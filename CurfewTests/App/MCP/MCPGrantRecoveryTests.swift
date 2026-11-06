@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
struct MCPGrantRecoveryTests {
    @Test("Restart acknowledges a committed extension without granting it twice")
    func restartAfterUnacknowledgedGrant() throws {
        try withFixture { fixture in
            try fixture.seedTrackedRuntime()
            let fault = AcknowledgementFault()
            let queue = MCPRequestQueueStore(
                recordURL: fixture.queueURL,
                beforeAcknowledgement: {
                    if fault
                        .enabled {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            )
            let request = fixture.request()
            try queue.append(request)
            let initial = fixture.model(queue: queue)
            initial.state = Self.warning
            fault.enabled = true
            initial.approveMCPRequest(request)
            #expect(initial.extensionMinutesGrantedToday == 15)
            #expect(initial.runtimeStateSnapshot().mcpGrantReceipts?.count == 1)
            #expect(try queue.load().first?.status == .pending)

            fault.enabled = false
            let restarted = fixture.model(queue: queue)
            restarted.aiConsentPolicy = .deny
            restarted.state = .dayOff
            restarted.handleNewMCPRequests([request])
            #expect(restarted.extensionMinutesGrantedToday == 15)
            #expect(restarted.extensionTracker.usedCount == 1)
            #expect(try queue.load().first?.status == .approved)
            #expect(restarted.runtimeStateSnapshot().mcpGrantReceipts?.isEmpty != false)
            restarted.approveMCPRequest(request)
            #expect(restarted.extensionTracker.usedCount == 1)
        }
    }

    @Test("Restart acknowledges a schedule request without overwriting a later edit")
    func restartAfterUnacknowledgedSchedule() throws {
        try withFixture { fixture in
            try fixture.seedTrackedRuntime()
            let fault = AcknowledgementFault()
            let queue = MCPRequestQueueStore(
                recordURL: fixture.queueURL,
                beforeAcknowledgement: {
                    if fault.enabled {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            )
            let request = MCPPendingRequest(
                tool: .setSchedule,
                argumentsJSON: #"{"weekday":"monday","lock_time":"22:00","is_day_off":false}"#,
                requestedAt: fixture.now
            )
            try queue.append(request)
            let initial = fixture.model(queue: queue)
            fault.enabled = true
            initial.approveMCPRequest(request)
            #expect(initial.settings.schedule.rule(for: .monday).lockMinutes == 22 * 60)
            #expect(try queue.load().first?.status == .pending)

            initial.queueScheduleUpdate(.standardNineToFive)
            let restarted = fixture.model(queue: queue)
            try #require(restarted.settings.schedule == .standardNineToFive)
            fault.enabled = false
            restarted.approveMCPRequest(request)

            #expect(restarted.settings.schedule == .standardNineToFive)
            #expect(fixture.settings.load().schedule == .standardNineToFive)
            #expect(try queue.load().first?.status == .approved)
            #expect(try fixture.settings.scheduleRecoveryIDs().isEmpty)
        }
    }

    @Test("A post-commit storage error leaves pending status and protects the committed snapshot")
    func ambiguousRuntimeWrite() throws {
        try withFixture { fixture in
            try fixture.seedTrackedRuntime()
            let fault = AcknowledgementFault()
            let store = EnforcementRuntimeStateStore(
                recordURL: fixture.runtimeURL,
                afterPersist: {
                    if fault
                        .enabled {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            )
            let queue = MCPRequestQueueStore(recordURL: fixture.queueURL)
            let request = fixture.request()
            try queue.append(request)
            let initial = fixture.model(queue: queue, runtime: store)
            let writer = RecordingAuditWriter()
            initial.auditLogOverride = AuditLog(stream: .app, writer: writer)
            initial.state = Self.warning
            fault.enabled = true
            initial.approveMCPRequest(request)
            #expect(initial.runtimePersistenceError != nil)
            #expect(try queue.load().first?.status == .pending)
            #expect(writer.first(.extensionDenied) == nil)
            initial.denyMCPRequest(request, reason: "The grant outcome is still uncertain.")
            #expect(try queue.load().first?.status == .pending)
            #expect(writer.first(.mcpRequestDenied) == nil)
            let committed = try Data(contentsOf: fixture.runtimeURL)
            #expect(!initial.persistRuntimeState())
            initial.handleDayRollover(to: "next-day")
            #expect(try Data(contentsOf: fixture.runtimeURL) == committed)

            let restarted = fixture.model(queue: queue)
            restarted.handleNewMCPRequests([request])
            #expect(restarted.extensionTracker.usedCount == 1)
            #expect(restarted.extensionMinutesGrantedToday == 15)
            #expect(try queue.load().first?.status == .approved)
        }
    }

    @Test("Daily reset retains unacknowledged identities until queue persistence recovers")
    func resetsPreserveReceipts() throws {
        try withFixture { fixture in
            try fixture.seedTrackedRuntime()
            let fault = AcknowledgementFault()
            let queue = MCPRequestQueueStore(
                recordURL: fixture.queueURL,
                beforeAcknowledgement: {
                    if fault
                        .enabled {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            )
            let request = fixture.request()
            try queue.append(request)
            let model = fixture.model(queue: queue)
            model.state = Self.warning
            fault.enabled = true
            model.approveMCPRequest(request)
            model.handleDayRollover(to: "next-day")
            model.settings.extensionWeeklyLimit = 4
            #expect(model.runtimeStateSnapshot().mcpGrantReceipts?.first?.matches(request) == true)
            #expect(try EnforcementRuntimeStateStore(recordURL: fixture.runtimeURL).load()?
                .mcpGrantReceipts?.count == 1)
            fault.enabled = false
            model.retryMCPGrantAcknowledgements()
            #expect(model.extensionMinutesGrantedToday == 0)
            #expect(model.extensionTracker.usedCount == 1)
            #expect(try queue.load().first?.status == .approved)
        }
    }

    @Test("Legacy migration tracks exact pending IDs without rejecting new same-second requests")
    func legacyMigration() throws {
        try withFixture { fixture in
            var legacy = EnforcementRuntimeState(dayToken: CurfewAppModel
                .dayToken(for: fixture.now))
            legacy.version = 1
            try EnforcementRuntimeStateStore(recordURL: fixture.runtimeURL).save(legacy)
            let queue = MCPRequestQueueStore(recordURL: fixture.queueURL)
            let old = fixture.request()
            try queue.append(old)
            let model = fixture.model(queue: queue)
            #expect(model.runtimeStateSnapshot().legacyMCPGrantRequestIDs?.contains(old.id) == true)
            model.state = Self.warning
            model.approveMCPRequest(old)
            #expect(try queue.load().first?.status == .denied)
            #expect(model.extensionTracker.usedCount == 0)

            let fresh = fixture.request()
            try queue.append(fresh)
            model.state = Self.warning
            model.approveMCPRequest(fresh)
            #expect(fresh.requestedAt == old.requestedAt)
            #expect(model.extensionTracker.usedCount == 1)
            #expect(try queue.load().first(where: { $0.id == fresh.id })?.status == .approved)
        }
    }

    private static var warning: CurfewEvaluation {
        CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: nil,
            unlockDate: nil
        )
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let suite = "CurfewMCPGrantRecovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = CurfewSettingsStore(
            defaults: defaults, scheduleRecordURL: directory.appendingPathComponent("schedule.json")
        )
        var value = CurfewSettings.default
        value.hasCompletedInitialSetup = true
        value.mcpEnabled = true
        value.schedule = .allDaysOff
        settings.save(value)
        settings.saveAutomaticScheduleConsent(false)
        try settings.prepareScheduleRecovery(queue: MCPRequestQueueStore())
        try body(Fixture(
            directory: directory,
            settings: settings,
            now: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        ))
    }
}

@MainActor
private struct Fixture {
    let directory: URL
    let settings: CurfewSettingsStore
    let now: Date
    var queueURL: URL {
        directory.appendingPathComponent("queue.json")
    }

    var runtimeURL: URL {
        directory.appendingPathComponent("runtime.json")
    }

    func seedTrackedRuntime() throws {
        try EnforcementRuntimeStateStore(recordURL: runtimeURL).save(EnforcementRuntimeState(
            dayToken: CurfewAppModel.dayToken(for: now), mcpReceiptTrackingStartedAt: now
        ))
    }

    func request() -> MCPPendingRequest {
        MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"Finish saving"}"#,
            requestedAt: now
        )
    }

    func model(
        queue: MCPRequestQueueStore,
        runtime: EnforcementRuntimeStateStore? = nil
    ) -> CurfewAppModel {
        CurfewAppModel(
            settingsStore: CurfewSettingsStore(
                defaults: settings.storageDefaults,
                scheduleRecordURL: directory.appendingPathComponent("schedule.json")
            ),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            mcpRequestQueueStore: queue,
            lockoutDeadlineStore: .ephemeralForTesting(),
            runtimeStateStore: runtime ??
                EnforcementRuntimeStateStore(recordURL: runtimeURL),
            runtimeNow: now
        )
    }
}

private final class AcknowledgementFault {
    var enabled = false
}
