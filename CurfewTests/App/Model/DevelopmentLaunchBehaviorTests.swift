import AppKit
@testable import Curfew
import Testing

struct DevelopmentLaunchBehaviorTests {
    private let studioBundleID = "studio.hypertext.apps.curfew.dev"
    private let personalDebugBundleID = "studio.hypertext.curfew.dev"
    private let releaseBundleID = "studio.hypertext.apps.curfew"

    @Test("Signed Curfew Dev launches arm enforcement without a developer environment variable")
    func studioDevelopmentLaunchStartsByDefault() {
        #expect(
            CurfewLaunchBehavior.shouldStartEnforcement(
                environment: [:],
                isDebugBuild: true,
                bundleIdentifier: studioBundleID,
                hasLoadedTestRuntime: false
            )
        )
        #expect(
            CurfewLaunchBehavior.shouldStartEnforcement(
                environment: [
                    "CURFEW_SKIP_ENFORCEMENT": "1",
                    "XCTestSessionIdentifier": "spoofed"
                ],
                isDebugBuild: true,
                bundleIdentifier: studioBundleID,
                hasLoadedTestRuntime: false
            )
        )
    }

    @Test("Only a loaded test runtime disarms Curfew Dev")
    func genuineTestHostRemainsDisarmed() {
        #expect(!CurfewLaunchBehavior.shouldStartEnforcement(
            environment: [:],
            isDebugBuild: true,
            bundleIdentifier: studioBundleID,
            hasLoadedTestRuntime: true
        ))
    }

    @Test("A unit-test host stays out of the Dock and the menu bar and opens no windows")
    func hostIsInvisible() {
        let hosted = CurfewLaunchBehavior.presentation(hostsUnitTests: true)
        #expect(hosted.activationPolicy == .accessory)
        #expect(!hosted.showsMenuBarItem)
        #expect(!hosted.opensWindowsOnLaunch)

        let ordinary = CurfewLaunchBehavior.presentation(hostsUnitTests: false)
        #expect(ordinary.activationPolicy == .regular)
        #expect(ordinary.showsMenuBarItem)
        #expect(ordinary.opensWindowsOnLaunch)
    }

    @Test("Only a Debug build takes the test configuration variable as proof of a test host")
    func hostPresentationNeedsDebugOrLoadedRuntime() {
        let injected = ["XCTestConfigurationFilePath": "/tmp/run.xctestconfiguration"]
        #expect(RuntimeEnvironment.hostsUnitTestsDecision(
            environment: injected, isDebugBuild: true, hasLoadedTestRuntime: false
        ))
        #expect(!RuntimeEnvironment.hostsUnitTestsDecision(
            environment: injected, isDebugBuild: false, hasLoadedTestRuntime: false
        ))
        #expect(RuntimeEnvironment.hostsUnitTestsDecision(
            environment: [:], isDebugBuild: false, hasLoadedTestRuntime: true
        ))
        #expect(!RuntimeEnvironment.hostsUnitTestsDecision(
            environment: [:], isDebugBuild: true, hasLoadedTestRuntime: false
        ))
    }

    @Test("Only a demo fixture asked to stay behind skips bringing itself forward")
    func captureCanStayBehind() {
        let asked = ["CURFEW_DEMO_STAY_BEHIND": "1"]
        #expect(RuntimeEnvironment.staysBehindDecision(isDemoFixture: true, environment: asked))
        #expect(!RuntimeEnvironment.staysBehindDecision(isDemoFixture: false, environment: asked))
        #expect(!RuntimeEnvironment.staysBehindDecision(isDemoFixture: true, environment: [:]))
    }

    @Test("Personal Debug cannot spoof Curfew Dev through the flavor environment")
    func personalDebugRemainsOptIn() {
        #expect(!CurfewLaunchBehavior.shouldStartEnforcement(
            environment: ["CURFEW_FLAVOR": "studioDevelopment"],
            isDebugBuild: true,
            bundleIdentifier: personalDebugBundleID,
            hasLoadedTestRuntime: false
        ))
    }

    @Test("Curfew Dev cannot enter the Debug demo fixture")
    func studioDevRejectsDemoFixture() {
        #expect(CurfewLaunchBehavior.demoScenario(
            environment: ["CURFEW_DEMO_FIXTURE": "1"],
            bundleIdentifier: studioBundleID, isSignedBuild: true
        ) == nil)
    }

    @Test("Spoofed XCTest environment cannot suppress signed app enforcement effects")
    func signedAppsRequireLoadedTestRuntime() {
        let spoofedEnvironment = ["XCTestSessionIdentifier": "spoofed"]
        #expect(!RuntimeEnvironment.testHostDecision(
            environment: spoofedEnvironment,
            bundleIdentifier: studioBundleID,
            hasLoadedTestRuntime: false
        ))
        #expect(RuntimeEnvironment.testHostDecision(
            environment: spoofedEnvironment,
            bundleIdentifier: studioBundleID,
            hasLoadedTestRuntime: true
        ))
        #expect(!RuntimeEnvironment.testHostDecision(
            environment: spoofedEnvironment,
            bundleIdentifier: personalDebugBundleID,
            hasLoadedTestRuntime: false
        ))
        #expect(!RuntimeEnvironment.testHostDecision(
            environment: spoofedEnvironment,
            bundleIdentifier: releaseBundleID,
            hasLoadedTestRuntime: false
        ))
    }
}
