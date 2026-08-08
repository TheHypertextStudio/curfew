@testable import Curfew
import Foundation
import Testing

/// Audit coverage for the user-space respawn deterrent.
///
/// `toggleRespawnGuardIfPhaseChanged` logs and swallows every `launchctl`
/// failure so a broken deterrent never crashes the app, which makes the audit
/// record the only surviving evidence of whether the deterrent was actually up
/// during a lockout. Split into its own suite to stay inside the type-body
/// budget.
@MainActor
struct AuditRespawnGuardTests {
    private func makeModel(
        respawnGuard: any RespawnGuardControlling = NoOpRespawnGuard()
    ) -> (model: CurfewAppModel, writer: RecordingAuditWriter) {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            activityRecorder: NullActivityRecording(),
            respawnGuard: respawnGuard,
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        let writer = RecordingAuditWriter()
        model.auditLogOverride = AuditLog(stream: .app, writer: writer)
        return (model, writer)
    }

    private func detailString(_ record: AuditRecord, _ key: String) -> String? {
        guard case .string(let value)? = record.detail[key] else { return nil }
        return value
    }

    @Test("Arming the respawn deterrent on lockout entry is recorded")
    func respawnGuardArmIsRecorded() throws {
        let (model, writer) = makeModel()

        model.state = .locked(
            lockDate: model.currentTime.addingTimeInterval(-60),
            unlockDate: model.currentTime.addingTimeInterval(3600)
        )
        model.toggleRespawnGuardIfPhaseChanged(previousPhase: .warning)

        let record = try #require(writer.first(.respawnGuardChanged))
        #expect(record.to == "armed")
        #expect(record.actor.token == "app")
        #expect(detailString(record, "phase") == "locked")
        #expect(record.detail["error"] == nil)
    }

    @Test("Disarming on lockout exit is recorded as a transition from armed")
    func respawnGuardDisarmIsRecorded() {
        let (model, writer) = makeModel()

        model.state = .locked(
            lockDate: model.currentTime.addingTimeInterval(-60),
            unlockDate: model.currentTime.addingTimeInterval(3600)
        )
        model.toggleRespawnGuardIfPhaseChanged(previousPhase: .working)
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 300,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.toggleRespawnGuardIfPhaseChanged(previousPhase: .locked)

        let records = writer.records(ofType: .respawnGuardChanged)
        #expect(records.count == 2)
        #expect(records[0].to == "armed")
        #expect(records[1].from == "armed")
        #expect(records[1].to == "disarmed")
    }

    @Test("A guard that fails to arm is recorded with the failure, not silently swallowed")
    func respawnGuardArmFailureIsRecorded() throws {
        // The model logs and swallows this error so a failed deterrent never
        // becomes a crash. That is exactly why the audit log has to carry it:
        // it is the difference between "quitting Curfew ends the lockout" and
        // "it does not", and nothing else on screen says which happened.
        let guardSpy = RecordingRespawnGuard()
        guardSpy.armErrors = [CocoaError(.fileWriteNoPermission)]
        let (model, writer) = makeModel(respawnGuard: guardSpy)

        model.state = .locked(
            lockDate: model.currentTime.addingTimeInterval(-60),
            unlockDate: model.currentTime.addingTimeInterval(3600)
        )
        model.toggleRespawnGuardIfPhaseChanged(previousPhase: .warning)

        let record = try #require(writer.first(.respawnGuardChanged))
        #expect(record.to == "arm_failed")
        #expect(detailString(record, "error")?.isEmpty == false)
    }
}

/// The override-grant redaction proof.
///
/// Lives beside the respawn-guard suite rather than in `AuditGrantWiringTests`
/// only because that suite is at its type-body budget; it is a redaction test
/// and `AuditRedactionTests` covers the encoder half of the same contract.
@MainActor
struct AuditOverrideRedactionTests {
    private func makeModel() -> (model: CurfewAppModel, writer: RecordingAuditWriter) {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            activityRecorder: NullActivityRecording(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        let writer = RecordingAuditWriter()
        model.auditLogOverride = AuditLog(stream: .app, writer: writer)
        return (model, writer)
    }

    private func detailString(_ record: AuditRecord, _ key: String) -> String? {
        guard case .string(let value)? = record.detail[key] else { return nil }
        return value
    }

    private func detailInt(_ record: AuditRecord, _ key: String) -> Int? {
        guard case .int(let value)? = record.detail[key] else { return nil }
        return value
    }

    @Test("A granted override records length and digest, never the justification")
    func overrideGrantRedactsProse() throws {
        let (model, writer) = makeModel()

        let reason = String(
            repeating: "the deploy window closes at midnight ",
            count: 3
        )
        model.recordOverrideEvent(
            OverrideEvent(
                timestamp: model.currentTime,
                deviceName: "Test Mac",
                reason: reason,
                grantedDurationMinutes: 20
            )
        )

        let record = try #require(writer.first(.overrideGranted))
        #expect(detailInt(record, "minutes") == 20)

        // Assert the redacted keys are present and hold exactly a count and a
        // digest. Scanning only the values that happen to be strings would
        // pass on a record that dropped `reasonDigest` altogether, or that
        // never carried the reason at all.
        #expect(detailInt(record, "reasonLength") == reason.count)
        let digest = try #require(detailString(record, "reasonDigest"))
        #expect(digest == AuditRedaction.digest(reason))
        #expect(digest.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil)

        // And no field anywhere on the record carries a fragment of the prose.
        let words = reason.split(separator: " ").filter { $0.count > 3 }
        let encoded = AuditLineEncoder.encode(record, previousHash: auditGenesisHash).line
        for word in words {
            #expect(encoded.contains(word) == false)
        }
    }
}
