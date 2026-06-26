@testable import Curfew
import Foundation
import Testing

/// Entitlement logic for Curfew Plus: the lifetime-vs-subscription split, the
/// expiry-aware unlock, and backward-tolerant decoding of the v2 payload. These
/// exercise the parts that don't need a real Ed25519 signature — the gate's
/// computed `isPlusUnlocked` (via the debug inject hook) and `LicenseKey`'s
/// `Codable` mapping.
@MainActor
struct LicenseGateTests {
    /// A gate backed by a throwaway UserDefaults suite so tests don't share
    /// persisted keys.
    private func makeGate() -> LicenseGate {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return LicenseGate(defaults: defaults)
    }

    @Test("No key leaves Plus locked")
    func noKeyLocked() {
        #expect(!makeGate().isPlusUnlocked)
    }

    @Test("A lifetime key (no expiry) unlocks Plus perpetually")
    func lifetimeUnlocks() {
        let gate = makeGate()
        gate.testInjectActivatedKey(
            LicenseKey(
                email: "a@b.c",
                product: "curfew-plus",
                plan: .lifetime,
                orderID: "o",
                issuedAt: Date()
            )
        )
        #expect(gate.isPlusUnlocked)
    }

    @Test("A subscription key unlocks while current and locks once expired")
    func subscriptionExpiryGatesUnlock() {
        let gate = makeGate()

        gate.testInjectActivatedKey(
            LicenseKey(
                email: "a@b.c",
                product: "curfew-plus",
                plan: .subscription,
                orderID: "s",
                issuedAt: Date(),
                expiresAt: Date().addingTimeInterval(86400),
                refreshToken: "tok"
            )
        )
        #expect(gate.isPlusUnlocked)

        gate.testInjectActivatedKey(
            LicenseKey(
                email: "a@b.c",
                product: "curfew-plus",
                plan: .subscription,
                orderID: "s",
                issuedAt: Date(),
                expiresAt: Date().addingTimeInterval(-60),
                refreshToken: "tok"
            )
        )
        #expect(!gate.isPlusUnlocked)
    }

    @Test("Decodes the v2 subscription payload (plan, expires_at, refresh_token)")
    func decodesSubscriptionPayload() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"email":"a@b.c","product":"curfew-plus","plan":"subscription",\
        "order_id":"s","issued_at":"2026-06-25T00:00:00Z",\
        "expires_at":"2026-07-25T00:00:00Z","refresh_token":"tok"}
        """.data(using: .utf8)!

        let key = try decoder.decode(LicenseKey.self, from: json)
        #expect(key.plan == .subscription)
        #expect(key.refreshToken == "tok")
        #expect(key.expiresAt != nil)
    }

    @Test("A pre-v2 payload (no plan/expiry) decodes as a perpetual lifetime key")
    func decodesLegacyPayloadAsLifetime() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"email":"a@b.c","product":"curfew-pro","order_id":"o",\
        "issued_at":"2026-06-25T00:00:00Z"}
        """.data(using: .utf8)!

        let key = try decoder.decode(LicenseKey.self, from: json)
        #expect(key.plan == .lifetime)
        #expect(key.expiresAt == nil)
        #expect(key.refreshToken == nil)
    }
}
