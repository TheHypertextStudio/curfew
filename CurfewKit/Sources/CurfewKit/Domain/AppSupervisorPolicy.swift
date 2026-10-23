import Foundation

/// Decides process recovery independently of windows, launchd, or AppKit.
public struct AppSupervisorPolicy {
    private var launchInFlight = false
    private var retryDelay: TimeInterval = 5
    private var nextLaunchAt: Date?
    private var healthySince: Date?

    public init() {}

    public mutating func shouldLaunch(at now: Date, appIsRunning: Bool) -> Bool {
        if appIsRunning {
            if healthySince == nil {
                healthySince = now
            }
            if let healthySince, now.timeIntervalSince(healthySince) >= 60 {
                retryDelay = 5
                nextLaunchAt = nil
            }
            return false
        }
        healthySince = nil
        guard !launchInFlight, nextLaunchAt.map({ now >= $0 }) ?? true else { return false }
        launchInFlight = true
        nextLaunchAt = now.addingTimeInterval(retryDelay)
        retryDelay = min(60, retryDelay * 2)
        return true
    }

    /// The adapter also calls this after a bounded launch-callback timeout.
    public mutating func launchCompleted(at _: Date) {
        launchInFlight = false
    }
}
