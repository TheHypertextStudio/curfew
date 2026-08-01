import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog
import SwiftUI

/// Central `@MainActor ObservableObject` for Curfew: holds all `@Published`
/// state and drives the 1 Hz tick loop. Behaviour lives in `CurfewAppModel+*`.
@MainActor
final class CurfewAppModel: NSObject, ObservableObject {
    /// Extension-button hold duration before a request is consumed; also drives
    /// `EnforcementSnapshot.extensionRequestTitle` copy.
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

    @Published var reflectionState: ReflectionRuntimeState

    // MARK: - Collaborators

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

    /// Respawn deterrent installed in `start()`, armed/disarmed on lockout.
    let respawnGuard: any RespawnGuardControlling
    let lockoutDeadlineStore: LockoutDeadlineStore
    /// Abstraction over "activate + show Settings". Tests substitute a spy.
    let appRouter: AppRouting

    /// Presenter for the first-launch onboarding window.
    let gettingStartedPresenter: GettingStartedPresenting

    /// Watches the MCP request queue; paired with `mcpSocketServer` (Unix-socket fast path).
    let mcpRequestMonitor: MCPRequestMonitor
    /// Unix-socket fast path for in-app MCP writes.
    let mcpSocketServer: MCPSocketServer

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

    /// Polls CoreGraphics idle time each tick. Gives downstream surfaces
    /// (future warning-suppression, retrospective attribution) a single
    /// source of truth for "is the user actively using the machine?".
    let idleWatcher: IdleWatcher

    /// Seam over the macOS Accessibility-trust check, polled each tick. The
    /// production default reads the real `AXIsProcessTrusted()` (false on
    /// headless CI); inject ``FakeAccessibilityAuthorization``.
    let accessibilityAuthorization: AccessibilityAuthorizing

    /// Cross-device awareness, started alongside CloudKit sync when Pro is
    /// unlocked and the flag is on. Lazy so the init body stays under budget.
    lazy var deviceRegistry: DeviceRegistry = .init(idleWatcher: idleWatcher)

    /// Writes lifecycle / extension / override events to the activity log.
    /// Always non-nil; falls back to ``NullActivityRecording`` when the SQLite
    /// store can't be opened.
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

    /// Daily grant counters; reset in `handleDayRollover`.
    var extensionMinutesGrantedToday = 0
    /// Snooze minutes granted today. Added to the deadline like extensions.
    var snoozeMinutesGrantedToday = 0

    /// `YYYY-M-D` token for the last-seen calendar day so `tick()` can
    /// detect rollovers without a NotificationCenter subscription.
    var currentDayToken = ""

    /// Last-evaluated warning stage — drives widget timeline reloads on
    /// sub-phase escalations (T-15 → T-5), not only phase transitions.
    var previousWarningStage: WarningStage = .none

    /// Warning stages fired today across every device on this iCloud
    /// account. Seeded from the `LockoutState` CKRecord; consulted by
    /// `WarningNotificationManager` to suppress cross-device duplicates.
    @Published var warningStagesFiredToday: Set<String> = []
    /// Day token for which `warningStagesFiredToday` applies. Flipped
    /// on rollover so yesterday's warnings don't leak into today.
    var warningStagesFiredDayToken: String = ""

    /// Whether the user has been idle past `idleWatcher.idleThresholdSeconds`.
    /// Mirrored from the watcher so observers need not reach into a
    /// non-`@Published` collaborator.
    @Published private(set) var isUserIdle = false

    /// Whether the app currently holds Accessibility trust. Seeded at init and
    /// re-polled each tick so a revoked permission shows without a relaunch.
    @Published private(set) var isAccessibilityTrusted: Bool

    /// Live enforcement-health verdict folding Accessibility trust with the
    /// keyboard shield's tap state. Seeded at init and recomputed each tick to
    /// drive the badge.
    @Published private(set) var enforcementHealth: EnforcementHealth

    /// Test seam for the keyboard shield's tap liveness. `nil` in production,
    /// where ``pollAndUpdateEnforcementHealth()`` reads the live
    /// `lockoutKeyInterceptor.isEnabled`; tests assign a closure instead.
    var tapLivenessOverride: (() -> Bool)?

    /// Memoisation cache for ``thisWeekRollup()``. Invalidated on week
    /// boundary advance or activity-recorder mutation.
    var cachedThisWeekKey: ThisWeekCacheKey?
    /// Cached rollup aligned with `cachedThisWeekKey`; nil when invalid.
    var cachedThisWeekRollup: WeeklyActivityRollup?

    /// Combine subscriptions held for the model's lifetime; drive reactive
    /// Pro-gated module reconciliation when `licenseGate.activatedKey` flips.
    var cancellables = Set<AnyCancellable>()

    /// How many seconds of activity log to keep. Matches the 52-week rolling
    /// retention promise in PRIVACY.md.
    static let activityRetentionSeconds: TimeInterval = 52 * 7 * 24 * 60 * 60

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

