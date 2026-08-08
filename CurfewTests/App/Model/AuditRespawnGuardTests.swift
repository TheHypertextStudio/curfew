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
