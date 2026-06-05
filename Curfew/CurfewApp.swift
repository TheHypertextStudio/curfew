import AppKit
import SwiftUI

/// Narrow seam exercised by `CurfewApp.init` on first launch. Separated
/// into a protocol so tests can assert the boot decisions (start
/// enforcement? show Getting Started?) without a SwiftUI app scene.
protocol AppCoordinating {
    /// Invoked once per launch on the main actor. `model` is the live
    /// `CurfewAppModel`; `shouldStartEnforcement` is the result of
    /// `CurfewLaunchBehavior.shouldStartEnforcement` applied to the
    /// current environment.
    @MainActor
    func handleInitialLaunch(
        model: CurfewAppModel,
        shouldStartEnforcement: Bool
    )
}

/// Production `AppCoordinating` — arms the tick loop (when the launch
/// policy allows) and opens Getting Started when the settings store
/// says first-launch setup hasn't been completed yet.
struct AppCoordinator: AppCoordinating {
    /// Concrete launch orchestration. Called from `CurfewApp.init`.
    @MainActor
    func handleInitialLaunch(
        model: CurfewAppModel,
        shouldStartEnforcement: Bool
    ) {
        if shouldStartEnforcement {
            model.start()
        }

        if model.shouldOpenSettingsOnLaunch {
            model.showGettingStarted()
        }
    }
}

/// Policy for whether the app arms enforcement on launch. Debug builds
/// stay disarmed unless explicitly opted in via `CURFEW_ENABLE_ENFORCEMENT=1`
/// so development doesn't accidentally lock the developer out. Release
/// builds always arm — `CURFEW_SKIP_ENFORCEMENT=1` is honored only in
/// Debug. Once a binary is notarised and distributed, a user-controllable
/// env var must not be able to disable the lockout: that would be a
/// trivial bypass. CI smoke tests that need to launch without enforcement
/// use Debug builds (or a dedicated launch argument the harness controls).
enum CurfewLaunchBehavior {
    /// Returns `true` when enforcement should arm at launch given the
    /// current environment and build configuration.
    static func shouldStartEnforcement(
        environment: [String: String],
        isDebugBuild: Bool
    ) -> Bool {
        if isDebugBuild {
            return environment["CURFEW_ENABLE_ENFORCEMENT"] == "1"
        }
        return true
    }

    #if DEBUG
        /// Resolves the demo-capture scenario from the environment, or `nil`
        /// when `CURFEW_DEMO_FIXTURE` is not set to `1`. Unknown scenario
        /// tokens fall back to `.overview`. Debug-only: Release builds neither
        /// compile nor honour this flag.
        static func demoScenario(environment: [String: String]) -> DemoScenario? {
            guard environment["CURFEW_DEMO_FIXTURE"] == "1" else {
                return nil
            }
            let token = environment["CURFEW_DEMO_SCENARIO"] ?? ""
            return DemoScenario(rawValue: token) ?? .overview
        }
    #endif
}

/// SwiftUI app entry point. Composes the three scenes users interact
/// with (main window, menu-bar extra, Settings) and hangs the launch
/// coordinator off `init` so enforcement arms before the first frame.
@main
struct CurfewApp: App {
    /// The central app-state object; injected into every scene.
    @StateObject private var model: CurfewAppModel
    /// Sparkle wrapper driving the Check-for-Updates menu item.
    @StateObject private var updater = CurfewUpdater()
    /// AppKit delegate seam. A no-op today; a later workflow hangs
    /// activation / wake re-assertion of the keyboard shield off it so a
    /// degraded lockout can recover when the user returns to the Mac.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let shouldStartEnforcementOnLaunch = CurfewLaunchBehavior.shouldStartEnforcement(
        environment: ProcessInfo.processInfo.environment,
        isDebugBuild: isDebugBuild
    )

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// Constructs the app model, wires the `@StateObject`, and defers
    /// the launch coordinator to the next run-loop spin so SwiftUI's
    /// first body evaluation completes before enforcement arms.
    init() {
        #if DEBUG
            if let scenario = CurfewLaunchBehavior.demoScenario(
                environment: ProcessInfo.processInfo.environment
            ) {
                let model = CurfewAppModel.demoModel()
                _model = StateObject(wrappedValue: model)
                DispatchQueue.main.async {
                    model.applyDemoScenario(scenario)
                }
                return
            }
        #endif

        let model = CurfewAppModel()
        _model = StateObject(wrappedValue: model)

        DispatchQueue.main.async {
            AppCoordinator().handleInitialLaunch(
                model: model,
                shouldStartEnforcement: Self.shouldStartEnforcementOnLaunch
            )
        }
    }

    /// Scene composition: main window + menu bar + Settings pane.
    var body: some Scene {
        WindowGroup(id: MainWorkspaceSection.windowID) {
            MainWindowView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            if CurfewUpdater.isAvailable {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }
        }

        MenuBarExtra("Curfew", systemImage: model.menuBarSymbolName) {
            ContentView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 520)
        }
    }
}

/// AppKit application delegate for Curfew.
///
/// Intentionally minimal for now: SwiftUI's `App` lifecycle owns launch and
/// scene composition, and the enforcement re-assertion hooks (re-check
/// Accessibility trust and restart the keyboard shield on app activation and
/// system wake) land in a later workflow. This stub exists so that wiring has
/// a delegate to attach to without reshaping the SwiftUI entry point again.
final class AppDelegate: NSObject, NSApplicationDelegate {}