    /// Production / test-friendly designated initialiser; every other
    /// initialiser delegates here. Collaborators are injected so tests can
    /// substitute fakes. `@Published` state is assigned before `super.init()`.
    init(
        settingsStore: CurfewSettingsStore,
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting,
        featureFlags: FeatureFlags = .default,
        activityRecorder: any ActivityRecording,
        reflectionState: ReflectionRuntimeState = ReflectionRuntimeState(),
        mcpRequestMonitor: MCPRequestMonitor = MCPRequestMonitor(),
        licenseGate: LicenseGate = LicenseGate(),
        cloudKitSyncEngine: CloudKitSyncEngine = CloudKitSyncEngine(),
        calendarMonitor: CalendarMonitor = CalendarMonitor(),
        privilegedHelperManager: PrivilegedHelperManager = PrivilegedHelperManager(),
        idleWatcher: IdleWatcher = IdleWatcher(source: CGEventSourceIdleSource()),
        respawnGuard: any RespawnGuardControlling = NoOpRespawnGuard(),
        lockoutDeadlineStore: LockoutDeadlineStore = LockoutDeadlineStore(),
        accessibilityAuthorization: AccessibilityAuthorizing = SystemAccessibilityAuthorization()
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
        self.reflectionState = reflectionState
        self.mcpRequestMonitor = mcpRequestMonitor
        self.mcpSocketServer = MCPSocketServer()
        self.licenseGate = licenseGate
        self.cloudKitSyncEngine = cloudKitSyncEngine
        self.calendarMonitor = calendarMonitor
        self.privilegedHelperManager = privilegedHelperManager
        self.idleWatcher = idleWatcher
        self.respawnGuard = respawnGuard
        self.lockoutDeadlineStore = lockoutDeadlineStore
        self.accessibilityAuthorization = accessibilityAuthorization

        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.shouldOpenSettingsOnLaunch = settingsStore.consumeShouldShowInitialSetup()
        self.overrideEvents = settingsStore.loadOverrideEvents()

        let trackers = Self.makeBudgetTrackers(for: loadedSettings)
        self.extensionTracker = trackers.extension
        self.overrideTracker = trackers.override

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
        self.isUserIdle = idleWatcher.isIdle
        let seededTrust = accessibilityAuthorization.isTrusted()
        self.isAccessibilityTrusted = seededTrust
        self.enforcementHealth = Self.seededEnforcementHealth(
            isAccessibilityTrusted: seededTrust,
            tapIsEnabled: lockoutKeyInterceptor.isEnabled
        )
        super.init()
        completeInitialization(with: loadedSettings)
    }

    /// Zero-arg convenience used by `CurfewApp` at production launch; collaborators
    /// resolve to their `System*` defaults. Release wires the real ``PersistentLockdown``
    /// (Debug uses `NoOpRespawnGuard`); flags from ``FeatureFlags/resolved``.
    override convenience init() {
        #if DEBUG
            let respawnGuard: any RespawnGuardControlling = NoOpRespawnGuard()
        #else
            let respawnGuard: any RespawnGuardControlling = PersistentLockdown.production()
        #endif
        self.init(
            settingsStore: CurfewSettingsStore(),
            appRouter: SystemAppRouter(),
            gettingStartedPresenter: GettingStartedWindowPresenter(),
            featureFlags: .resolved,
            respawnGuard: respawnGuard
        )
    }

    /// Starts the 1 Hz enforcement tick. Safe to call repeatedly; no-ops
    /// when onboarding is incomplete or the timer is already armed.
    func start() {
        guard settings.hasCompletedInitialSetup, !started else { return }
        started = true
        notificationManager.requestPermissionIfNeeded()
        installRespawnGuardIfNeeded()
        startEnforcementReassertionObservers()
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

    /// Overrides the mirrored idle flag for the idle watcher and deterministic tests.
    func setIdleState(_ idle: Bool) {
        isUserIdle = idle
    }

    /// Updates accessibility trust only when its value changed.
    func setAccessibilityTrusted(_ trusted: Bool) {
        if isAccessibilityTrusted != trusted {
            isAccessibilityTrusted = trusted
        }
    }

    /// Updates enforcement health only when its value changed.
    func setEnforcementHealth(_ health: EnforcementHealth) {
        if enforcementHealth != health {
            enforcementHealth = health
        }
    }

    /// Timer-target bridge. Swift `Timer` requires a `@objc` selector, and
    /// `tick()` must remain callable from Swift too, so we trampoline here.
    @objc
    private func handleTimerFire(_ timer: Timer) {
        tick()
    }

    /// Appends to the published override log.
    func appendOverrideEvent(_ event: OverrideEvent) {
        overrideEvents.append(event)
    }

    deinit {
        timer?.invalidate()
    }
}
