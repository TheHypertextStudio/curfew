@testable import Curfew
import Foundation
import Testing

struct DaemonLockoutDeadlineResolverTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A daemon enforces a remote deadline even when no app deadline exists")
    func resolvesRemoteOnlyDeadline() {
        let remote = record(startOffset: -30, endOffset: 900, kind: .remoteCommand)

        #expect(
            DaemonLockoutDeadlineResolver.resolve(
                now: now,
                user: nil,
                shadow: nil,
                remote: remote
            ) == remote
        )
    }

    @Test("The daemon chooses the strongest active deadline across every command source")
    func choosesStrongestDeadline() {
        let user = record(startOffset: -120, endOffset: 300, kind: .scheduledTime)
        let shadow = record(startOffset: -120, endOffset: 600, kind: .scheduledHours)
        let remote = record(startOffset: -30, endOffset: 900, kind: .remoteCommand)

        let resolved = DaemonLockoutDeadlineResolver.resolve(
            now: now,
            user: user,
            shadow: shadow,
            remote: remote
        )

        #expect(resolved?.scheduledUnlockAt == now.addingTimeInterval(900))
        #expect(resolved?.lockoutStartedAt == now.addingTimeInterval(-120))
        #expect(resolved?.kind == .remoteCommand)
    }

    @Test("Expired records cannot resurrect an ended lockout")
    func ignoresExpiredDeadlines() {
        let expired = record(startOffset: -900, endOffset: -1, kind: .remoteCommand)

        #expect(
            DaemonLockoutDeadlineResolver.resolve(
                now: now,
                user: nil,
                shadow: nil,
                remote: expired
            ) == nil
        )
    }

    @Test("Applied remote result locks only its enrolled device and never shortens a deadline")
    func projectsAuthenticatedResultIntoStrongerLocalDeadline() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deviceID = try #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35"))
        let existing = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-60),
            scheduledUnlockAt: now.addingTimeInterval(1800),
            kind: .scheduledTime
        )
        let shorter = RemoteCommandResult(
            commandID: UUID(),
            deviceID: deviceID,
            sequence: 1,
            stage: .applied,
            resolvedAt: now,
            appliedDeadline: now.addingTimeInterval(900)
        )
        let longer = RemoteCommandResult(
            commandID: UUID(),
            deviceID: deviceID,
            sequence: 2,
            stage: .applied,
            resolvedAt: now,
            appliedDeadline: now.addingTimeInterval(3600)
        )

        #expect(RemoteCommandLockoutProjection.resolve(
            result: shorter,
            enrolledDeviceID: deviceID,
            now: now,
            current: existing
        ) == existing)
        #expect(RemoteCommandLockoutProjection.resolve(
            result: longer,
            enrolledDeviceID: deviceID,
            now: now,
            current: existing
        )?.scheduledUnlockAt == now.addingTimeInterval(3600))
        #expect(RemoteCommandLockoutProjection.resolve(
            result: RemoteCommandResult(
                commandID: UUID(),
                deviceID: UUID(),
                sequence: 3,
                stage: .applied,
                resolvedAt: now,
                appliedDeadline: now.addingTimeInterval(3600)
            ),
            enrolledDeviceID: deviceID,
            now: now,
            current: nil
        ) == nil)
    }

    private func record(
        startOffset: TimeInterval,
        endOffset: TimeInterval,
        kind: LockoutKind
    ) -> LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(startOffset),
            scheduledUnlockAt: now.addingTimeInterval(endOffset),
            kind: kind
        )
    }
}
