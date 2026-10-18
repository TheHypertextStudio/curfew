@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct DevelopmentDaemonSafetyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A live higher-priority app prevents Curfew Dev command enforcement")
    func liveOwnerDeniesRemoteLock() {
        let owner = makeOwner(flavor: .production, bundleIdentifier: "studio.hypertext.curfew")
        #expect(DevelopmentDaemonSafety.shouldStandDown(
            flavor: .development,
            owner: owner,
            ownerIsLive: true
        ))
        #expect(!DevelopmentDaemonSafety.shouldStandDown(
            flavor: .development,
            owner: owner,
            ownerIsLive: false
        ))
        #expect(!DevelopmentDaemonSafety.shouldStandDown(
            flavor: .development,
            owner: makeOwner(flavor: .development, bundleIdentifier: "com.example.imposter"),
            ownerIsLive: true
        ))
    }

    @Test("A stale Curfew Dev heartbeat never schedules root shutdown")
    func staleHeartbeatCannotShutdown() {
        let deadline = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-120),
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .remoteCommand
        )
        let input = DaemonEnforcementDecision.Input(
            now: now,
            deadline: deadline,
            heartbeatAge: .infinity,
            heartbeatTimeout: 90
        )
        let owner = makeOwner(flavor: .production, bundleIdentifier: "studio.hypertext.curfew")

        let withOwner = DevelopmentDaemonSafety.evaluate(
            input,
            flavor: .development,
            owner: owner,
            ownerIsLive: true
        )
        let withoutOwner = DevelopmentDaemonSafety.evaluate(
            input,
            flavor: .development,
            owner: nil,
            ownerIsLive: false
        )
        #expect(withOwner.action == .wait)
        #expect(withoutOwner.action == .wait)
        #expect(!withOwner.cancelsPendingShutdown)
        #expect(!withoutOwner.cancelsPendingShutdown)
    }

    @Test("Curfew Dev effects cannot issue or cancel another daemon's shutdown")
    func rootShutdownEffectsAreInert() {
        let underlying = RecordingShutdownEffects()
        let effects = DevelopmentDaemonEffects(underlying: underlying)
        effects.cancelPendingShutdown()
        #expect(throws: DevelopmentShutdownDisabled.self) {
            try effects.issueShutdown()
        }
        #expect(underlying.issueCount == 0)
        #expect(underlying.cancelCount == 0)
    }

    private func makeOwner(flavor: CurfewFlavor, bundleIdentifier: String) -> EnforcementOwner {
        EnforcementOwner(
            flavor: flavor.rawValue,
            bundleIdentifier: bundleIdentifier,
            displayName: "Curfew\(flavor.displaySuffix)",
            processIdentifier: 42,
            acquiredAt: now
        )
    }
}

private final class RecordingShutdownEffects: DaemonEnforcementEffects {
    var issueCount = 0
    var cancelCount = 0

    func persistDeferralStart(_: Date?) {}
    func cancelPendingShutdown() {
        cancelCount += 1
    }

    func issueShutdown() throws {
        issueCount += 1
    }

    func clearDeadlineShadow() {}
}
