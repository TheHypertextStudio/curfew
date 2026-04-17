import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog
import SwiftUI

/// Central `ObservableObject` for Curfew. Holds all `@Published` state,
/// drives the 1 Hz tick loop, and exposes the designated initialiser.
/// Behaviour is split across extension files: Actions, Lifecycle,
/// Presentation, Setup. `@MainActor` throughout — reads and writes
/// AppKit + SwiftUI state and the tick timer fires on the main run loop.
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

    /// Pro license gate. Verifies the stored license key on startup and
    /// exposes `isProUnlocked` for all Pro-gated surfaces.
    let licenseGate: LicenseGate

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

    /// MCP write requests waiting for user approval. Non-empty triggers the
    /// ``MCPConsentSheet`` on the front window. Entries are removed once the
    /// user approves or denies.
    @Published var pendingMCPRequests: [MCPPendingRequest] = []

    /// Whether the AI consent policy allows queuing MCP write requests.
    /// Persisted in settings when user changes it in Settings → Integrations.
    @Published var aiConsentPolicy: AIConsentPolicy = .queue

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

    /// Watches the MCP request queue file for new write requests and fires
    /// `pendingMCPRequests` updates so the UI can show consent sheets.
    let mcpRequestMonitor: MCPRequestMonitor

    /// Syncs settings to iCloud when `featureFlags.cloudSyncEnabled` and
    /// `licenseGate.isProUnlocked`. Dormant by default; started from
    /// lifecycle once both conditions are satisfied.
    let cloudKitSyncEngine: CloudKitSyncEngine

    /// Reads today's calendar events for contextual display on the lockout
    /// screen and This Week view. Requires `featureFlags.calendarEnabled`
    /// and `licenseGate.isProUnlocked`. Never started in free tier.
    let calendarMonitor: CalendarMonitor

    /// Manages the `SMAppService`-registered privileged daemon and the
    /// main-app login item. Surfaces Install/Uninstall actions in
    /// Settings → Integrations when `featureFlags.privilegedHelperEnabled`.
    let privilegedHelperManager: PrivilegedHelperManager

    /// Writes lifecycle / extension / override events to the activity
    /// log. Always non-nil; when the SQLite store can't be opened
    /// (sandbox denied, disk full), this holds a ``NullActivityRecording``
    /// that silently discards writes. Tests may inject a
    /// `NullActivityRecording` directly to bypass I/O.
    let activityRecorder: any ActivityRecording

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

    /// The event identifier of the calendar event for which we've already
    /// delivered a "meeting near curfew" extension prompt today. Reset to
    /// `nil` on day rollover so the next day's events get their own prompt.
    var curfewOverlapPromptFiredForEventID: String?

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
        featureFlags: FeatureFlags = .default,
        activityRecorder: any ActivityRecording,
        mcpRequestMonitor: MCPRequestMonitor = MCPRequestMonitor(),
        licenseGate: LicenseGate = LicenseGate(),
        cloudKitSyncEngine: CloudKitSyncEngine = CloudKitSyncEngine(),
        calendarMonitor: CalendarMonitor = CalendarMonitor(),
        privilegedHelperManager: PrivilegedHelperManager = PrivilegedHelperManager()
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
        self.activityRecorder = activityRecorder
        self.mcpRequestMonitor = mcpRequestMonitor
        self.licenseGate = licenseGate
        self.cloudKitSyncEngine = cloudKitSyncEngine
        self.calendarMonitor = calendarMonitor
        self.privilegedHelperManager = privilegedHelperManager

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

    /// Convenience for tests that only need to override the routing /
    /// onboarding presenter; defaults everything else (including the
    /// activity recorder, which falls back to the null recording when the
    /// SQLite store cannot be opened).
    convenience init(
        settingsStore: CurfewSettingsStore,
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting,
        featureFlags: FeatureFlags = .default
    ) {
        self.init(
            settingsStore: settingsStore,
            appRouter: appRouter,
            gettingStartedPresenter: gettingStartedPresenter,
            featureFlags: featureFlags,
            activityRecorder: Self.defaultActivityRecording()
        )
    }

    /// Convenience for call sites that only want to override routing +
    /// onboarding presenter; uses a default ``CurfewSettingsStore``.
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

    /// Wires the notification manager's snooze callback and MCP request
    /// monitor back into the model after `super.init()` completes. Lifted
    /// out of the initialiser body because closures capturing `self` must
    /// run post-init.
    private func configureNotificationCallback() {
        notificationManager.onSnoozeRequested = { [weak self] in
            self?.requestNotificationSnooze()
        }
        mcpRequestMonitor.onNewRequests = { [weak self] requests in
            self?.handleNewMCPRequests(requests)
        }
        if settings.mcpEnabled {
            mcpRequestMonitor.start()
        }
        licenseGate.loadStoredKey()

        cloudKitSyncEngine.onSettingsReceived = { [weak self] remoteSettings in
            guard let self else { return }
            settings = remoteSettings
            settingsStore.save(remoteSettings)
        }
        if featureFlags.cloudSyncEnabled, licenseGate.isProUnlocked {
            cloudKitSyncEngine.start(
                localSettings: settings,
                localModifiedAt: Date()
            )
        }
        if featureFlags.calendarEnabled, licenseGate.isProUnlocked {
            calendarMonitor.requestAccessAndSync()
        }
        if featureFlags.privilegedHelperEnabled {
            privilegedHelperManager.refreshStatus()
        }
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

    /// Whether `start()` has successfully armed the tick timer.
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
    /// in-memory log. Exists because `overrideEvents` is `@Published
    /// private(set)` — extensions in sibling files cannot mutate the array
    /// directly.
    func recordOverrideEvent(_ event: OverrideEvent) {
        settingsStore.appendOverrideEvent(event)
        overrideEvents.append(event)
        activityRecorder.recordOverrideGranted(
            minutes: event.grantedDurationMinutes,
            reason: event.reason,
            at: event.timestamp
        )
    }

    deinit {
        timer?.invalidate()
    }
}
