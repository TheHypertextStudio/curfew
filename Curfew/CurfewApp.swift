import AppKit
import CurfewKit
import ServiceManagement
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
        // Open the audit stream before anything can transition, so the first
        // enforcement decision of the process has a line above it explaining
        // what state the app booted into. Skipped in the unit-test host: the
        // suite must never append to the user's real ~/Library/Logs/Curfew.
        if !RuntimeEnvironment.isUnitTestHost {
            AuditLog.bootstrap(stream: .app)
            model.recordAuditAppLaunched(enforcementArmed: shouldStartEnforcement)
        }

        // Always run the display clock so the countdown, sky, and health stay
        // live even when enforcement isn't armed (Debug `just dev`, pre-
        // onboarding, or Curfew off). Enforcement — the actual locking — stays
        // gated behind `start()` below, so a disarmed app is live but never
        // locks the Mac.
        model.beginDisplayClock()

        if shouldStartEnforcement {
            model.start()
        }

        if model.shouldOpenSettingsOnLaunch,
           !CurfewLaunchBehavior.isBackgroundLaunch(arguments: ProcessInfo.processInfo.arguments) {
            model.showGettingStarted()
        }
    }
}

/// Both installed apps arm enforcement on ordinary launch. Curfew Dev uses
/// the staging services and retains its separate schedule consent. It arms
/// like Release despite being compiled with `DEBUG`, so
/// an authenticated remote lock cannot be accepted by its helper while the
/// app remains in display-only mode. Only loaded test runtimes are excluded.
enum CurfewLaunchBehavior {
    static func isBackgroundLaunch(arguments: [String]) -> Bool {
        arguments.contains("--background")
    }

    static let developmentBundleIdentifier = CurfewFlavor.development.bundleIdentifier

    /// Returns `true` when enforcement should arm at launch given the
    /// actual app identity and build configuration. Environment-only test
    /// markers cannot disarm a signed app.
    static func shouldStartEnforcement(
        environment: [String: String],
        isDebugBuild: Bool,
        bundleIdentifier: String? = nil,
        hasLoadedTestRuntime: Bool = false
    ) -> Bool {
        guard !hasLoadedTestRuntime else { return false }
        if isDebugBuild, bundleIdentifier != developmentBundleIdentifier {
            return environment["CURFEW_ENABLE_ENFORCEMENT"] == "1"
        }
        return true
    }

