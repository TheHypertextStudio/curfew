import CryptoKit
@testable import Curfew
import Foundation
import Observation
import Synchronization
import Testing

@MainActor
struct LicenseExpiryTests {
    @Test("A signed deadline publishes one eligibility transition without replacing the purchase")
    func signedDeadlinePublishesTransition() throws {
        let fixture = try LicenseExpiryFixture()
        let key = try fixture.signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60))
        fixture.gate.activate(key)
        #expect(fixture.gate.isPlusUnlocked)
        var transitions = 0
        fixture.gate.onActivationChange = { transitions += 1 }
        let observations = Mutex(0)
        withObservationTracking {
            _ = fixture.gate.isPlusUnlocked
        } onChange: {
            observations.withLock { $0 += 1 }
        }

        fixture.clock.date += 60
        fixture.gate.reevaluateEligibility()
        #expect(!fixture.gate.isPlusUnlocked)
        #expect(transitions == 1)
        #expect(observations.withLock { $0 } == 1)
        #expect(fixture.gate.activatedKey?.refreshToken == "purchase-token")
        #expect(fixture.defaults.string(forKey: "pro.licenseKey") == key)
        fixture.gate.reevaluateEligibility()
        #expect(transitions == 1)
    }

    @Test("Replacing a subscription makes its former deadline harmless", arguments: [true, false])
    func replacementSupersedesOldDeadline(lifetime: Bool) throws {
        let fixture = try LicenseExpiryFixture()
        try fixture.gate
            .activate(fixture.signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60)))
        var changes = 0
        fixture.gate.onActivationChange = { changes += 1 }
        let replacement = try fixture.signedKey(
            expiresAt: lifetime ? nil : fixture.clock.date.addingTimeInterval(120)
        )
        fixture.gate.activate(replacement)
        #expect(changes == 1)
        fixture.clock.date += 60
        fixture.gate.reevaluateEligibility()
        #expect(fixture.gate.isPlusUnlocked)
        #expect(changes == 1)
        #expect(fixture.defaults.string(forKey: "pro.licenseKey") == replacement)
        fixture.clock.date += 60
        fixture.gate.reevaluateEligibility()
        #expect(fixture.gate.isPlusUnlocked == lifetime)
        #expect(changes == (lifetime ? 1 : 2))
    }

    @Test("Reevaluation after sleep or a clock jump uses the current deadline")
    func clockBoundaryReevaluatesEligibility() throws {
        let fixture = try LicenseExpiryFixture()
        try fixture.gate
            .activate(fixture.signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60)))
        fixture.clock.date += 600
        fixture.gate.reevaluateEligibility()
        #expect(!fixture.gate.isPlusUnlocked)
        fixture.clock.date -= 600
        fixture.gate.reevaluateEligibility()
        #expect(fixture.gate.isPlusUnlocked)
        fixture.gate.deactivate()
        fixture.clock.date += 600
        fixture.gate.reevaluateEligibility()
        #expect(!fixture.gate.isPlusUnlocked)
    }

    @Test("A matching signed renewal restores eligibility once after the old key expires")
    func renewalReopensExpiredEligibility() throws {
        let fixture = try LicenseExpiryFixture()
        try fixture.gate
            .activate(fixture.signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60)))
        let original = try #require(fixture.gate.activatedKey)
        fixture.clock.date += 60
        fixture.gate.reevaluateEligibility()
        #expect(!fixture.gate.isPlusUnlocked)
        var changes = 0
        fixture.gate.onActivationChange = { changes += 1 }
        let renewed = try fixture.signedKey(expiresAt: fixture.clock.date.addingTimeInterval(600))
        fixture.gate.activateSilently(renewed, replacing: original)
        #expect(fixture.gate.isPlusUnlocked)
        #expect(changes == 1)
        #expect(fixture.defaults.string(forKey: "pro.licenseKey") == renewed)
        fixture.gate.reevaluateEligibility()
        #expect(changes == 1)
    }

    @Test(
        "Same-key load and activation refresh eligibility after a corrected clock",
        arguments: ["load", "activate", "refresh"]
    )
    func sameKeyReevaluatesEligibility(operation: String) throws {
        let fixture = try LicenseExpiryFixture()
        let key = try fixture.signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60))
        fixture.gate.activate(key)
        let original = try #require(fixture.gate.activatedKey)
        fixture.clock.date += 60
        fixture.gate.reevaluateEligibility()
        #expect(!fixture.gate.isPlusUnlocked)
        fixture.clock.date -= 60
        var changes = 0
        fixture.gate.onActivationChange = { changes += 1 }
        switch operation {
        case "load": fixture.gate.loadStoredKey()
        case "refresh": fixture.gate.activateSilently(key, replacing: original)
        default: fixture.gate.activate(key)
        }
        #expect(fixture.gate.isPlusUnlocked)
        #expect(changes == 1)
    }

    @Test("Rejected incoming keys still close an expired existing grant", arguments: [true, false])
    func failedActivationReevaluatesExistingGrant(silent: Bool) throws {
        let fixture = try LicenseExpiryFixture()
        let key = try fixture.signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60))
        fixture.gate.activate(key)
        let original = try #require(fixture.gate.activatedKey)
        fixture.clock.date += 60
        if silent {
            fixture.gate.activateSilently("invalid-key", replacing: original)
        } else {
            fixture.gate.activate("invalid-key")
        }
        #expect(!fixture.gate.isPlusUnlocked)
        #expect(fixture.gate.activatedKey == original)
        #expect(fixture.defaults.string(forKey: "pro.licenseKey") == key)
    }

    @Test("Expiry removes success for the activated purchase without clearing its signed key")
    func expiryRemovesActivationSuccess() throws {
        let fixture = try LicenseExpiryFixture()
        let flow = LicenseActivationController(gate: fixture.gate)
        try flow
            .activateManually(fixture
                .signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60)))
        #expect(flow.message == "Curfew Plus is active.")
        fixture.clock.date += 60
        fixture.gate.reevaluateEligibility()
        #expect(flow.message == nil)
        #expect(fixture.gate.activatedKey != nil)
    }

    @Test("An expiry transition preserves an in-flight restore request and its result")
    func expiryPreservesRestoreWork() async throws {
        let fixture = try LicenseExpiryFixture()
        let service = ExpiryRestoreService()
        let flow = LicenseActivationController(gate: fixture.gate, service: service)
        try flow
            .activateManually(fixture
                .signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60)))
        let request = Task { await flow.restore(email: "buyer@example.com") }
        await service.waitUntilRequested()
        fixture.clock.date += 60
        fixture.gate.reevaluateEligibility()
        #expect(!fixture.gate.isPlusUnlocked)
        #expect(flow.isBusy)
        #expect(flow.message == "Sending restore link…")
        await service.finish()
        #expect(await request.value)
        fixture.gate.reevaluateEligibility()
        #expect(flow.message == "Check buyer@example.com for your restore link.")
        #expect(!flow.isBusy)
    }

    @Test("Expiry preserves user-facing errors and cannot revive stale activation success")
    func expiryPreservesErrorsAndReplacementIdentity() throws {
        let fixture = try LicenseExpiryFixture()
        let flow = LicenseActivationController(gate: fixture.gate)
        try flow
            .activateManually(fixture
                .signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60)))
        try fixture.gate.activate(fixture.signedKey(expiresAt: nil))
        #expect(flow.message == nil)
        try flow
            .activateManually(fixture
                .signedKey(expiresAt: fixture.clock.date.addingTimeInterval(60)))
        flow.activateManually("invalid-key")
        let error = flow.error
        #expect(error != nil)
        fixture.clock.date += 600
        fixture.gate.reevaluateEligibility()
        #expect(flow.error == error)
        #expect(flow.message == nil)
        #expect(!fixture.gate.isPlusUnlocked)
    }
}

