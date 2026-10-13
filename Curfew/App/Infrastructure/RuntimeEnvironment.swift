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
/// Detection accepts test environment markers for the personal Debug app, but
/// signed Studio Dev and Release apps require a loaded test runtime. Otherwise
/// a launch environment could silently suppress enforcement side effects.
enum RuntimeEnvironment {
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
        if bundleIdentifier != CurfewLaunchBehavior.personalDebugBundleIdentifier {
            return false
        }
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["DYLD_INSERT_LIBRARIES"]?.contains("libXCTestBundleInject") == true
    }

    /// Stronger test-host evidence for enforcement launch policy. An
    /// environment variable alone must not disarm a signed Studio Dev app.
    static var hasLoadedTestRuntime: Bool {
        if NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest") != nil {
            return true
        }
        return Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
    }
}
