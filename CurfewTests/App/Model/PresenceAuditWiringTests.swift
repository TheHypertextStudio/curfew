@testable import Curfew
import Foundation
import Testing

/// Presence wiring through the live model: the tick loop, the audit records,
/// and the nudge.
///
/// The audit assertions do double duty. They check the right event came out of
/// the right transition, and they check the *shape* of what came out — that no
/// record carries anything an image could hide in.
@MainActor
struct PresenceAuditWiringTests {
    /// A `.working` evaluation, so a test can put the model in the one phase
    /// where a nudge is eligible without depending on the wall clock.
    private static let workingEvaluation = CurfewEvaluation(
        phase: .working,
        warningStage: .none,
        minutesRemaining: 120,
        canRequestExtension: false,
        lockDate: nil,
        unlockDate: nil
    )

    /// A model wired to throwaway defaults, its own recording audit log, and a
    /// fake presence sensor.
    ///
    /// The sensor override is installed before anything can tick, which is
    /// what keeps this suite from ever constructing the real camera-backed
    /// sensor.
    private func makeModel(
        idleSeconds: TimeInterval = 600,
        presence: PresenceDetectionPolicy = .default,
        authorization: CameraAuthorization = .authorized
    ) -> (model: CurfewAppModel, writer: RecordingAuditWriter, sensor: FakePresenceSensor) {
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
        return (model, writer, sensor)
    }

    private func detailString(_ record: AuditRecord, _ key: String) -> String? {
        guard case .string(let value)? = record.detail[key] else { return nil }
        return value
    }

    private func detailBool(_ record: AuditRecord, _ key: String) -> Bool? {
        guard case .bool(let value)? = record.detail[key] else { return nil }
        return value
    }

    // MARK: - Gating through the model

    @Test("A default-configured model never starts the camera, however long it runs")
    func defaultModelNeverStartsTheCamera() {
        let (model, _, sensor) = makeModel()

        for _ in 0 ..< 20 {
            model.tick()
        }

        #expect(sensor.startCount == 0)
        #expect(!model.isPresenceCameraLive)
        #expect(model.presenceState == .unknown)
        #expect(model.presenceSignal == .unavailable)
    }

    @Test("Turning the setting on starts the camera; turning it off stops it")
    func settingDrivesTheCamera() throws {
        let (model, writer, sensor) = makeModel()

        model.settings.presence.cameraEnabled = true
        model.tick()
        #expect(sensor.isRunning)
        #expect(model.isPresenceCameraLive)
        let started = try #require(writer.first(.presenceCameraStarted))
        #expect(detailString(started, "authorization") == "authorized")

        model.disablePresenceDetection()
        #expect(!sensor.isRunning)
        #expect(!model.isPresenceCameraLive)

        let stopped = try #require(writer.first(.presenceCameraStopped))
        #expect(detailString(stopped, "reason") == CameraStopReason.settingDisabled.rawValue)
    }

    @Test("Disabling presence detection stops the camera without waiting for a tick")
    func disablingIsImmediate() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let (model, _, sensor) = makeModel(presence: presence)

        model.tick()
        #expect(sensor.isRunning)

        model.disablePresenceDetection()

