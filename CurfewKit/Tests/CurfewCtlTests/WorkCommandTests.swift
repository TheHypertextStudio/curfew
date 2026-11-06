@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct WorkCommandTests {
    @Test("Protected work claim supports structured JSON output")
    func claimJSONFlag() throws {
        _ = try WorkClaimCommand.parse(["--label", "build release", "--json"])
    }

    @Test("Protected work list supports structured JSON output")
    func listJSONFlag() throws {
        _ = try WorkListCommand.parse(["--json"])
    }

    @Test("Protected work release supports structured JSON output")
    func releaseJSONFlag() throws {
        _ = try WorkReleaseCommand.parse(["47B3580F-2E74-47C2-8D10-77CB55B973EA", "--json"])
    }

    @Test("Claim JSON exposes the stored identity and granted expiry")
    func claimJSON() throws {
        try withWorkStore { store in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let command = try WorkClaimCommand.parse([
                "--label",
                "build release",
                "--minutes",
                "60",
                "--json"
            ])
            let object = try workObject(command.output(store: store, policy: .default, now: now))
            let stored = try #require(store.load().first)
            #expect(object["id"] as? String == stored.id.uuidString)
            #expect(object["label"] as? String == "build release")
            #expect(object["source"] as? String == "cli")
            #expect(object["started_at"] as? String == ISO8601DateFormatter().string(from: now))
            #expect(object["expires_at"] as? String == ISO8601DateFormatter()
                .string(from: now.addingTimeInterval(1800)))
            #expect(object["maximum_deferral_seconds"] as? Int == ProtectedWorkPolicy.default
                .maximumDeferralMinutes * 60)
            #expect(object["maximum_deferral_minutes"] == nil)
        }
    }

    @Test("Renewing the same claim preserves its identity and initial start")
    func renewClaim() throws {
        try withWorkStore { store in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let original = try store.claim(label: "build", source: .cli, now: now, policy: .default)
            let command = try WorkClaimCommand.parse([
                "--label", "build release", "--id", original.id.uuidString, "--minutes", "20",
                "--json"
            ])
            let output = try command.output(
                store: store,
                policy: .default,
                now: now.addingTimeInterval(60)
            )
            let object = try workObject(output)
            #expect(object["id"] as? String == original.id.uuidString)
            #expect(object["started_at"] as? String == ISO8601DateFormatter()
                .string(from: original.startedAt))
            #expect(store.load().count == 1)
            #expect(store.load().first?.expiresAt == now.addingTimeInterval(1260))
        }
    }

    @Test("List JSON contains only live claims and supports an empty store")
    func listJSON() throws {
        try withWorkStore { store in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let command = try WorkListCommand.parse(["--json"])
            let empty = try workObject(command.output(store: store, now: now))
            #expect((empty["claims"] as? [Any])?.isEmpty == true)
            let live = try store.claim(label: "build", source: .cli, now: now, policy: .default)
            let output = try workObject(command.output(
                store: store,
                now: now.addingTimeInterval(1)
            ))
            let claims = try #require(output["claims"] as? [[String: Any]])
            #expect(claims.count == 1)
            #expect(claims.first?["id"] as? String == live.id.uuidString)
            let expired = try workObject(command.output(store: store, now: live.expiresAt))
            #expect((expired["claims"] as? [Any])?.isEmpty == true)
        }
    }

    @Test("Release JSON confirms absence and repeated release remains safe")
    func releaseJSON() throws {
        try withWorkStore { store in
            let claim = try store.claim(label: "build", source: .cli, now: Date(), policy: .default)
            let command = try WorkReleaseCommand.parse([claim.id.uuidString, "--json"])
            let first = try workObject(command.output(store: store))
            #expect(first["id"] as? String == claim.id.uuidString)
            #expect(first["released"] as? Bool == true)
            #expect(store.load().isEmpty)
            #expect(try command.output(store: store) == command.output(store: store))
        }
    }

    @Test("List reports corrupt or unsafe claim files rather than an empty list")
    func invalidListStore() throws {
        try withWorkStore { store in
            try Data("invalid JSON".utf8).write(to: store.recordURL)
            let command = try WorkListCommand.parse(["--json"])
            #expect(throws: (any Error).self) { try command.output(store: store, now: Date()) }
            try FileManager.default.removeItem(at: store.recordURL)
            try FileManager.default.createDirectory(
                at: store.recordURL,
                withIntermediateDirectories: true
            )
            #expect(throws: (any Error).self) { try command.output(store: store, now: Date()) }
        }
    }

    @Test("Invalid claim and release identities fail without creating a store")
    func invalidIdentity() throws {
        try withWorkStore { store in
            let claim = try WorkClaimCommand.parse(["--label", "build", "--id", "bad-id", "--json"])
            let release = try WorkReleaseCommand.parse(["bad-id", "--json"])
            #expect(throws: (any Error).self) { try claim.output(
                store: store,
                policy: .default,
                now: Date()
            ) }
            #expect(throws: (any Error).self) { try release.output(store: store) }
            #expect(!FileManager.default.fileExists(atPath: store.recordURL.path))
        }
    }
}

private func withWorkStore(_ body: (ProtectedWorkStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(ProtectedWorkStore(recordURL: directory.appendingPathComponent("claims.json")))
}

private func workObject(_ output: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
}
