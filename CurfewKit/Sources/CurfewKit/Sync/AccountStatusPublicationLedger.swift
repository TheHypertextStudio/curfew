import Foundation

/// Tracks HTTP acknowledgement, never socket liveness. Attempted reports do not
/// become synchronized merely because the next heartbeat has identical content.
@MainActor
public final class AccountStatusPublicationLedger {
    public struct Attempt: Equatable {
        fileprivate let identifier: UUID
        fileprivate let report: DeviceStatusReport
    }

    private enum Outcome {
        case inFlight
        case acknowledged
        case failed
    }

    private var latestAttempt: Attempt?
    private var outcome: Outcome = .failed

    public init() {}

    public func begin(_ report: DeviceStatusReport) -> Attempt? {
        if let latestAttempt, outcome != .failed {
            // Normalize only publication metadata. Synthesized equality keeps
            // every enforcement field (including future fields) significant.
            var previous = latestAttempt.report
            previous.statusVersion = report.statusVersion
            previous.observedAt = report.observedAt
            let heartbeatIsDue = report.observedAt.timeIntervalSince(
                latestAttempt.report.observedAt
            ) >= Double(DeviceStatusReportingPolicy.heartbeatFloorSeconds)
            if previous == report, outcome == .inFlight || !heartbeatIsDue {
                return nil
            }
        }
        let attempt = Attempt(identifier: UUID(), report: report)
        latestAttempt = attempt
        outcome = .inFlight
        return attempt
    }

    public func finish(_ attempt: Attempt, succeeded: Bool) {
        guard latestAttempt?.identifier == attempt.identifier else { return }
        outcome = succeeded ? .acknowledged : .failed
    }

    /// A cancelled HTTP operation has no acknowledgement. Forget its identity
    /// so a late completion cannot suppress the next unchanged heartbeat.
    public func abortInFlight() {
        guard outcome == .inFlight else { return }
        latestAttempt = nil
        outcome = .failed
    }
}
