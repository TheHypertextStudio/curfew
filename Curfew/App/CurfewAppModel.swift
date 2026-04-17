import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Central `ObservableObject` that every Curfew UI surface binds to.
///
/// Responsibilities, in roughly the order they fire each tick:
/// 1. Hold user-facing state (`settings`, `state`, `currentTime`, remaining
///    budgets, override composer flags). All `@Published` so SwiftUI diffs.
/// 2. Drive the 1 Hz tick loop that recomputes `CurfewEvaluation` via the
///    `CurfewEnforcementEngine`.
/// 3. Translate the engine result into the shape UI needs (menu bar symbol,
///    one-line status, snapshot) — see `CurfewAppModel+Presentation`.
/// 4. Route user actions (apply preset, edit schedule, request extension,
///    confirm override) — see `CurfewAppModel+Actions`.
/// 5. React to state changes — schedule swap, lockout entry, shutdown
///    workflow, key interception — see `CurfewAppModel+Lifecycle`.
///
/// The class body here holds stored state and the three initialisers;
/// everything behavioural lives in the adjacent extension files. Splitting
/// this way keeps any one file under SwiftLint's length thresholds and
/// groups related code by responsibility rather than visibility modifier.
///
/// Marked `@MainActor` because it reads and writes AppKit + SwiftUI state,
/// and the tick timer fires on the main run loop.
@MainActor
final class CurfewAppModel: NSObject, ObservableObject {
    /// How long the user must hold the extension button before the request
    /// is consumed. Prevents accidental taps from burning a weekly budget
    /// slot. Also exposed to `EnforcementSnapshot.extensionRequestTitle` so
    /// the UI copy stays in sync with the actual hold duration.
    static let extensionConfirmationHoldSeconds: Double = 2

    /// Whether the first-launch Settings window should open automatically
    /// after boot. Set once by the settings store during init, then never
    /// again — re-invoking onboarding from Settings uses a different path.
    let shouldOpenSettingsOnLaunch: Bool

    /// Runtime module flags (widgets, cloud sync, MCP, privileged helper).
    /// See ``FeatureFlags``.
    let featureFlags: FeatureFlags

    /// Persisted user settings (schedule, budgets, notification preferences,
    /// warning intervals). Mutations trigger `handleSettingsMutation` via
    /// `didSet` so budget trackers stay in sync with user edits.
    @Published var settings: CurfewSettings {
        didSet {
            handleSettingsMutation(from: oldValue)
        }
    }

    /// Latest evaluation from the enforcement engine. Replaced every tick.
    @Published var state: CurfewEvaluation

    /// Cached clock value. Updated at the top of each tick so all downstream
    /// logic within one tick agrees on "now".
    @Published var currentTime: Date = .init()

    /// Remaining weekly extensions. Mirror of `extensionTracker.remaining`
    /// lifted to `@Published` so SwiftUI can observe it directly.
    @Published var extensionsRemaining: Int

    /// Remaining weekly overrides. Mirror of `overrideTracker.remaining`.
    @Published var overridesRemaining: Int

    /// Current lockout-screen encouragement message. Rotates once per
    /// `.working → .locked` transition via `EncouragementMessageCatalog`.
    @Published var lockoutMessage: String

    /// Text the user is typing in the override reason box. Surfaced live so
    /// character-count UI (the "Convince Me" flow requires ≥50 chars) stays
    /// responsive to every keystroke.
    @Published var overrideReasonDraft: String = ""

    /// End time of the 5-minute cooldown before the override composer can
    /// be confirmed. `nil` when no override attempt is in progress.
    @Published var overrideCooldownEndsAt: Date?

    /// Whether the override composer sheet is currently presented on the
    /// lockout screen.
    @Published var isOverrideComposerVisible = false

    /// One-line status describing the auto-shutdown workflow (e.g. a
    /// countdown), or `nil` when no shutdown is pending.
    @Published var shutdownStatusLine: String?

    /// Persisted log of granted overrides, newest last. Populated from the
    /// settings store at init and appended to whenever `confirmOverride()`
    /// succeeds.
    @Published private(set) var overrideEvents: [OverrideEvent]

