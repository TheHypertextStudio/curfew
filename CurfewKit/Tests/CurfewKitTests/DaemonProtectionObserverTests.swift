import CurfewKit
import Foundation
import Testing

struct DaemonProtectionObserverTests {
    @Test("A daemon started before login reads the current user's recovery files on the next tick")
    func consoleAppearsAfterBoot() throws {
        try withProtectionFixture { root, user in
            let directory = ProtectionDirectory(root)
            let observer = DaemonProtectionObserver(
                applicationSupport: { directory.url },
                live: .disabled
            )
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let deadline = protectionDeadline(now)
            #expect(observer.observe(now: now, deadline: deadline, policy: .default)
                .breakGlass == nil)
            let release = try BreakGlassStore(
                recordURL: user.appendingPathComponent("break-glass.json"),
                secretURL: user.appendingPathComponent(".break-glass-secret")
            )
            .issue(reason: "recover a stalled lockout", issuedBy: "tester@host", now: now)
            try ProtectedWorkStore(recordURL: user.appendingPathComponent("protected-work.json"))
                .claim(label: "build release", source: .cli, now: now, policy: .default)
            directory.url = user
            let observation = observer.observe(now: now, deadline: deadline, policy: .default)
            #expect(observation.breakGlass?.id == release.id)
            #expect(observation.hasProtectedWork)
        }
    }

    @Test("Switching console users does not retain the previous user's claims")
    func consoleSwitch() throws {
        try withProtectionFixture { first, second in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            try ProtectedWorkStore(recordURL: first.appendingPathComponent("protected-work.json"))
                .claim(label: "old user job", source: .cli, now: now, policy: .default)
            let directory = ProtectionDirectory(first)
            let observer = DaemonProtectionObserver(
                applicationSupport: { directory.url },
                live: .disabled
            )
            #expect(observer.observe(now: now, deadline: protectionDeadline(now), policy: .default)
                .hasProtectedWork)
            directory.url = second
            #expect(!observer.observe(now: now, deadline: protectionDeadline(now), policy: .default)
                .hasProtectedWork)
        }
    }
}

private final class ProtectionDirectory {
    var url: URL
    init(_ url: URL) {
        self.url = url
    }
}

private func protectionDeadline(_ now: Date) -> LockoutDeadlineRecord {
    LockoutDeadlineRecord(
        lockoutStartedAt: now.addingTimeInterval(-60),
        scheduledUnlockAt: now.addingTimeInterval(3600),
        kind: .scheduledTime
    )
}

private func withProtectionFixture(_ body: (URL, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(
        directory.appendingPathComponent("boot-root"),
        directory.appendingPathComponent("console-user")
    )
}
