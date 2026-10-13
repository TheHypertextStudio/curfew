import CryptoKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct LicenseActivationTests {
    @Test("Activation links accept only this build's scheme and one bounded ticket")
    func validatesActivationLink() throws {
        let token = String(repeating: "a", count: 43)
        #expect(try LicenseActivationController.token(
            in: #require(URL(string: "curfew://activate?token=\(token)")), flavor: .production
        ) == token)
        for link in [
            "https://example.com/activate?token=\(token)",
            "curfew-dev://activate?token=\(token)",
            "curfew://other?token=\(token)",
            "curfew://activate/extra?token=\(token)",
            "curfew://user@activate?token=\(token)",
            "curfew://activate:80?token=\(token)",
            "curfew://activate?token=\(token)&token=\(token)",
            "curfew://activate?token=short",
            "curfew://activate?token=\(token)&issuer=https://attacker.example"
        ] {
            #expect(try LicenseActivationController.token(
                in: #require(URL(string: link)),
                flavor: .production
            ) == nil)
        }
    }

    @Test("One ticket verifies, unlocks, and persists a real signed license for offline relaunch")
    func activatesAndPersists() async throws {
        let signer = Curve25519.Signing.PrivateKey()
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let publicKey = signer.publicKey.rawRepresentation.base64EncodedString()
        let gate = LicenseGate(defaults: defaults, publicKeyBase64: publicKey)
        let service = try PurchaseServiceStub(key: signedKey(signer))
        let flow = LicenseActivationController(gate: gate, service: service)
        await flow.activate(ticket: String(repeating: "a", count: 43))
        #expect(gate.isPlusUnlocked)
        #expect(gate.activatedKey?.email == "buyer@example.com")
        #expect(flow.message == "Curfew Plus is active.")
        #expect(!flow.isBusy)
        let relaunched = LicenseGate(defaults: defaults, publicKeyBase64: publicKey)
        relaunched.loadStoredKey()
        #expect(relaunched.isPlusUnlocked)
    }

    @Test("A forged or expired incoming key cannot replace an active purchase")
    func preservesActivePurchaseOnBadKey() async throws {
        let signer = Curve25519.Signing.PrivateKey()
        let gate = try LicenseGate(
            defaults: #require(UserDefaults(suiteName: UUID().uuidString)),
            publicKeyBase64: signer.publicKey.rawRepresentation
                .base64EncodedString()
        )
        try gate.activate(signedKey(signer))
        let original = gate.activatedKey
        for key in try [
            signedKey(Curve25519.Signing.PrivateKey()),
            signedKey(signer, expired: true)
        ] {
            let flow = LicenseActivationController(
                gate: gate,
                service: PurchaseServiceStub(key: key)
            )
            await flow.activate(ticket: String(repeating: "a", count: 43))
            #expect(flow.error != nil)
            #expect(gate.activatedKey == original)
            #expect(gate.isPlusUnlocked)
        }
    }

    @Test("Restore confirms an inbox request without unlocking Plus")
    func requestsRestoration() async throws {
        let gate = try LicenseGate(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let flow = LicenseActivationController(gate: gate, service: PurchaseServiceStub(key: ""))
        await flow.restore(email: " buyer@example.com ")
        #expect(flow.message == "Check buyer@example.com for your restore link.")
        #expect(!gate.isPlusUnlocked)
        #expect(!flow.isBusy)
    }

    @Test("A failed unattended refresh preserves the current purchase")
    func failedSilentRefreshPreservesPurchase() throws {
        let signer = Curve25519.Signing.PrivateKey()
        let gate = try LicenseGate(
            defaults: #require(UserDefaults(suiteName: UUID().uuidString)),
            publicKeyBase64: signer.publicKey.rawRepresentation
                .base64EncodedString()
        )
        try gate.activate(signedKey(signer))
        let original = gate.activatedKey
        try gate.activateSilently("invalid-response", replacing: #require(original))
        #expect(gate.activatedKey == original)
        #expect(gate.isPlusUnlocked)
    }

    @Test("An old refresh cannot replace a newer activation, including the same subscription")
    func staleRefreshPreservesNewActivation() throws {
        let signer = Curve25519.Signing.PrivateKey()
        for lifetime in [true, false] {
            let gate = try LicenseGate(
                defaults: #require(UserDefaults(suiteName: UUID().uuidString)),
                publicKeyBase64: signer.publicKey.rawRepresentation.base64EncodedString()
            )
            try gate.activate(signedKey(signer, expiresAt: "2090-01-01T00:00:00Z"))
            let original = try #require(gate.activatedKey)
            try gate.activate(signedKey(signer, expiresAt: lifetime ? nil : "2092-01-01T00:00:00Z"))
            let replacement = gate.activatedKey
            try gate.activateSilently(
                signedKey(signer, expiresAt: "2091-01-01T00:00:00Z"),
                replacing: original
            )
            #expect(gate.activatedKey == replacement)
        }
    }

    @Test("A canceled restore cannot report success for a subsequent request")
    func canceledRestoreCannotDismissNewRequest() async throws {
        let gate = try LicenseGate(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let service = SuspendedRestoreService()
        let flow = LicenseActivationController(gate: gate, service: service)
        let first = Task { await flow.restore(email: "old@example.com") }
        await service.waitForRequest("old@example.com")
        flow.cancel()
        let second = Task { await flow.restore(email: "new@example.com") }
        await service.waitForRequest("new@example.com")
        await service.release("old@example.com")
        #expect(await first.value == false)
        #expect(flow.isBusy)
        await service.release("new@example.com")
        #expect(await second.value == true)
        #expect(flow.message == "Check new@example.com for your restore link.")
    }

    @Test("Repeated OS delivery of one link still activates exactly once")
    func repeatedLinkDelivery() async throws {
        let signer = Curve25519.Signing.PrivateKey()
        let gate = try LicenseGate(
            defaults: #require(UserDefaults(suiteName: UUID().uuidString)),
            publicKeyBase64: signer.publicKey.rawRepresentation
                .base64EncodedString()
        )
        let service = SuspendedPurchaseService()
        let flow = LicenseActivationController(gate: gate, service: service)
        let url =
            try #require(
                URL(string: "curfew://activate?token=\(String(repeating: "a", count: 43))")
            )
        #expect(flow.open(url, flavor: .production))
        #expect(flow.open(url, flavor: .production))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        try await service.release(signedKey(signer))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(gate.isPlusUnlocked)
        #expect(!flow.isBusy)
    }

    @Test("Canceling before a link task starts sends no redemption request")
    func cancelsQueuedActivation() async throws {
        let gate = try LicenseGate(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let service = CountingPurchaseService()
        let flow = LicenseActivationController(gate: gate, service: service)
        let url =
            try #require(
                URL(string: "curfew://activate?token=\(String(repeating: "a", count: 43))")
            )
        #expect(flow.open(url, flavor: .production))
        flow.cancel()
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(await service.requests == 0)
        #expect(flow.message == nil)
        #expect(flow.error == nil)
        #expect(!flow.isBusy)
    }

    private func signedKey(
        _ signer: Curve25519.Signing.PrivateKey,
        expired: Bool = false,
        expiresAt: String? = nil
    ) throws -> String {
        let expiry = expired ? "2020-01-01T00:00:00Z" : expiresAt
        var fields = [
            "email": "buyer@example.com",
            "product": "curfew-plus",
            "order_id": "cs_test",
            "issued_at": "2026-01-01T00:00:00Z",
            "plan": expiry == nil ? "lifetime" : "subscription"
        ]
        if let expiry {
            fields["expires_at"] = expiry
            fields["refresh_token"] = "same-subscription-token"
        }
        let payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return try "\(encode(payload)).\(encode(signer.signature(for: payload)))"
    }
}

private actor CountingPurchaseService: LicenseServicing {
    private(set) var requests = 0
    func redeem(ticket _: String) async throws -> String {
        requests += 1
        throw LicenseServiceError.unavailable
    }

    func restore(email _: String) async throws {}
}

private actor SuspendedRestoreService: LicenseServicing {
    private var requests: [String: CheckedContinuation<Void, Never>] = [:]
    private var starts: [String: CheckedContinuation<Void, Never>] = [:]
    func redeem(ticket _: String) async throws -> String {
        throw LicenseServiceError.unavailable
    }

    func restore(email: String) async throws {
        await withCheckedContinuation {
            requests[email] = $0
            starts.removeValue(forKey: email)?.resume()
        }
    }

    func waitForRequest(_ email: String) async {
        if requests[email] != nil {
            return
        }
        await withCheckedContinuation { starts[email] = $0 }
    }

    func release(_ email: String) {
        requests.removeValue(forKey: email)?.resume()
    }
}

private struct PurchaseServiceStub: LicenseServicing {
    let key: String
    func redeem(ticket _: String) async throws -> String {
        key
    }

    func restore(email _: String) async throws {}
}

private actor SuspendedPurchaseService: LicenseServicing {
    private var continuation: CheckedContinuation<String, Never>?
    private var resolvedKey: String?
    func redeem(ticket _: String) async throws -> String {
        if let resolvedKey {
            return resolvedKey
        }
        return await withCheckedContinuation { continuation = $0 }
    }

    func restore(email _: String) async throws {}
    func release(_ key: String) {
        resolvedKey = key
        continuation?.resume(returning: key)
        continuation = nil
    }
}
