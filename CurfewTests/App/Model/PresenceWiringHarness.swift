@testable import Curfew
import Foundation

/// A `CurfewAppModel` wired for presence tests, alongside the audit writer and
/// fake sensor installed into it.
///
/// Shared by the two suites that drive presence through the live model —
/// `PresenceAuditWiringTests` for the gate and the records, and
/// `PresenceNudgeWiringTests` for the distraction nudge — so the setup that
/// keeps a test run from opening a real camera has exactly one definition.
@MainActor
struct PresenceWiringHarness {
    /// The model under test.
    let model: CurfewAppModel

    /// The audit writer installed on ``model``, holding everything it emitted.
    let writer: RecordingAuditWriter

    /// The fake sensor installed on ``model``. Opens nothing.
    let sensor: FakePresenceSensor

    /// A `.working` evaluation, so a test can put the model in the one phase
    /// where a nudge is eligible without depending on the wall clock.
    static let workingEvaluation = CurfewEvaluation(
        phase: .working,
        warningStage: .none,
        minutesRemaining: 120,
        canRequestExtension: false,
        lockDate: nil,
        unlockDate: nil
    )

    /// Builds a model over throwaway defaults, its own recording audit log, and
    /// a fake presence sensor.
    ///
    /// The sensor override is installed before anything can tick, which is what
    /// keeps these suites from ever constructing the real camera-backed sensor.
    init(
        idleSeconds: TimeInterval = 600,
        presence: PresenceDetectionPolicy = .default,
        authorization: CameraAuthorization = .authorized
    ) {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.presence = presence
        // Every day off, so `tick()` can never evaluate into `.warning` or
        // `.locked`. That keeps these tests independent of the wall clock —
        // and keeps a suite run from putting a lockout overlay on the screen
        // of whoever is running it.
        settings.schedule = WeeklySchedule(
            rules: Dictionary(
                uniqueKeysWithValues: Weekday.allCases.map { ($0, DayRule.weekendDefault) }
            )
        )
        store.save(settings)

        // An isolated deadline file, for the same reason `LifecycleWiringTests`
        // uses one: a durable record left by another run would push the model
        // back into `.locked` on the first tick, which would both break these
        // assertions and put a lockout overlay on the screen.
        let deadlineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-presence-deadline-\(UUID().uuidString).json")

        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            activityRecorder: NullActivityRecording(),
            idleWatcher: IdleWatcher(
                source: MutableIdleSource(seconds: idleSeconds),
                idleThresholdSeconds: 300
            ),
            lockoutDeadlineStore: LockoutDeadlineStore(recordURL: deadlineURL),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        let sensor = FakePresenceSensor(authorization: authorization)
        model.presenceSensorOverride = sensor
        let writer = RecordingAuditWriter()
        model.auditLogOverride = AuditLog(stream: .app, writer: writer)

        self.model = model
        self.writer = writer
        self.sensor = sensor
    }

    /// The string sitting at `key` in `record`'s detail, or `nil` if the key is
    /// absent or holds another kind of value.
    func detailString(_ record: AuditRecord, _ key: String) -> String? {
        guard case .string(let value)? = record.detail[key] else { return nil }
        return value
    }

    /// The boolean sitting at `key` in `record`'s detail, or `nil` if the key is
    /// absent or holds another kind of value.
    func detailBool(_ record: AuditRecord, _ key: String) -> Bool? {
        guard case .bool(let value)? = record.detail[key] else { return nil }
        return value
    }

    /// Drives the monitor to a present-but-idle stretch that is already
    /// `secondsAgo` old, without the test having to wait, and returns the
    /// moment the stretch began.
    ///
    /// `evaluateDistractionWarning` measures the stretch against the model's own
    /// clock, which is now — so backdating the samples is what makes a sustained
    /// distraction reachable in a unit test.
    @discardableResult
    func backdatePresentButIdle(secondsAgo: TimeInterval) -> Date {
        let past = Date().addingTimeInterval(-secondsAgo)
        let monitor = model.presenceMonitor
        monitor.sample(now: past, cameraEnabled: true)
        sensor.observe(.detected, at: past)
        monitor.sample(now: past, cameraEnabled: true)
        return past
    }
}
