@testable import Curfew
import Foundation
import Testing

/// Wiring tests for the grant, consent, and tick-loop paths.
///
/// Split from ``AuditWiringTests`` to stay inside the type-body budget; that
/// suite covers the schedule paths and documents the shared approach.
@MainActor
struct AuditGrantWiringTests {
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

    private func detailInt(_ record: AuditRecord, _ key: String) -> Int? {
        guard case .int(let value)? = record.detail[key] else { return nil }
        return value
    }

    // MARK: - Grants

    @Test("A granted extension records minutes and the budget it left behind")
    func extensionGrantIsRecorded() throws {
        let (model, writer) = makeModel()

        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .thirtyMinutes,
            minutesRemaining: 30,
            canRequestExtension: true,
            lockDate: model.currentTime.addingTimeInterval(1800),
            unlockDate: model.currentTime.addingTimeInterval(50000)
        )
        let limit = model.settings.extensionWeeklyLimit
        model.confirmExtensionRequest()

        let record = try #require(writer.first(.extensionGranted))
        #expect(record.actor.token == "user")
        #expect(detailInt(record, "minutes") == model.settings.extensionDurationMinutes)
        #expect(detailInt(record, "budgetLimit") == limit)
        #expect(detailInt(record, "budgetRemaining") == limit - 1)
    }

    @Test("A refused extension records a stable reason token")
    func extensionDenialIsRecorded() throws {
        let (model, writer) = makeModel()

        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 300,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.confirmExtensionRequest()

        let record = try #require(writer.first(.extensionDenied))
        #expect(detailString(record, "reason") == "not_offered")
    }

    @Test("An override request outside lockout is recorded as denied, not granted")
    func overrideOutsideLockoutIsDenied() throws {
        let (model, writer) = makeModel()

        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 120,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.beginOverrideRequest()

        let record = try #require(writer.first(.overrideDenied))
        #expect(detailString(record, "reason") == "not_locked")
        #expect(writer.first(.overrideGranted) == nil)
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
        #expect(detailInt(record, "reasonLength") == reason.count)
        #expect(detailString(record, "reasonDigest") == AuditRedaction.digest(reason))
        for value in record.detail.values {
            guard case .string(let text) = value else { continue }
            #expect(text.contains("deploy window") == false)
        }
    }

    // MARK: - MCP consent

    @Test("An inbound MCP request and its denial are both recorded with the origin")
    func mcpDenialIsRecorded() throws {
        let (model, writer) = makeModel()

        let request = MCPPendingRequest(
            tool: .requestOverride,
            argumentsJSON: #"{"reason":"private prose that must not appear"}"#
        )
        model.handleNewMCPRequests([request])

        let received = try #require(writer.first(.mcpRequestReceived))
        #expect(received.actor.token == "mcp")
        #expect(detailString(received, "tool") == "curfew.request_override")
        #expect(received.detail["argumentsDigest"] != nil)
        for value in received.detail.values {
            guard case .string(let text) = value else { continue }
            #expect(text.contains("private prose") == false)
        }

        let denied = try #require(writer.first(.mcpRequestDenied))
        #expect(detailString(denied, "requestId") == request.id.uuidString)
        #expect(detailString(denied, "denialReason")?.isEmpty == false)
    }

    @Test("The override guard's refusal is attributed to the app, not to a person")
    func overrideGuardDenialIsAttributedToApp() throws {
        let (model, writer) = makeModel()

        // No human sees this one. The legacy `request_override` guard refuses
        // before the consent sheet exists, so filing it as a user decision
        // would put a person's name on a choice they never made.
        model.handleNewMCPRequests([
            MCPPendingRequest(tool: .requestOverride, argumentsJSON: "{}")
        ])

        let denied = try #require(writer.first(.mcpRequestDenied))
        #expect(denied.actor.token == "app")
    }

    @Test("A deny-all policy refusal is attributed to the app, not to a person")
    func policyDenialIsAttributedToApp() throws {
        let (model, writer) = makeModel()

        model.aiConsentPolicy = .deny
        model.handleNewMCPRequests([
            MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        ])

        let denied = try #require(writer.first(.mcpRequestDenied))
        #expect(denied.actor.token == "app")
        #expect(detailString(denied, "policy") == "deny")
    }

    @Test("A refusal in the consent sheet is attributed to the person who clicked")
    func consentSheetDenialIsAttributedToUser() throws {
        let (model, writer) = makeModel()

        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        model.denyMCPRequest(request, reason: "Not tonight.")

        let denied = try #require(writer.first(.mcpRequestDenied))
        #expect(denied.actor.token == "user")
        #expect(detailString(denied, "denialReason") == "Not tonight.")
    }

    @Test("An approval in the consent sheet writes one record attributed to the person")
    func consentSheetApprovalIsAttributedToUser() throws {
        let (model, writer) = makeModel()

        model.approveMCPRequest(
            MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        )

        #expect(writer.records(ofType: .mcpRequestApproved).count == 1)
        #expect(writer.records(ofType: .mcpRequestAutoApproved).isEmpty)
        let approved = try #require(writer.first(.mcpRequestApproved))
        #expect(approved.actor.token == "user")
    }

    @Test("A queued MCP request records the consent policy that parked it")
    func mcpQueuedIsRecorded() throws {
        let (model, writer) = makeModel()

        model.aiConsentPolicy = .queue
        let request = MCPPendingRequest(
            tool: .setSchedule,
            argumentsJSON: #"{"weekday":"monday","lock_time":"18:00"}"#
        )
        model.handleNewMCPRequests([request])

        let queued = try #require(writer.first(.mcpRequestQueued))
        #expect(detailString(queued, "policy") == "queue")
        #expect(model.pendingMCPRequests.count == 1)
    }

    @Test("A policy auto-approval writes exactly one record, attributed to the app")
    func autoApprovalWritesOneAppRecord() throws {
        let (model, writer) = makeModel()

        model.aiConsentPolicy = .autoApprove
        model.autoApproveMCPRequest(
            MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        )

        // One decision, one line. The earlier shape emitted an app-attributed
        // `auto_approved` and then a user-attributed `approved` for the same
        // choice, which read as a person approving something never shown.
        #expect(writer.records(ofType: .mcpRequestAutoApproved).count == 1)
        #expect(writer.records(ofType: .mcpRequestApproved).isEmpty)
        let approved = try #require(writer.first(.mcpRequestAutoApproved))
        #expect(approved.actor.token == "app")
        #expect(detailString(approved, "policy") == "autoApprove")
    }

    // MARK: - Tick loop

    @Test("A phase transition records the change plus the lockout marker")
    func phaseTransitionRecordsLockoutStart() throws {
        let (model, writer) = makeModel()

        model.state = .locked(
            lockDate: model.currentTime.addingTimeInterval(-60),
            unlockDate: model.currentTime.addingTimeInterval(3600)
        )
        model.recordAuditTickState(previousPhase: .warning)

        let transition = try #require(writer.first(.phaseChanged))
        #expect(transition.from == "warning")
        #expect(transition.to == "locked")
        #expect(transition.detail["scheduleDigest"] != nil)
        #expect(transition.detail["unlockAt"] != nil)
        #expect(detailString(transition, "todayLock") != nil)
        #expect(writer.first(.lockoutStarted) != nil)
        #expect(writer.first(.lockoutEnded) == nil)
    }

    @Test("Leaving lockout under an active override records the override reason")
    func lockoutEndAttributesOverride() throws {
        let (model, writer) = makeModel()

        model.overrideUntil = model.currentTime.addingTimeInterval(1200)
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 20,
            canRequestExtension: false,
            lockDate: model.currentTime.addingTimeInterval(1200),
            unlockDate: model.currentTime.addingTimeInterval(40000)
        )
        model.recordAuditTickState(previousPhase: .locked)

        let ended = try #require(writer.first(.lockoutEnded))
        #expect(detailString(ended, "reason") == "override")
    }

    @Test("A steady tick writes nothing after the first")
    func steadyTicksAreSilent() {
        let (model, writer) = makeModel()

        model.recordAuditTickState(previousPhase: model.state.phase)
        let afterFirst = writer.records.count
        for _ in 0 ..< 10 {
            model.recordAuditTickState(previousPhase: model.state.phase)
        }
        #expect(writer.records.count == afterFirst)
    }

    @Test("Accessibility trust loss is recorded as a transition")
    func accessibilityLossIsRecorded() {
        let (model, writer) = makeModel()

        model.recordAuditTickState(previousPhase: model.state.phase)
        model.setAccessibilityTrusted(false)
        model.recordAuditTickState(previousPhase: model.state.phase)

        let records = writer.records(ofType: .accessibilityChanged)
        #expect(records.count == 2)
        #expect(records[0].to == "granted")
        #expect(records[1].from == "granted")
        #expect(records[1].to == "denied")
        #expect(records[1].actor.token == "system")
    }

    // MARK: - Default installation

    @Test("A disabled log reports itself disabled and drops records")
    func disabledLogDropsRecords() {
        let log = AuditLog.disabled()
        #expect(log.isEnabled == false)
        // The point of the disabled default: an emitter that has not been
        // bootstrapped must be a no-op, never a crash and never a write into
        // the user's real ~/Library/Logs/Curfew.
        log.emit(.appLaunched, actor: .app)
    }
}
