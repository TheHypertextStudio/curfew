@testable import curfew_ctl
@testable import CurfewKit
import Foundation
import Testing

struct BreakGlassCommandTests {
    @Test("Emergency revocation does not require an issuance reason")
    func revokeWithoutReason() throws {
        _ = try BreakGlassCommand.parse(["--revoke"])
    }

    @Test("Emergency revocation can be previewed without an issuance reason")
    func previewRevokeWithoutReason() throws {
        _ = try BreakGlassCommand.parse(["--revoke", "--dry-run"])
    }

    @Test("Dry-run revocation leaves the existing release and secret untouched")
    func dryRunRevoke() throws {
        try withBreakGlassStore { store in
            try store.issue(
                reason: "recover a stalled lockout",
                issuedBy: "tester@host",
                now: Date()
            )
            let record = try Data(contentsOf: store.recordURL)
            let secret = try Data(contentsOf: store.secretURL)
            let canceller = RecordingShutdownCanceller()
            let command = try BreakGlassCommand.parse(["--revoke", "--dry-run"])
            let output = try command.output(
                store: store,
                canceller: canceller,
                isRoot: true,
                now: Date(),
                issuedBy: "tester@host"
            )
            #expect(output.contains("would remove"))
            #expect(try Data(contentsOf: store.recordURL) == record)
            #expect(try Data(contentsOf: store.secretURL) == secret)
            #expect(canceller.calls == 0)
        }
    }

    @Test("Dry-run issuance creates no state and never cancels shutdown")
    func dryRunIssue() throws {
        try withBreakGlassStore { store in
            let canceller = RecordingShutdownCanceller()
            let command = try BreakGlassCommand.parse([
                "--reason",
                "recover a stalled lockout",
                "--dry-run"
            ])
            let output = try command.output(
                store: store,
                canceller: canceller,
                isRoot: true,
                now: Date(),
                issuedBy: "tester@host"
            )
            #expect(output.contains("would write"))
            #expect(!FileManager.default.fileExists(atPath: store.recordURL.path))
            #expect(!FileManager.default.fileExists(atPath: store.secretURL.path))
            #expect(canceller.calls == 0)
        }
    }

    @Test("Revocation reports removal failures rather than claiming success")
    func revokeFailure() throws {
        try withBreakGlassStore { store in
            let failing = BreakGlassStore(
                fileManager: RemovalFailingFileManager(),
                recordURL: store.recordURL,
                secretURL: store.secretURL
            )
            let canceller = RecordingShutdownCanceller()
            let command = try BreakGlassCommand.parse(["--revoke"])
            #expect(throws: (any Error).self) {
                try command.output(
                    store: failing,
                    canceller: canceller,
                    isRoot: true,
                    now: Date(),
                    issuedBy: "tester@host"
                )
            }
            #expect(canceller.calls == 0)
        }
    }

    @Test("Repeated revocation safely keeps the release absent")
    func repeatedRevoke() throws {
        try withBreakGlassStore { store in
            let canceller = RecordingShutdownCanceller()
            let command = try BreakGlassCommand.parse(["--revoke"])
            let first = try command.output(
                store: store,
                canceller: canceller,
                isRoot: true,
                now: Date(),
                issuedBy: "tester@host"
            )
            let second = try command.output(
                store: store,
                canceller: canceller,
                isRoot: true,
                now: Date(),
                issuedBy: "tester@host"
            )
            #expect(first == second)
            #expect(!FileManager.default.fileExists(atPath: store.recordURL.path))
            #expect(!FileManager.default.fileExists(atPath: store.secretURL.path))
            #expect(canceller.calls == 0)
        }
    }

    @Test("Root issuance signs the release and invokes only the injected canceller")
    func rootIssue() throws {
        try withBreakGlassStore { store in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let canceller = RecordingShutdownCanceller()
            let command = try BreakGlassCommand.parse(["--reason", "recover a stalled lockout"])
            let output = try command.output(
                store: store,
                canceller: canceller,
                isRoot: true,
                now: now,
                issuedBy: "tester@host"
            )
            #expect(canceller.calls == 1)
            #expect(store.activeRelease(now: now)?.issuedBy == "tester@host")
            #expect(output.contains("cancelled a pending"))
            #expect(output.contains("display stays locked"))
        }
    }

    @Test("User issuance reports that a pending shutdown remains uncancelled")
    func userIssue() throws {
        try withBreakGlassStore { store in
            let canceller = RecordingShutdownCanceller()
            let command = try BreakGlassCommand.parse(["--reason", "recover a stalled lockout"])
            let output = try command.output(
                store: store,
                canceller: canceller,
                isRoot: false,
                now: Date(),
                issuedBy: "tester@host"
            )
            #expect(canceller.calls == 0)
            #expect(output.contains("was NOT cancelled"))
        }
    }

    @Test("Missing or short reasons fail before any recovery state changes")
    func invalidReason() throws {
        try withBreakGlassStore { store in
            let canceller = RecordingShutdownCanceller()
            for arguments in [[], ["--reason", "too short"]] {
                let command = try BreakGlassCommand.parse(arguments)
                #expect(throws: (any Error).self) {
                    try command.output(
                        store: store,
                        canceller: canceller,
                        isRoot: true,
                        now: Date(),
                        issuedBy: "tester@host"
                    )
                }
            }
            #expect(canceller.calls == 0)
            #expect(!FileManager.default.fileExists(atPath: store.recordURL.path))
            #expect(!FileManager.default.fileExists(atPath: store.secretURL.path))
        }
    }

    @Test("Cancellation failure reports the saved release and an unresolved countdown")
    func cancellationFailure() throws {
        let cancellers = [
            SystemShutdownCanceller(runCommand: { .exited(2) }),
            SystemShutdownCanceller(runCommand: { throw CocoaError(.executableNotLoadable) })
        ]
        for canceller in cancellers {
            try withBreakGlassStore { store in
                let now = Date()
                let command = try BreakGlassCommand.parse(["--reason", "recover a stalled lockout"])
                var message: String?
                do {
                    _ = try command.output(
                        store: store,
                        canceller: canceller,
                        isRoot: true,
                        now: now,
                        issuedBy: "tester@host"
                    )
                } catch {
                    message = error.localizedDescription
                    #expect(BreakGlassCommand.exitCode(for: error).rawValue != 0)
                }
                #expect(message?.contains("was saved") == true)
                #expect(message?.contains("may still be running") == true)
                #expect(store.activeRelease(now: now) != nil)
            }
        }
    }

    @Test("User issuance never runs even a failing shutdown command")
    func userDoesNotInvokeCancellation() throws {
        try withBreakGlassStore { store in
            let canceller =
                SystemShutdownCanceller(runCommand: { throw CocoaError(.executableNotLoadable) })
            let command = try BreakGlassCommand.parse(["--reason", "recover a stalled lockout"])
            let output = try command.output(
                store: store,
                canceller: canceller,
                isRoot: false,
                now: Date(),
                issuedBy: "tester@host"
            )
            #expect(output.contains("was NOT cancelled"))
        }
    }
}

private func withBreakGlassStore(_ body: (BreakGlassStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(BreakGlassStore(
        recordURL: directory.appendingPathComponent("release.json"),
        secretURL: directory.appendingPathComponent("secret")
    ))
}

private final class RecordingShutdownCanceller: PendingShutdownCanceling, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var calls: Int {
        lock.withLock { count }
    }

    func cancelPendingShutdown() -> Bool {
        lock.withLock { count += 1 }
        return true
    }
}

private final class RemovalFailingFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at url: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