@MainActor
final class LicenseExpiryClock {
    var date = Date(timeIntervalSince1970: 4_000_000_000)
}

@MainActor
struct LicenseExpiryFixture {
    let clock = LicenseExpiryClock()
    let signer = Curve25519.Signing.PrivateKey()
    let defaults: UserDefaults
    let gate: LicenseGate

    init() throws {
        self.defaults = try #require(UserDefaults(suiteName: "curfew-expiry-tests-\(UUID())"))
        self.gate = LicenseGate(
            defaults: defaults,
            publicKeyBase64: signer.publicKey.rawRepresentation.base64EncodedString(),
            now: { [clock] in clock.date }
        )
    }

    func signedKey(expiresAt: Date?) throws -> String {
        let key = LicenseKey(
            email: "buyer@example.com", product: "curfew-plus",
            plan: expiresAt == nil ? .lifetime : .subscription,
            orderID: "test-purchase", issuedAt: clock.date,
            expiresAt: expiresAt, refreshToken: expiresAt == nil ? nil : "purchase-token"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(key)
        func encode(_ bytes: Data) -> String {
            bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return try "\(encode(payload)).\(encode(signer.signature(for: payload)))"
    }
}

private actor ExpiryRestoreService: LicenseServicing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?

    func redeem(ticket _: String) async throws -> String {
        throw LicenseServiceError.unavailable
    }

    func restore(email _: String) async throws {
        await withCheckedContinuation {
            continuation = $0
            waiting?.resume()
            waiting = nil
        }
    }

    func waitUntilRequested() async {
        if continuation == nil {
            await withCheckedContinuation { waiting = $0 }
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
