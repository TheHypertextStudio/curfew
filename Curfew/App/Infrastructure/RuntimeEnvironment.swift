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
/// Detection is deliberately broad so it works for BOTH XCTest and Swift
/// Testing (which `xcodebuild test` bootstraps through the XCTest host): any of
/// the standard test environment variables, a loaded XCTest runtime, or an
/// injected `.xctest` bundle marks the process as a test host. Production
/// launches match none of these and behave normally.
enum RuntimeEnvironment {
    /// `true` when running inside an `xcodebuild test` host process.
    static var isUnitTestHost: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || env["DYLD_INSERT_LIBRARIES"]?.contains("libXCTestBundleInject") == true {
            return true
        }
        if NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest") != nil {
            return true
        }
        return Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
    }
}
