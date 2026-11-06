import Foundation

// MARK: - Cancelling a shutdown that is already in flight

/// Stops a `/sbin/shutdown` that the daemon has already issued.
///
/// Split behind a protocol so the break-glass path is testable without a
/// machine that actually powers off.
public protocol PendingShutdownCanceling: Sendable {
    /// Terminates any pending `shutdown` process. Returns `true` when at least
    /// one was signalled. A no-match exit returns false. Launch failures,
    /// command failures, and signal termination throw.
    @discardableResult
    func cancelPendingShutdown() throws -> Bool
}

/// Production canceller. `/sbin/shutdown -h +1` has no cancel flag on macOS,
/// so the only way back is to kill the waiting process — which needs root,
/// hence the `sudo curfew-ctl break-glass` form in the runbook.
public struct SystemShutdownCanceller: PendingShutdownCanceling {
    enum CommandResult: Sendable {
        case exited(Int32)
        case signalled(Int32)
    }

    private let runCommand: @Sendable () throws -> CommandResult

    public init() {
        self.runCommand = { try Self.runSystemCommand() }
    }

    init(runCommand: @escaping @Sendable () throws -> CommandResult) {
        self.runCommand = runCommand
    }

    @discardableResult
    public func cancelPendingShutdown() throws -> Bool {
        switch try runCommand() {
        case .exited(0):
            return true
        case .exited(1):
            return false
        case .exited(let status):
            throw ShutdownCancellationError.commandFailed(status: status)
        case .signalled(let signal):
            throw ShutdownCancellationError.commandTerminated(signal: signal)
        }
    }

    private static func runSystemCommand() throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", "shutdown"]
        try process.run()
        process.waitUntilExit()
        return process.terminationReason == .exit
            ? .exited(process.terminationStatus)
            : .signalled(process.terminationStatus)
    }
}

public enum ShutdownCancellationError: LocalizedError, Equatable {
    case commandFailed(status: Int32)
    case commandTerminated(signal: Int32)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let status):
            "Could not cancel a pending shutdown: /usr/bin/pkill exited with status \(status)."
        case .commandTerminated(let signal):
            "Could not cancel a pending shutdown: /usr/bin/pkill was terminated by signal \(signal)."
        }
    }
}
