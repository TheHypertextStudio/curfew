import AppKit
import Foundation

/// Abstracts the "ask everyone to quit, then shut down the Mac" pair of
/// operations so tests can drive `ShutdownWorkflow` without actually telling
/// the OS to power off. Production uses `SystemShutdownController`.
protocol ShutdownControlling: AnyObject {
    /// Sends a graceful-terminate request to every running app except Curfew
    /// itself. Apps receive the standard AppKit "unsaved changes?" flow and
    /// may veto termination — that's fine; we retry with `executeShutdown`.
    func requestGracefulTermination()

    /// Tells macOS to shut down. Returns `true` iff the AppleScript
    /// invocation succeeded. The system may still block shutdown for reasons
    /// unrelated to Curfew (e.g. user-level "are you sure?" dialogs) so this
    /// value is advisory, not authoritative.
    func executeShutdown() -> Bool
}

/// Production `ShutdownControlling` that wraps `NSWorkspace` and
/// `NSAppleScript`. Kept as a thin concrete shim so the meaningful logic
/// lives in `ShutdownWorkflow` and is unit-testable.
final class SystemShutdownController: ShutdownControlling {
    /// Terminates every running app except Curfew, giving them the standard
    /// "save changes?" opportunity first.
    func requestGracefulTermination() {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier != ownBundleIdentifier
        }
        for application in applications {
            _ = application.terminate()
        }
    }

    /// Executes the system-shutdown AppleScript. The script requires the
    /// `com.apple.security.automation.apple-events` entitlement plus user
    /// approval for System Events scripting — without either, `error` will
    /// be populated and we return `false`.
    func executeShutdown() -> Bool {
        guard let script = NSAppleScript(source: "tell application \"System Events\" to shut down")
        else {
            return false
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }
}

/// Small state machine that drives the optional auto-shutdown sequence after
/// curfew lockout begins.
///
/// Flow:
/// 1. Lockout starts → move to `.scheduled(date:)` with `date = now + delay`.
/// 2. On later ticks, once `now >= date`, request graceful termination and
///    attempt shutdown.
///    - Success → `.completed`.
///    - Failure → `.retryScheduled(date: now + 60)` and retry once.
/// 3. Retry fails → `.failed`. Lockout remains active (caller is responsible
///    for keeping the screen locked regardless of shutdown outcome).
///
/// If lockout ends, auto-shutdown is disabled, or the workflow already
/// completed, the machine resets to `.idle`. The state is intentionally
/// value-typed and `Equatable` so callers can diff snapshots cheaply and
/// tests can compare expected phases directly.
struct ShutdownWorkflow: Equatable {
    /// Current position in the shutdown sequence.
    enum Phase: Equatable {
        /// Either not in lockout yet, or auto-shutdown disabled.
        case idle
        /// First shutdown attempt queued for the given fire date.
        case scheduled(date: Date)
        /// Second (retry) attempt queued for the given fire date.
        case retryScheduled(date: Date)
        /// Both attempts failed; lockout must stay active by other means.
        case failed
        /// Shutdown command was dispatched successfully.
        case completed
    }

    /// Externally read-only view of the workflow's current state. Mutated
    /// only by `update(now:isLocked:isEnabled:delayMinutes:controller:)`.
    private(set) var phase: Phase = .idle

    /// Advances the workflow given the current moment and enforcement state.
    ///
    /// - Parameters:
    ///   - now: current clock time; `.scheduled`/`.retryScheduled` fire when
    ///     `now >= phase.date`.
    ///   - isLocked: whether the schedule engine is currently in `.locked`
    ///     phase. Transitions back to `.idle` if lockout ends.
    ///   - isEnabled: user's auto-shutdown setting.
    ///   - delayMinutes: how long to wait after lockout begins before the
    ///     first shutdown attempt. Clamped to a minimum of 1 minute.
    ///   - controller: injection point for graceful-terminate + shutdown.
    mutating func update(
        now: Date,
        isLocked: Bool,
        isEnabled: Bool,
        delayMinutes: Int,
        controller: ShutdownControlling,
        isActiveDevice: Bool = true
    ) {
        guard isLocked, isEnabled else {
            phase = .idle
            return
        }

        switch phase {
        case .idle:
            // Active device follows the configured delay so the user has
            // time to save. Idle devices get a shorter default — 2 min —
            // since the user isn't there and the delay's only purpose is
            // a graceful app termination grace period, not user save-time.
            let delay = isActiveDevice ? max(1, delayMinutes) : 2
            phase = .scheduled(date: now.addingTimeInterval(TimeInterval(delay * 60)))
        case .scheduled(let date):
            guard now >= date else {
                return
            }
            controller.requestGracefulTermination()
            if controller.executeShutdown() {
                phase = .completed
            } else {
                phase = .retryScheduled(date: now.addingTimeInterval(60))
            }
        case .retryScheduled(let date):
            guard now >= date else {
                return
            }
            controller.requestGracefulTermination()
            if controller.executeShutdown() {
                phase = .completed
            } else {
                phase = .failed
            }
        case .failed, .completed:
            return
        }
    }

    /// Human-readable one-liner describing the shutdown state, or `nil` when
    /// there is nothing to tell the user (idle / completed cleanly).
    ///
    /// The model publishes this text so the lockout screen can render a
    /// countdown ("Your Mac is going to sleep in 9:45.") without having to
    /// know about workflow internals.
    func statusLine(now: Date) -> String? {
        switch phase {
        case .scheduled(let date):
            let remaining = max(0, Int(date.timeIntervalSince(now)))
            return "Your Mac is going to sleep in \(ShutdownWorkflow.format(seconds: remaining))."
        case .retryScheduled(let date):
            let remaining = max(0, Int(date.timeIntervalSince(now)))
            return "Retrying shutdown in \(ShutdownWorkflow.format(seconds: remaining))."
        case .failed:
            return "Shutdown failed. Lockout remains active."
        case .completed, .idle:
            return nil
        }
    }

    /// Formats seconds as `M:SS` with a zero-padded second component.
    private static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let secondComponent = seconds % 60
        return String(format: "%d:%02d", minutes, secondComponent)
    }
}
