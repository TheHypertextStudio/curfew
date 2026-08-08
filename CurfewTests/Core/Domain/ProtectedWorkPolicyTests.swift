@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for ``ProtectedWorkPolicy`` — the allowlist that keeps
/// graceful termination away from terminals and agent CLIs, and the clamps
/// that stop a user (or a hand-edited file) configuring their way out of
/// enforcement.
struct ProtectedWorkPolicyTests {
    @Test("Defaults protect terminal emulators and agent CLIs")
    func defaultsProtectAgentHosts() {
        let policy = ProtectedWorkPolicy.default
        #expect(policy.protectsApplication(
            bundleIdentifier: "com.apple.Terminal",
            executableName: nil
        ))
        #expect(policy.protectsApplication(
            bundleIdentifier: "com.googlecode.iterm2",
            executableName: nil
        ))
        #expect(policy.protectsApplication(
            bundleIdentifier: nil,
            executableName: "claude"
        ))
        #expect(policy.protectsApplication(
            bundleIdentifier: nil,
            executableName: "ssh"
        ))
    }

    @Test("Unlisted applications are not protected")
    func unlistedApplicationsAreTerminated() {
        let policy = ProtectedWorkPolicy.default
        #expect(!policy.protectsApplication(
            bundleIdentifier: "com.apple.Safari",
            executableName: "Safari"
        ))
        #expect(!policy.protectsApplication(bundleIdentifier: nil, executableName: nil))
    }

    @Test("Matching ignores case but never matches on a prefix")
    func matchingIsExactAndCaseInsensitive() {
        let policy = ProtectedWorkPolicy.default
        #expect(policy.protectsApplication(
            bundleIdentifier: "COM.APPLE.TERMINAL",
            executableName: nil
        ))
        // A prefix rule would shield everything Apple ships. It must not.
        #expect(!policy.protectsApplication(
            bundleIdentifier: "com.apple.TerminalExtras",
            executableName: nil
        ))
    }

    @Test("Maximum deferral is clamped to the ceiling on construction")
    func deferralIsClampedOnConstruction() {
        let greedy = ProtectedWorkPolicy(
            protectedBundleIdentifiers: [],
            protectedProcessNames: [],
            acceptsAgentClaims: true,
            maximumDeferralMinutes: 100_000,
            defaultLeaseMinutes: 10
        )
        #expect(greedy.maximumDeferralMinutes == ProtectedWorkPolicy.deferralCeilingMinutes)

        let negative = ProtectedWorkPolicy(
            protectedBundleIdentifiers: [],
            protectedProcessNames: [],
            acceptsAgentClaims: true,
            maximumDeferralMinutes: -5,
            defaultLeaseMinutes: 10
        )
        #expect(negative.maximumDeferralMinutes == 1)
    }

    @Test("A hand-edited policy file cannot exceed the ceiling")
    func decodingClampsDeferral() throws {
        let json = Data("""
        {"acceptsAgentClaims":true,"defaultLeaseMinutes":999,\
        "maximumDeferralMinutes":100000,"protectedBundleIdentifiers":[],\
        "protectedProcessNames":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(ProtectedWorkPolicy.self, from: json)
        #expect(decoded.maximumDeferralMinutes == ProtectedWorkPolicy.deferralCeilingMinutes)
        #expect(decoded.defaultLeaseMinutes == ProtectedWorkPolicy.leaseCeilingMinutes)
    }

    @Test("Requested leases are clamped, absent ones fall back to the default")
    func leaseClamping() {
        let policy = ProtectedWorkPolicy.default
        #expect(policy.leaseMinutes(requested: nil) == policy.defaultLeaseMinutes)
        #expect(policy.leaseMinutes(requested: 5) == 5)
        #expect(policy.leaseMinutes(requested: 10000) == ProtectedWorkPolicy.leaseCeilingMinutes)
        #expect(policy.leaseMinutes(requested: 0) == 1)
    }

    @Test("Policy mirror round-trips through the filesystem")
    func mirrorRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("protected-work-policy.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var policy = ProtectedWorkPolicy.default
        policy.protectedProcessNames = ["my-agent"]
        policy.maximumDeferralMinutes = 45
        try policy.writeMirror(to: url)

        let loaded = ProtectedWorkPolicy.loadMirror(from: url)
        #expect(loaded == policy)
    }

    @Test("A missing or corrupt mirror falls back to defaults, not to zero protection")
    func mirrorFailsToDefaults() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        #expect(ProtectedWorkPolicy.loadMirror(from: missing) == .default)

        let corrupt = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        #expect(ProtectedWorkPolicy.loadMirror(from: corrupt) == .default)
    }

    @Test("Settings carry the policy and upgrade a payload that predates it")
    func settingsRoundTripAndUpgrade() throws {
        let settings = CurfewSettings.default
        #expect(settings.protectedWork == .default)

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CurfewSettings.self, from: encoded)
        #expect(decoded.protectedWork == settings.protectedWork)

        // Strip the key the way a v0.1 payload would have, and confirm the
        // upgrade lands on defaults rather than an empty allowlist.
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "protectedWork")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let upgraded = try JSONDecoder().decode(CurfewSettings.self, from: legacy)
        #expect(upgraded.protectedWork == .default)
    }
}
