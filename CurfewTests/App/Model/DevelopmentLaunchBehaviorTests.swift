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
