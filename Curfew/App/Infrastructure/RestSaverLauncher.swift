import AppKit
import CurfewKit
import Foundation
import ScreenSaver

/// Public-system launcher. It never selects a saver or changes authentication policy.
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
    }

    private let operations: Operations
    private(set) var ownedProcess: Int32?

    init(operations: Operations) {
        self.operations = operations
    }

    func launch() async -> RestHandoffPolicy.LaunchResult {
        guard !Task.isCancelled, let url = operations.resolve() else {
            return .unavailable(.launchUnavailable)
        }
        do {
            try operations.requestReadback()
            try Task.checkCancellation()
            ownedProcess = try await operations.open(url)
            try Task.checkCancellation()
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