    // MARK: - Collaborators

    //
    // Kept at module-internal visibility (default `internal`) rather than
    // `private` so the extension files in `CurfewAppModel+*.swift` can
    // reach them. Swift requires this because extensions in separate files
    // cannot access the containing type's `private` storage.

    /// Read/write access to persisted settings + override event log.
    let settingsStore: CurfewSettingsStore

    /// Classifies proposed schedule changes as stricter / weaker / no-change
    /// to drive the anti-bypass cooldown rules.
    let policyEngine: SchedulePolicyEngine

    /// Pure function that turns (schedule, now, extensions, override) into a
    /// `CurfewEvaluation`. Injected for testability.
    let enforcementEngine: CurfewEnforcementEngine

    /// Delivers warning-stage user notifications and surfaces snooze taps
    /// back via `onSnoozeRequested`.
    let notificationManager: WarningNotificationManager

    /// Manages the dim / warning / lockout overlay NSWindows across displays.
    let overlayCoordinator: OverlayCoordinator

    /// CGEventTap installer that blocks bypass keyboard shortcuts during
    /// lockout (⌘⇥, ⌘Q, ⌘⌥Esc, …).
    let lockoutKeyInterceptor: LockoutKeyInterceptor

    /// AppleScript wrapper for auto-shutdown. Abstracted behind a protocol
    /// so tests can assert the sequence without telling the OS to power off.
    let shutdownController: ShutdownControlling

    /// Abstraction over "activate + show Settings". Tests substitute a spy.
    let appRouter: AppRouting

    /// Presenter for the first-launch onboarding window.
    let gettingStartedPresenter: GettingStartedPresenting

    /// Tracks weekly extension budget consumption. Rebuilt when the user
    /// edits their extension config.
    var extensionTracker: ExtensionBudgetTracker

    /// Tracks weekly override budget consumption. Rebuilt when the user
    /// edits their override config.
    var overrideTracker: ExtensionBudgetTracker

    /// The 1 Hz repeating tick timer. `nil` until `start()` is called.
    /// Only used inside the main class body — kept `private`.
    private var timer: Timer?

    /// Sum of extension minutes granted since the current day rolled over.
    /// Resets in `tick()` when `dayToken(for: currentTime)` changes.
    var extensionMinutesGrantedToday = 0

    /// Count of 1-minute snoozes granted today. Treated equivalently to
    /// extension minutes when the engine computes `extensionMinutesGrantedToday`.
    var snoozeMinutesGrantedToday = 0

    /// `YYYY-M-D` token representing the last-seen calendar day, so `tick()`
    /// can detect day rollovers without depending on a NotificationCenter.
    var currentDayToken = ""

    /// When non-nil, "Convince Me" override is active until this date —
    /// the engine continues returning `.working` until `now >= overrideUntil`.
    var overrideUntil: Date?

    /// Value-typed state machine driving auto-shutdown after lockout begins.
    /// See ``ShutdownWorkflow``.
    var shutdownWorkflow = ShutdownWorkflow()

    /// Guard flag so `start()` is idempotent — prevents duplicate timers if
    /// the setup-complete callback fires twice. Only used inside the main
    /// class body.
    private var started = false

