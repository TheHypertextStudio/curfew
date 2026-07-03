import AppKit
import CurfewKit
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
        // Appearance is left to the system: CurfewTheme resolves every colour
        // adaptively (Aqua / Dark Aqua), so the chrome follows Light/Dark Mode
        // automatically.
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
    @State private var model: CurfewAppModel
    /// Sparkle wrapper driving the Check-for-Updates menu item.
    @State private var updater = CurfewUpdater()
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

    /// Constructs the app model, wires the `@State`-owned model, and defers
    /// the launch coordinator to the next run-loop spin so SwiftUI's
    /// first body evaluation completes before enforcement arms.
    init() {
        #if DEBUG
            if let scenario = CurfewLaunchBehavior.demoScenario(
                environment: ProcessInfo.processInfo.environment
            ) {
                let model = CurfewAppModel.demoModel()
                _model = State(wrappedValue: model)
                let demoAppearance: NSAppearance.Name =
                    ProcessInfo.processInfo.environment["CURFEW_DEMO_APPEARANCE"] == "dark"
                        ? .darkAqua
                        : .aqua
                DispatchQueue.main.async {
                    // Demo/capture builds only: pin a deterministic appearance so
                    // marketing screenshots don't depend on the capture machine's
                    // mode. Defaults to light; `CURFEW_DEMO_APPEARANCE=dark` pins
                    // dark so we can capture both. The shipping app itself follows
                    // the system — this pin is scoped to the demo fixture.
                    NSApplication.shared.appearance = NSAppearance(named: demoAppearance)
                    model.applyDemoScenario(scenario)
                }
                return
            }
        #endif

        let model = CurfewAppModel()
        _model = State(wrappedValue: model)

        // Hand the shared model to the AppKit delegate so it can re-assert
        // enforcement on app activation. Captured here and assigned on the next
        // run-loop spin alongside the launch coordinator, by which point the
        // delegate adaptor has produced its instance.
        let delegate = appDelegate
        DispatchQueue.main.async {
            delegate.model = model
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
                .environment(model)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        #if DEBUG
            .defaultLaunchBehavior(.presented)
        #endif
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

        MenuBarExtra {
            ContentView()
                .environment(model)
        } label: {
            // Morph between phase glyphs on change, and pulse when enforcement
            // is degraded so a silently-broken lockout draws the eye in the
            // menu bar. (Menu-bar symbol animation is best-effort; the glyph
            // itself always renders correctly.)
            Image(systemName: model.menuBarSymbolName)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: model.enforcementHealth != .active)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }

        // First-launch onboarding window. Replaces the hand-rolled
        // `NSWindowController` presenter: `MainWindowView` observes the model's
        // `gettingStartedRequestID` / `gettingStartedDismissID` triggers and
        // drives `openWindow` / `dismissWindow` for this group. Suppressed at
        // launch so it only appears when the model requests it.
        WindowGroup(id: CurfewAppModel.gettingStartedWindowID) {
            GettingStartedView()
                .environment(model)
        }
        .defaultSize(width: 620, height: 430)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// AppKit application delegate for Curfew.
///
/// SwiftUI's `App` lifecycle owns launch and scene composition; the delegate's
/// one job is to re-assert enforcement when the user returns to the Mac. On app
/// activation it re-polls Accessibility trust + tap liveness and, when locked,
/// restarts the keyboard shield and re-fronts the lockout overlay so a degraded
/// lockout recovers. System wake is handled by the model's own
/// `NSWorkspace` observers (see `CurfewAppModel.startEnforcementReassertionObservers`).
///
/// The shared model is injected by `CurfewApp.init` after the scene graph is
/// constructed; it is `weak` so the delegate never keeps the model alive past
/// the app's own lifetime.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The live app model, injected by `CurfewApp`. `weak` so the delegate
    /// observes rather than owns the model.
    weak var model: CurfewAppModel?

    /// AppKit calls this whenever Curfew becomes the active app — including the
    /// user clicking back into a Curfew window after being away. Re-assert
    /// enforcement so a lockout that degraded while we were in the background
    /// recovers. No-ops when not locked.
    func applicationDidBecomeActive(_ notification: Notification) {
        model?.reassertEnforcementIfNeeded()
    }
}
