import CurfewKit
import Foundation

/// Detects whether the production app is running purely as a unit-test host.
///
/// `xcodebuild test` re-signs the app with a throwaway ad-hoc signature on
/// every run, so macOS treats it as a brand-new app and re-prompts for any
/// TCC-gated capability. We use this flag to suppress the side effects that
/// trigger those prompts in a test host — installing the Accessibility event
/// tap, writing the App Group container (the per-tick heartbeat / widget
/// mirror), and requesting Notifications authorization — so the developer is
/// never spammed with permission dialogs on every run.
///
/// Both Curfew and Curfew Dev require a loaded test runtime. Otherwise
/// a launch environment could silently suppress enforcement side effects.
nonisolated enum RuntimeEnvironment {
    static var shouldInstallKeyboardInterceptor: Bool {
        #if DEBUG && CURFEW_STAGING
            let staging = true
            let backgroundAcceptance = ProcessInfo.processInfo.arguments
                .contains("--supervisor-acceptance")
                || ProcessInfo.processInfo.environment["CURFEW_DEMO_SCENARIO"]
                == "background-enforcement"
        #else
            let staging = false
            let backgroundAcceptance = false
        #endif
        return permitsKeyboardInterception(
            testHost: isUnitTestHost, demo: isDemoFixture, staging: staging,
            acceptanceOptIn: Bundle.main.object(
                forInfoDictionaryKey: "CurfewAcceptanceKeyboardShield"
            ) as? Bool == true,
            backgroundAcceptance: backgroundAcceptance
        )
    }

    static func permitsKeyboardInterception(
        testHost: Bool, demo: Bool, staging: Bool, acceptanceOptIn: Bool,
        backgroundAcceptance: Bool
    ) -> Bool {
        !testHost && (!demo || (staging && acceptanceOptIn && backgroundAcceptance))
    }

    static var isStagingAcceptanceFixture: Bool {
        #if DEBUG && CURFEW_STAGING
            ProcessInfo.processInfo.arguments.contains("--supervisor-acceptance") &&
                Bundle.main.object(forInfoDictionaryKey: "CurfewAcceptanceFixture") as? Bool == true
        #else
            false
        #endif
    }

    static var isDemoFixture: Bool {
        #if DEBUG
            isStagingAcceptanceFixture ||
                (DaemonSigningIdentity.current == nil &&
                    ProcessInfo.processInfo.environment["CURFEW_DEMO_FIXTURE"] == "1")
        #else
            false
        #endif
    }

    /// Capture runs only: with `CURFEW_DEMO_STAY_BEHIND=1` the demo fixture
    /// never brings itself forward, so recording it does not take the keyboard
    /// away from whoever is working on this Mac.
    static var staysBehindForCapture: Bool {
        staysBehindDecision(
            isDemoFixture: isDemoFixture, environment: ProcessInfo.processInfo.environment
        )
    }

    static func staysBehindDecision(isDemoFixture: Bool, environment: [String: String]) -> Bool {
        isDemoFixture && environment["CURFEW_DEMO_STAY_BEHIND"] == "1"
    }

    /// `true` when running inside an `xcodebuild test` host process.
    static var isUnitTestHost: Bool {
        testHostDecision(
            environment: ProcessInfo.processInfo.environment,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            hasLoadedTestRuntime: hasLoadedTestRuntime
        )
    }

    static func testHostDecision(
        environment: [String: String],
        bundleIdentifier: String?,
        hasLoadedTestRuntime: Bool
    ) -> Bool {
        if hasLoadedTestRuntime {
            return true
        }
        return false
    }

    /// `true` when this process hosts unit tests, known early enough to
    /// decide how the app presents itself (Dock, menu bar, windows).
    static var hostsUnitTests: Bool {
        #if DEBUG
            let isDebugBuild = true
        #else
            let isDebugBuild = false
        #endif
        return hostsUnitTestsDecision(
            environment: ProcessInfo.processInfo.environment,
            isDebugBuild: isDebugBuild,
            hasLoadedTestRuntime: hasLoadedTestRuntime
        )
    }

    /// The test runtime can load after the scenes are first built, so a Debug
    /// build also accepts the configuration path `xcodebuild test` passes to
    /// its host. This decides presentation only. It never disarms
    /// enforcement, which still requires a loaded test runtime.
    static func hostsUnitTestsDecision(
        environment: [String: String],
        isDebugBuild: Bool,
        hasLoadedTestRuntime: Bool
    ) -> Bool {
        if hasLoadedTestRuntime {
            return true
        }
        return isDebugBuild && environment["XCTestConfigurationFilePath"] != nil
    }

    /// Stronger test-host evidence for enforcement launch policy. An
    /// environment variable alone must not disarm a signed Curfew Dev app.
    static var hasLoadedTestRuntime: Bool {
        if NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest") != nil {
            return true
        }
        return Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
    }
}
