@testable import Curfew
import Foundation
import Testing

/// Wiring tests: the right audit event, with the right actor and the right
/// detail, comes out of the paths that actually change enforcement state.
///
/// The byte format is `AuditLineEncoderTests`' problem, and the filesystem is
/// `AuditLogWriterTests`' — these use an in-memory writer so a failure points
/// at the call site rather than at serialization.
@MainActor
struct AuditWiringTests {
    /// A model wired to throwaway defaults and its own recording log.
    ///
    /// The log is injected per model rather than installed process-wide, so
    /// these tests neither observe nor disturb other suites running in
    /// parallel — several of which build models and tick them.
    private func makeModel(
        settings: CurfewSettings? = nil
    ) -> (model: CurfewAppModel, writer: RecordingAuditWriter) {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)
        if let settings {
            store.save(settings)
        }
        let deadlineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-audit-deadline-\(UUID().uuidString).json")

        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: LockoutDeadlineStore(recordURL: deadlineURL),
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

    // MARK: - Schedule

    @Test("A weaker schedule change records the classification and effective date")
    func weakerScheduleChangeIsRecorded() throws {
        let (model, writer) = makeModel()

        var proposed = model.settings.schedule
        var monday = proposed.rule(for: .monday)
        monday.lockMinutes += 60
        proposed.rules[.monday] = monday
        model.queueScheduleUpdate(proposed)

        let record = try #require(writer.first(.scheduleChangeRequested))
        #expect(record.actor.token == "user")
        #expect(detailString(record, "classification") == "weaker")
        #expect(detailString(record, "changedDays") == "mon")
        #expect(record.detail["effectiveAt"] != nil)
        #expect(record.from != record.to)
        #expect(record.to == AuditScheduleSummary.digest(proposed))
    }

    @Test("A schedule change requested over MCP is attributed to the MCP client")
    func mcpScheduleChangeIsAttributed() throws {
        let (model, writer) = makeModel()

        var proposed = model.settings.schedule
        var tuesday = proposed.rule(for: .tuesday)
        tuesday.lockMinutes -= 30
        proposed.rules[.tuesday] = tuesday
        model.queueScheduleUpdate(proposed, requestedBy: .mcp(client: "claude-desktop"))

        let record = try #require(writer.first(.scheduleChangeRequested))
        #expect(record.actor.token == "mcp:claude-desktop")
        #expect(detailString(record, "classification") == "stricter")
    }

    @Test("Applying a due change records the delay it actually waited")
    func appliedScheduleChangeIsRecorded() throws {
        let (model, writer) = makeModel()

        var proposed = model.settings.schedule
        var wednesday = proposed.rule(for: .wednesday)
        wednesday.lockMinutes -= 15
        proposed.rules[.wednesday] = wednesday
        model.settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: proposed,
            requestedAt: model.currentTime.addingTimeInterval(-3600),
            effectiveAt: model.currentTime.addingTimeInterval(-1),
            classification: .stricter
        )
        model.applyPendingScheduleIfNeeded(now: model.currentTime)

        let record = try #require(writer.first(.scheduleChangeApplied))
        #expect(detailString(record, "classification") == "stricter")
        #expect(detailInt(record, "delaySeconds") == 3599)
        #expect(model.settings.schedule == proposed)
    }

    @Test("A deferral is recorded once, not once per tick")
    func deferralIsRecordedOnce() {
        let (model, writer) = makeModel()

        var proposed = model.settings.schedule
        var thursday = proposed.rule(for: .thursday)
        thursday.lockMinutes += 90
        proposed.rules[.thursday] = thursday
        let pending = PendingScheduleChange(
            proposedSchedule: proposed,
            requestedAt: model.currentTime.addingTimeInterval(-86400),
            effectiveAt: model.currentTime.addingTimeInterval(-1),
            classification: .weaker
        )
        model.settings.pendingScheduleChange = pending
        model.state = .locked(
            lockDate: model.currentTime.addingTimeInterval(-600),
            unlockDate: model.currentTime.addingTimeInterval(600)
        )

        for _ in 0 ..< 5 {
            model.applyPendingScheduleIfNeeded(now: model.currentTime)
        }

        let deferrals = writer.records(ofType: .scheduleChangeDeferred)
        #expect(deferrals.count == 1)
        #expect(detailString(deferrals[0], "reason") == "weaker_change_during_lockout")
        #expect(model.settings.schedule != proposed)
    }
}
