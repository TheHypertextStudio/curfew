import Foundation

/// The company-signed test build may verify commands and show overlays, but
/// must not issue or cancel a machine-wide root shutdown beside another build.
public nonisolated enum DevelopmentDaemonSafety {
    public static func shouldStandDown(
        flavor: CurfewFlavor,
        owner: EnforcementOwner?,
        ownerIsLive: Bool
    ) -> Bool {
        guard flavor == .development,
              let owner,
              ownerIsLive,
              owner.hasRecognizedIdentity,
              let ownerFlavor = CurfewFlavor(rawValue: owner.flavor)
        else { return false }
        return ownerFlavor.enforcementPriority > flavor.enforcementPriority
    }

    public static func evaluate(
        _ input: DaemonEnforcementDecision.Input,
        flavor: CurfewFlavor,
        owner: EnforcementOwner?,
        ownerIsLive: Bool
    ) -> DaemonEnforcementDecision.Outcome {
        let outcome = DaemonEnforcementDecision.evaluate(input)
        guard flavor == .development else { return outcome }
        let action: DaemonEnforcementDecision.Action =
            shouldStandDown(flavor: flavor, owner: owner, ownerIsLive: ownerIsLive)
                || outcome.action == .shutDown ? .wait : outcome.action
        return .init(
            action: action,
            deferralStartedAt: action == .wait ? nil : outcome.deferralStartedAt,
            cancelsPendingShutdown: false
        )
    }
}

public enum DevelopmentShutdownDisabled: Error, Equatable {
    case disabled
}

/// Secondary guard if a future decision regression reaches the effect seam.
public final class DevelopmentDaemonEffects: DaemonEnforcementEffects {
    private let underlying: any DaemonEnforcementEffects

    public init(underlying: any DaemonEnforcementEffects) {
        self.underlying = underlying
    }

    public func persistDeferralStart(_ start: Date?) {
        underlying.persistDeferralStart(start)
    }

    public func cancelPendingShutdown() {}

    public func issueShutdown() throws {
        throw DevelopmentShutdownDisabled.disabled
    }

    public func clearDeadlineShadow() {
        underlying.clearDeadlineShadow()
    }
}