    /// Production / test-friendly designated initialiser. Every other
    /// initialiser delegates here.
    ///
    /// `settingsStore`, `appRouter`, and `gettingStartedPresenter` are
    /// injected so tests can substitute fakes; everything else is built
    /// internally because the production engines have no knobs worth
    /// varying in tests.
    ///
    /// The initial `state` is computed *before* `super.init()` runs because
    /// `@Published` stored properties must be assigned before the NSObject
    /// subclass completes initialisation. `configureNotificationCallback()`
    /// runs after `super.init()` since it passes `self` into a closure.
    init(
        settingsStore: CurfewSettingsStore,
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting,
        featureFlags: FeatureFlags = .default
    ) {
        self.settingsStore = settingsStore
        self.policyEngine = SchedulePolicyEngine()
        let enforcementEngine = CurfewEnforcementEngine()
        self.enforcementEngine = enforcementEngine
        self.notificationManager = WarningNotificationManager()
        self.overlayCoordinator = OverlayCoordinator()
        self.lockoutKeyInterceptor = LockoutKeyInterceptor()
        self.shutdownController = SystemShutdownController()
        self.appRouter = appRouter
        self.gettingStartedPresenter = gettingStartedPresenter
        self.featureFlags = featureFlags

        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.shouldOpenSettingsOnLaunch = settingsStore.consumeShouldShowInitialSetup()
        self.overrideEvents = settingsStore.loadOverrideEvents()

        self.extensionTracker = ExtensionBudgetTracker(
            weeklyLimit: loadedSettings.extensionWeeklyLimit,
            extensionMinutes: loadedSettings.extensionDurationMinutes,
            resetWeekday: loadedSettings.resetWeekday
        )
        self.overrideTracker = ExtensionBudgetTracker(
            weeklyLimit: loadedSettings.overrideWeeklyLimit,
            extensionMinutes: loadedSettings.overrideDurationMinutes,
            resetWeekday: loadedSettings.resetWeekday
        )

        let now = Date()
        self.state = Self.initialEvaluation(
            settings: loadedSettings,
            now: now,
            enforcementEngine: enforcementEngine
        )
        self.extensionsRemaining = extensionTracker.remaining
        self.overridesRemaining = overrideTracker.remaining
        self.lockoutMessage = EncouragementMessageCatalog.next(after: nil)
        self.shutdownStatusLine = nil
        self.currentDayToken = Self.dayToken(for: now)
        super.init()

        configureNotificationCallback()
    }

    /// Convenience initialiser used by the main app when only routing and
    /// onboarding presenter customisation is needed — in that case, the
    /// settings store is built with its defaults.
    convenience init(
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting
    ) {
        self.init(
            settingsStore: CurfewSettingsStore(),
            appRouter: appRouter,
            gettingStartedPresenter: gettingStartedPresenter
        )
    }

    /// Zero-arg convenience used by `CurfewApp` at production launch. All
    /// collaborators resolve to their `System*` defaults.
    override convenience init() {
        self.init(
            settingsStore: CurfewSettingsStore(),
            appRouter: SystemAppRouter(),
            gettingStartedPresenter: GettingStartedWindowPresenter()
        )
    }

    /// Wires the notification manager's snooze callback back into the model
    /// after `super.init()` completes. Lifted out of the initialiser body
    /// because closures capturing `self` must run post-init.
    private func configureNotificationCallback() {
        notificationManager.onSnoozeRequested = { [weak self] in
            self?.requestNotificationSnooze()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Starts the 1 Hz enforcement tick. Safe to call repeatedly; no-ops
    /// when the user has not completed onboarding (we don't want a half-
    /// configured schedule firing warnings) or when already running.
    func start() {
        guard settings.hasCompletedInitialSetup else {
            return
        }
        guard !started else {
            return
        }
        started = true
        notificationManager.requestPermissionIfNeeded()
        tick()
        timer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(handleTimerFire(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    /// Whether `start()` has successfully armed the tick timer. Used by the
    /// UI to show a "Start enforcement" button in Debug builds where
    /// auto-start is disabled.
    var isEnforcementRunning: Bool {
        started
    }

    /// Timer-target bridge. Swift `Timer` requires a `@objc` selector, and
    /// `tick()` must remain callable from Swift too, so we trampoline here.
    @objc
    private func handleTimerFire(_ timer: Timer) {
        tick()
    }

    /// Persists the given override event and appends it to the published
    /// in-memory log.
    ///
    /// Exists because `overrideEvents` is `@Published private(set)` — the
    /// private setter is file-scoped, so extensions in sibling files cannot
    /// mutate the array directly. Routing every append through this method
    /// preserves the read-only public API while letting the actions
    /// extension record events.
    func recordOverrideEvent(_ event: OverrideEvent) {
        settingsStore.appendOverrideEvent(event)
        overrideEvents.append(event)
    }
}
