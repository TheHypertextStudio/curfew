@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Behaviour tests for ``AIConsentPolicy``.
@MainActor
struct AIConsentPolicyTests {
    @Test("Default policy is queue")
    func defaultPolicyIsQueue() {
        // The model initialises aiConsentPolicy = .queue. Tests inject a
        // model directly so we can verify the default without launching the UI.
        let model = makeModel()
        #expect(model.aiConsentPolicy == .queue)
    }

    @Test("All cases have non-empty display names")
    func allCasesHaveDisplayNames() {
        for policy in AIConsentPolicy.allCases {
            #expect(!policy.displayName.isEmpty)
            #expect(!policy.rationale.isEmpty)
        }
    }

    @Test("AIConsentPolicy round-trips through JSON")
    func jsonRoundTrip() throws {
        for policy in AIConsentPolicy.allCases {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(AIConsentPolicy.self, from: data)
            #expect(decoded == policy)
        }
    }

    @Test("Policy is backed by settings, so it persists across relaunch")
    func policyPersistsThroughSettings() throws {
        let model = makeModel()

        model.aiConsentPolicy = .autoApprove
        #expect(model.settings.aiConsentPolicyRawValue == "autoApprove")

        // Simulates a relaunch: the single source of truth is `settings`, not
        // a standalone in-memory property, so it survives an encode/decode.
        let data = try JSONEncoder().encode(model.settings)
        let decoded = try JSONDecoder().decode(CurfewSettings.self, from: data)
        #expect(decoded.aiConsentPolicyRawValue == "autoApprove")
    }

    @Test("handleNewMCPRequests queues requests under .queue policy")
    func queuePolicyQueuesRequests() {
        let model = makeModel()
        model.aiConsentPolicy = .queue
        let request = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"finish up"}"#
        )

        model.handleNewMCPRequests([request])

        // Use contains rather than count to tolerate stale entries the
        // monitor may have loaded from the developer's live queue file.
        #expect(model.pendingMCPRequests.contains { $0.id == request.id })
    }

    @Test("handleNewMCPRequests does not add duplicates")
    func noDuplicateRequests() {
        let model = makeModel()
        model.aiConsentPolicy = .queue
        let request = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"finish up"}"#
        )

        let countBefore = model.pendingMCPRequests.count
        model.handleNewMCPRequests([request])
        let countAfterFirst = model.pendingMCPRequests.count
        model.handleNewMCPRequests([request])
        let countAfterSecond = model.pendingMCPRequests.count

        // Second call must not add a second copy.
        #expect(countAfterFirst == countBefore + 1)
        #expect(countAfterSecond == countAfterFirst)
    }

    @Test("denyMCPRequest removes the request from pending list")
    func denyRemovesFromPending() {
        let model = makeModel()
        model.aiConsentPolicy = .queue
        let request = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"test"}"#
        )

        model.handleNewMCPRequests([request])
        #expect(model.pendingMCPRequests.contains { $0.id == request.id })

        model.denyMCPRequest(request, reason: "Not during working hours")
        #expect(!model.pendingMCPRequests.contains { $0.id == request.id })
    }

    @Test("handleNewMCPRequests discards all under .deny policy")
    func denyPolicyDiscards() {
        let model = makeModel()
        model.aiConsentPolicy = .deny
        let request = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"finish up"}"#
        )

        model.handleNewMCPRequests([request])

        // Under deny policy, requests are NOT queued in-memory — they are
        // written back to the file as denied. The specific request must not
        // appear in the pending list.
        #expect(!model.pendingMCPRequests.contains { $0.id == request.id })
    }

    // MARK: - Helpers

    /// An isolated `UserDefaults` suite per call, so mutating `aiConsentPolicy`
    /// (which persists through `settings` since it's the single source of
    /// truth) never leaks into the shared/default domain and pollutes other
    /// tests or runs.
    private func makeModel() -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
    }
}