        #expect(!sensor.isRunning)
        #expect(!model.settings.presence.cameraEnabled)
    }

    @Test("Refused camera access leaves the setting off")
    func refusedAccessDoesNotPersistIntent() {
        let (model, _, sensor) = makeModel(authorization: .notDetermined)
        sensor.authorizationRequestResult = .denied

        model.enablePresenceDetection()

        #expect(sensor.authorizationRequestCount == 1)
        #expect(!model.settings.presence.cameraEnabled)
        #expect(sensor.startCount == 0)
        // The claim is about *stored* intent, so read the persisted blob back
        // rather than trusting the in-memory value: a refused prompt must not
        // leave a machine configured to open a camera on next launch.
        #expect(!model.settingsStore.load().presence.cameraEnabled)
    }

    @Test("Granted camera access turns the setting on")
    func grantedAccessPersistsIntent() {
        let (model, _, sensor) = makeModel(authorization: .notDetermined)
        sensor.authorizationRequestResult = .authorized

        model.enablePresenceDetection()

        #expect(model.settings.presence.cameraEnabled)
        model.tick()
        #expect(sensor.startCount == 1)
    }

    // MARK: - Audit records

    @Test("The fused presence verdict is recorded when it moves")
    func fusedPresenceIsRecorded() throws {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let (model, writer, sensor) = makeModel(presence: presence)

        model.tick()
        sensor.observe(.detected, at: model.currentTime)
        model.tick()

        let records = writer.records(ofType: .presenceStateChanged)
        let last = try #require(records.last)
        #expect(last.to == "present_idle")
        #expect(last.actor.token == "system")
        #expect(detailString(last, "personSignal") == "detected")
        #expect(detailBool(last, "hidIdle") == true)
        #expect(detailBool(last, "cameraEnabled") == true)
        #expect(detailBool(last, "cameraLive") == true)
        #expect(detailString(last, "cameraAuthorization") == "authorized")
    }

    @Test("The HID-only presence record is unchanged alongside the fused one")
    func legacyPresenceRecordSurvives() throws {
        let (model, writer, _) = makeModel()
        model.tick()

        let legacy = try #require(writer.first(.presenceChanged))
        #expect(legacy.to == "idle")
        #expect(legacy.detail["thresholdSeconds"] != nil)
        // The fused record is additive, not a replacement — a parser written
        // against `presence.changed` keeps working.
        #expect(writer.first(.presenceStateChanged) != nil)
    }

    @Test("No presence record can carry image data")
    func presenceRecordsCarryNoImagery() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let (model, writer, sensor) = makeModel(presence: presence)

        model.tick()
        sensor.observe(.detected, at: model.currentTime)
        model.tick()
        sensor.observe(.notDetected, at: model.currentTime)
        model.tick()

        let presenceEvents: Set<AuditEventType> = [
            .presenceStateChanged,
            .presenceCameraStarted,
            .presenceCameraStopped,
            .presenceCameraAuthorizationChanged,
            .presenceDistractionWarned
        ]
        let records = writer.records.filter { presenceEvents.contains($0.event) }
        #expect(!records.isEmpty)

        // `AuditValue` admits only scalars, so there is no representation for
        // a frame. This asserts the weaker but checkable property: every value
        // written is short, and none is a base64-looking blob.
        for record in records {
            for (key, value) in record.detail {
                guard case .string(let text) = value else { continue }
                #expect(
                    text.count <= 64,
                    "presence detail \(key) is suspiciously long: \(text.count) chars"
                )
            }
        }
    }

    @Test("Camera authorization changes are recorded with both ends")
    func authorizationChangesAreRecorded() throws {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let (model, writer, sensor) = makeModel(presence: presence)

        model.tick()
        sensor.authorization = .denied
        model.tick()

        let record = try #require(writer.first(.presenceCameraAuthorizationChanged))
        #expect(record.from == "authorized")
        #expect(record.to == "denied")
        #expect(record.actor.token == "system")
    }

    // MARK: - Distraction nudge

    @Test("A freshly begun pause does not produce a nudge")
    func briefPauseStaysSilent() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let (model, writer, sensor) = makeModel(presence: presence)

        // The stretch starts now, so it is seconds old at most — well inside
        // the sustained window. Standing up to stretch is not a distraction.
        let now = Date()
        let monitor = model.presenceMonitor
        monitor.sample(now: now, cameraEnabled: true)
        sensor.observe(.detected, at: now)
        monitor.sample(now: now, cameraEnabled: true)

        model.state = Self.workingEvaluation
        model.evaluateDistractionWarning()

        #expect(model.presenceState == .presentButIdle)
        #expect(writer.records(ofType: .presenceDistractionWarned).isEmpty)
    }

    @Test("A sustained distraction is nudged once, then held for the repeat window")
    func sustainedDistractionIsNudgedOnce() throws {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let (model, writer, sensor) = makeModel(presence: presence)

        // Drive the monitor directly with a past timestamp so the
        // present-but-idle stretch is half an hour old without the test having
        // to wait half an hour. `evaluateDistractionWarning` then measures
        // against the model's own clock, which is now.
        let past = Date().addingTimeInterval(-1800)
        let monitor = model.presenceMonitor
        monitor.sample(now: past, cameraEnabled: true)
        sensor.observe(.detected, at: past)
        monitor.sample(now: past, cameraEnabled: true)
        #expect(model.presenceState == .presentButIdle)

        model.state = Self.workingEvaluation

        model.evaluateDistractionWarning()
        let warnings = writer.records(ofType: .presenceDistractionWarned)
        #expect(warnings.count == 1)
        let record = try #require(warnings.first)
        #expect(record.actor.token == "app")
        #expect(detailString(record, "state") == "present_idle")
        #expect(detailString(record, "phase") == "working")

        // Immediately again: the repeat window has not elapsed, so nothing
        // more is written. This is what stops a long meeting from producing a
        // banner every second.
        model.evaluateDistractionWarning()
        #expect(writer.records(ofType: .presenceDistractionWarned).count == 1)
    }

    @Test("No nudge during lockout, however long the user has been still")
    func noNudgeDuringLockout() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let (model, writer, sensor) = makeModel(presence: presence)

        let past = Date().addingTimeInterval(-1800)
        let monitor = model.presenceMonitor
        monitor.sample(now: past, cameraEnabled: true)
        sensor.observe(.detected, at: past)
        monitor.sample(now: past, cameraEnabled: true)

        model.state = .locked(
            lockDate: past,
            unlockDate: Date().addingTimeInterval(3600)
        )
        model.evaluateDistractionWarning()

        // The screen is already covering the Mac; "get back to work" is the
        // opposite of what Curfew is saying at that moment.
        #expect(writer.records(ofType: .presenceDistractionWarned).isEmpty)
    }

    @Test("No nudge when the user turned nudges off but kept presence detection on")
    func nudgeSwitchIsIndependent() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        presence.warnsWhenDistracted = false
        let (model, writer, sensor) = makeModel(presence: presence)

        let past = Date().addingTimeInterval(-1800)
        let monitor = model.presenceMonitor
        monitor.sample(now: past, cameraEnabled: true)
        sensor.observe(.detected, at: past)
        monitor.sample(now: past, cameraEnabled: true)

        model.state = Self.workingEvaluation
        model.evaluateDistractionWarning()

        #expect(model.presenceState == .presentButIdle)
        #expect(writer.records(ofType: .presenceDistractionWarned).isEmpty)
    }

    @Test("No nudge fires while presence detection is off")
    func noNudgeWithoutTheCamera() {
        let (model, writer, _) = makeModel()

        for _ in 0 ..< 10 {
            model.tick()
        }

        #expect(writer.records(ofType: .presenceDistractionWarned).isEmpty)
        #expect(model.presenceState == .unknown)
    }
}
