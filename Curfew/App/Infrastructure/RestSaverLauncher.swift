import AppKit
import CurfewKit
import Foundation
import ScreenSaver

/// Public-system launcher. It never selects a saver or changes authentication policy.
///
/// For Curfew's own saver it waits for the saver's full-screen receipt and
/// stops the engine it started if none arrives. For the Mac's selected saver,
/// launched only by the person's choice, there is no receipt to wait for and
/// the engine is left to the system. A saver that is already running is never
/// started again or stopped.
@MainActor
final class RestSaverLauncher {
    struct Operations {
        var resolve: () -> URL?
        var requestReadback: () throws -> Void
        var open: (URL) async throws -> Int32
        var hasFullScreenReceipt: () -> Bool
        var isRunning: (Int32) -> Bool
        var stopOwned: (Int32) -> Void
        var waitForReceipt: () async throws -> Void
        var isEngineRunning: () -> Bool = { false }
    }

    private let operations: Operations
    private(set) var ownedProcess: Int32?

    init(operations: Operations) {
        self.operations = operations
    }

    func launch(target: RestSaverChoice.Target = .curfew) async -> RestHandoffPolicy.LaunchResult {
        guard !operations.isEngineRunning() else { return .saverAlreadyRunning }
        guard !Task.isCancelled, let url = operations.resolve() else {
            return .unavailable(.launchUnavailable)
        }
        do {
            if target == .curfew {
                try operations.requestReadback()
            }
            try Task.checkCancellation()
            ownedProcess = try await operations.open(url)
            try Task.checkCancellation()
            if target == .selected {
                return .started
            }
            try await operations.waitForReceipt()
            try Task.checkCancellation()
            guard operations.hasFullScreenReceipt() else {
                stopOwned()
                return .unavailable(.companionUnavailable)
            }
            return .started
        } catch {
            stopOwned()
            return .unavailable(.launchUnavailable)
        }
    }

    /// Whether Curfew's saver has acknowledged a full-screen render.
    var hasFullScreenReceipt: Bool {
        operations.hasFullScreenReceipt()
    }

    func consumeReturn() -> Bool {
        guard hasReturned else { return false }
        ownedProcess = nil
        return true
    }

    func stopOwned() {
        if let ownedProcess {
            operations.stopOwned(ownedProcess)
        }
        ownedProcess = nil
    }

    var hasReturned: Bool {
        guard let ownedProcess else { return false }
        return !operations.isRunning(ownedProcess)
    }
}
