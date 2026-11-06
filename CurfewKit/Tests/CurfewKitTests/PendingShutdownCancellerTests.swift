@testable import CurfewKit
import Foundation
import Testing

struct PendingShutdownCancellerTests {
    @Test("A successful signal reports cancellation")
    func signalledProcess() throws {
        let canceller = SystemShutdownCanceller(runCommand: { .exited(0) })
        #expect(try canceller.cancelPendingShutdown())
    }

    @Test("Only a no-match exit reports no pending shutdown")
    func noMatch() throws {
        let canceller = SystemShutdownCanceller(runCommand: { .exited(1) })
        #expect(try !canceller.cancelPendingShutdown())
    }

    @Test("A command error cannot masquerade as no pending shutdown")
    func commandFailure() {
        let canceller = SystemShutdownCanceller(runCommand: { .exited(2) })
        #expect(throws: (any Error).self) { try canceller.cancelPendingShutdown() }
    }

    @Test("An executable launch error reaches the caller")
    func launchFailure() {
        let canceller =
            SystemShutdownCanceller(runCommand: { throw CocoaError(.executableNotLoadable) })
        #expect(throws: (any Error).self) { try canceller.cancelPendingShutdown() }
    }

    @Test("Termination by signal cannot masquerade as a no-match exit")
    func signalFailure() {
        let canceller = SystemShutdownCanceller(runCommand: { .signalled(1) })
        #expect(throws: (any Error).self) { try canceller.cancelPendingShutdown() }
    }
}
