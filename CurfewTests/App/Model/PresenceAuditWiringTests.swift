@testable import Curfew
import Foundation
import Testing

/// The camera gate and the audit trail, driven through the live model.
///
/// The audit assertions do double duty. They check the right event came out of
/// the right transition, and they check the *shape* of what came out — that no
/// record carries anything an image could hide in.
///
/// The distraction nudge rides on the same wiring but answers a different
/// question — when Curfew should speak up — so it lives in
/// `PresenceNudgeWiringTests`.
@MainActor
struct PresenceAuditWiringTests {
    // MARK: - Gating through the model

    @Test("A default-configured model never starts the camera, however long it runs")
    func defaultModelNeverStartsTheCamera() {
        let harness = PresenceWiringHarness()

        for _ in 0 ..< 20 {
            harness.model.tick()
        }

        #expect(harness.sensor.startCount == 0)
        #expect(!harness.model.isPresenceCameraLive)
        #expect(harness.model.presenceState == .unknown)
        #expect(harness.model.presenceSignal == .unavailable)
    }

    @Test("Turning the setting on starts the camera; turning it off stops it")
    func settingDrivesTheCamera() throws {
        let harness = PresenceWiringHarness()
        let model = harness.model

        model.settings.presence.cameraEnabled = true
        model.tick()
        #expect(harness.sensor.isRunning)
        #expect(model.isPresenceCameraLive)
        let started = try #require(harness.writer.first(.presenceCameraStarted))
        #expect(harness.detailString(started, "authorization") == "authorized")

        model.disablePresenceDetection()
        #expect(!harness.sensor.isRunning)
        #expect(!model.isPresenceCameraLive)

        let stopped = try #require(harness.writer.first(.presenceCameraStopped))
        #expect(
            harness.detailString(stopped, "reason") == CameraStopReason.settingDisabled.rawValue
        )
    }

    @Test("Disabling presence detection stops the camera without waiting for a tick")
    func disablingIsImmediate() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let harness = PresenceWiringHarness(presence: presence)

        harness.model.tick()
        #expect(harness.sensor.isRunning)

        harness.model.disablePresenceDetection()

        #expect(!harness.sensor.isRunning)
        #expect(!harness.model.settings.presence.cameraEnabled)
    }

    @Test("Refused camera access leaves the setting off")
    func refusedAccessDoesNotPersistIntent() {
        let harness = PresenceWiringHarness(authorization: .notDetermined)
        let model = harness.model
        harness.sensor.authorizationRequestResult = .denied

        model.enablePresenceDetection()

        #expect(harness.sensor.authorizationRequestCount == 1)
        #expect(!model.settings.presence.cameraEnabled)
        #expect(harness.sensor.startCount == 0)
        // The claim is about *stored* intent, so read the persisted blob back
        // rather than trusting the in-memory value: a refused prompt must not
        // leave a machine configured to open a camera on next launch.
        #expect(!model.settingsStore.load().presence.cameraEnabled)
    }

    @Test("Granted camera access turns the setting on")
    func grantedAccessPersistsIntent() {
        let harness = PresenceWiringHarness(authorization: .notDetermined)
        harness.sensor.authorizationRequestResult = .authorized

        harness.model.enablePresenceDetection()

        #expect(harness.model.settings.presence.cameraEnabled)
        harness.model.tick()
        #expect(harness.sensor.startCount == 1)
    }

    // MARK: - Audit records

    @Test("The fused presence verdict is recorded when it moves")
    func fusedPresenceIsRecorded() throws {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let harness = PresenceWiringHarness(presence: presence)

        harness.model.tick()
        harness.sensor.observe(.detected, at: harness.model.currentTime)
        harness.model.tick()

        let records = harness.writer.records(ofType: .presenceStateChanged)
        let last = try #require(records.last)
        #expect(last.to == "present_idle")
        #expect(last.actor.token == "system")
        #expect(harness.detailString(last, "personSignal") == "detected")
        #expect(harness.detailBool(last, "hidIdle") == true)
        #expect(harness.detailBool(last, "cameraEnabled") == true)
        #expect(harness.detailBool(last, "cameraLive") == true)
        #expect(harness.detailString(last, "cameraAuthorization") == "authorized")
    }

    @Test("The HID-only presence record is unchanged alongside the fused one")
    func legacyPresenceRecordSurvives() throws {
        let harness = PresenceWiringHarness()
        harness.model.tick()

        let legacy = try #require(harness.writer.first(.presenceChanged))
        #expect(legacy.to == "idle")
        #expect(legacy.detail["thresholdSeconds"] != nil)
        // The fused record is additive, not a replacement — a parser written
        // against `presence.changed` keeps working.
        #expect(harness.writer.first(.presenceStateChanged) != nil)
    }

    @Test("No presence record can carry image data")
    func presenceRecordsCarryNoImagery() {
        var presence = PresenceDetectionPolicy.default
        presence.cameraEnabled = true
        let harness = PresenceWiringHarness(presence: presence)
        let model = harness.model

        model.tick()
        harness.sensor.observe(.detected, at: model.currentTime)
        model.tick()
        harness.sensor.observe(.notDetected, at: model.currentTime)
        model.tick()

        let presenceEvents: Set<AuditEventType> = [
            .presenceStateChanged,
            .presenceCameraStarted,
            .presenceCameraStopped,
            .presenceCameraAuthorizationChanged,
            .presenceDistractionWarned
        ]
        let records = harness.writer.records.filter { presenceEvents.contains($0.event) }
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
        let harness = PresenceWiringHarness(presence: presence)

        harness.model.tick()
        harness.sensor.authorization = .denied
        harness.model.tick()

        let record = try #require(harness.writer.first(.presenceCameraAuthorizationChanged))
        #expect(record.from == "authorized")
        #expect(record.to == "denied")
        #expect(record.actor.token == "system")
    }
}
