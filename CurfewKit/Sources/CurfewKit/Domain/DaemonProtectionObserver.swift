import Foundation

/// Reads one console user's protection files together with the live work observer.
public struct DaemonProtectionObserver {
    /// Protection facts consumed by one daemon policy evaluation.
    public struct Observation {
        public let breakGlass: BreakGlassRelease?
        public let hasProtectedWork: Bool
        public let liveSummary: String
    }

    private let applicationSupport: () -> URL
    private let live: LiveProtectedWorkMonitor

    public init(
        applicationSupport: @escaping () -> URL = { SharedPaths.applicationSupport },
        live: LiveProtectedWorkMonitor = .system
    ) {
        self.applicationSupport = applicationSupport
        self.live = live
    }

    public func observe(
        now: Date,
        deadline: LockoutDeadlineRecord?,
        policy: ProtectedWorkPolicy
    ) -> Observation {
        let directory = applicationSupport()
        let secret = directory.appendingPathComponent(".break-glass-secret")
        let local = BreakGlassStore(
            recordURL: directory.appendingPathComponent("break-glass.json"),
            secretURL: secret
        )
        let remote = BreakGlassStore(
            recordURL: directory.appendingPathComponent("remote-override-release.json"),
            secretURL: secret
        )
        let release = deadline.flatMap {
            local.activeRelease(now: now, issuedAfter: $0.lockoutStartedAt) ?? remote
                .activeCoordinatorRelease(now: now)
        }
        let liveWork = live.observe(policy: policy)
        let claims = ProtectedWorkStore(recordURL: directory
            .appendingPathComponent("protected-work.json"))
        return Observation(
            breakGlass: release,
            hasProtectedWork: claims.hasActiveWork(now: now) || liveWork.isActive,
            liveSummary: liveWork.summary
        )
    }
}
