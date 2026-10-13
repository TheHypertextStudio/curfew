import Foundation

/// Serializes helper replacement without letting command producers outrun admission
/// or mistake launchd registration for an authenticated helper connection.
@MainActor
public final class DaemonRegistrationRepair {
    public enum State: Equatable, Sendable { case idle, repairing, ready, failed }
    public enum RepairError: Error { case alreadyRepairing }
    public typealias Step = @MainActor () async throws -> Void
    public private(set) var state: State = .idle

    public init() {}

    public func run(
        quiesce: Step, admit: Step, unregister: Step, register: Step,
        verify: Step, resume: @MainActor () -> Void
    ) async throws {
        guard state != .repairing else { throw RepairError.alreadyRepairing }
        state = .repairing
        do {
            try await quiesce()
            try Task.checkCancellation()
            try await admit()
            try Task.checkCancellation()
            try await unregister()
            // Once removal has happened, attempt replacement even if the caller
            // cancelled meanwhile. Never activate producers for a cancelled run.
            try await register()
            try Task.checkCancellation()
            try await verify()
            try Task.checkCancellation()
            // An atomic MainActor commit cannot partially resume then throw.
            resume()
            state = .ready
        } catch {
            state = .failed
            // Never resume producers after incomplete replacement or failed
            // authentication. The caller retains enrollment and durable state.
            throw error
        }
    }
}