    #if DEBUG
        /// Resolves the demo-capture scenario from the environment, or `nil`
        /// when `CURFEW_DEMO_FIXTURE` is not set to `1`. Unknown scenario
        /// tokens fall back to `.overview`. Debug-only: Release builds neither
        /// compile nor honour this flag.
        static func demoScenario(
            environment: [String: String],
            bundleIdentifier: String? = Bundle.main.bundleIdentifier,
            isSignedBuild: Bool = DaemonSigningIdentity.current != nil
        ) -> DemoScenario? {
            if RuntimeEnvironment.isStagingAcceptanceFixture {
                return .backgroundEnforcement
            }
            guard !isSignedBuild else { return nil }
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

    private static let backgroundLaunch = CurfewLaunchBehavior.isBackgroundLaunch(
        arguments: ProcessInfo.processInfo.arguments
    )

    private static let shouldStartEnforcementOnLaunch = CurfewLaunchBehavior.shouldStartEnforcement(
        environment: ProcessInfo.processInfo.environment,
        isDebugBuild: isDebugBuild,
        bundleIdentifier: Bundle.main.bundleIdentifier,
        hasLoadedTestRuntime: RuntimeEnvironment.hasLoadedTestRuntime
    )

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// Forced colour scheme for demo/capture launches, or `nil` to follow the
    /// system. `CURFEW_DEMO_APPEARANCE=dark` pins dark so headless captures can
    /// grab dark-mode stills of a backgrounded window (where an
    /// `NSApplication.appearance` assignment doesn't reliably re-render). Only
    /// active in Debug demo launches; the shipping app always returns `nil` and
    /// follows Light/Dark Mode.
    private static var demoColorScheme: ColorScheme? {
        #if DEBUG
            let env = ProcessInfo.processInfo.environment
            guard CurfewLaunchBehavior.demoScenario(environment: env) != nil else {
                return nil
            }
            return env["CURFEW_DEMO_APPEARANCE"] == "dark" ? .dark : .light
        #else
            nil
        #endif
    }

    /// Exercises menu-bar-only launch in the unsigned UI fixture, matching a
    /// release launch where the main workspace has never been constructed.
    private static var demoStartsWithoutMainWindow: Bool {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            return CurfewLaunchBehavior.demoScenario(environment: environment) != nil &&
                environment["CURFEW_DEMO_WITHOUT_MAIN_WINDOW"] == "1"
        #else
            false
        #endif
    }

    private static var suppressesOrdinaryWindows: Bool {
        backgroundLaunch || demoStartsWithoutMainWindow
    }

    /// Constructs the app model, wires the `@State`-owned model, and defers
    /// the launch coordinator to the next run-loop spin so SwiftUI's
    /// first body evaluation completes before enforcement arms.
    init() {
        Self.handleBackgroundServiceCommand()
        #if DEBUG
            if let scenario = CurfewLaunchBehavior.demoScenario(
                environment: Self.demoEnvironment
            ) {
                let model = CurfewAppModel.demoModel(
                    backgroundEnforcement: scenario == .backgroundEnforcement
                )
                _model = State(wrappedValue: model)
                let delegate = appDelegate
                let demoAppearance: NSAppearance.Name =
                    ProcessInfo.processInfo.environment["CURFEW_DEMO_APPEARANCE"] == "dark"
                        ? .darkAqua
                        : .aqua
                DispatchQueue.main.async {
                    delegate.model = model
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

    #if DEBUG
        private static var demoEnvironment: [String: String] {
            var environment = ProcessInfo.processInfo.environment
            #if CURFEW_STAGING
                if ProcessInfo.processInfo.arguments.contains("--supervisor-acceptance") {
                    environment["CURFEW_DEMO_FIXTURE"] = "1"
                    environment["CURFEW_DEMO_SCENARIO"] = "background-enforcement"
                }
            #endif
            return environment
        }
    #endif

    /// Scene composition: main window + menu bar + Settings pane.
    var body: some Scene {
        Window("Curfew", id: MainWorkspaceSection.windowID) {
            MainWindowView()
                .environment(model)
                .appWindowRouting(using: model.appRouter)
                .disabled(model.privilegedHelperManager.repairInProgress)
                .frame(minWidth: 980, minHeight: 660)
                .onOpenURL { _ = model.handleIncomingURL($0) }
                .demoWindowSize(width: 1080, height: 720, minimumWidth: 980, minimumHeight: 660)
                .preferredColorScheme(Self.demoColorScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(Self.suppressesOrdinaryWindows ? .suppressed : .presented)
        .restorationBehavior(Self.backgroundLaunch ? .disabled : .automatic)
        .commands {
            MainWorkspaceCommands(delegate: appDelegate)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }

        MenuBarExtra {
            ContentView()
                .preferredColorScheme(Self.demoColorScheme)
                .environment(model)
                .onOpenURL { _ = model.handleIncomingURL($0) }
        } label: {
            // Morph between phase glyphs on change, and pulse when enforcement
            // is degraded so a silently-broken lockout draws the eye in the
            // menu bar. (Menu-bar symbol animation is best-effort; the glyph
            // itself always renders correctly.)
            Image(systemName: model.menuBarSymbolName)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: model.enforcementHealth != .active)
                .accessibilityLabel("Curfew\(CurfewFlavor.current.displaySuffix) status")
                .accessibilityIdentifier("curfew-status-item")
                .accessibilityValue(model.menuBarHeaderLine)
                .appWindowRouting(using: model.appRouter)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .preferredColorScheme(Self.demoColorScheme)
                .environment(model)
                .appWindowRouting(using: model.appRouter)
                .frame(minWidth: 760, minHeight: 520)
                .onOpenURL { _ = model.handleIncomingURL($0) }
                .demoWindowSize(width: 860, height: 620, minimumWidth: 760, minimumHeight: 520)
        }

        .restorationBehavior(Self.backgroundLaunch ? .disabled : .automatic)

        // Suppressed at launch; setup is opened on request through any available
        // scene, and can dismiss itself without a main workspace window.
        Window("Set Up Curfew", id: CurfewAppModel.gettingStartedWindowID) {
            GettingStartedView()
                .environment(model)
                .appWindowRouting(using: model.appRouter)
                .preferredColorScheme(Self.demoColorScheme)
        }
        .defaultSize(width: 620, height: 430)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(Self.backgroundLaunch ? .disabled : .automatic)
    }
}

private struct MainWorkspaceCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let delegate: AppDelegate

    var body: some Commands {
        delegate.openMainWindow = { openWindow(id: MainWorkspaceSection.windowID) }
        return CommandGroup(after: .windowArrangement) {
            Button("Open Curfew") { openWindow(id: MainWorkspaceSection.windowID) }
        }
    }
}
