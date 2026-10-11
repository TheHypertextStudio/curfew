import CurfewKit
import Foundation
import OSLog

private let monitorLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "mcp-request-monitor"
)

/// Watches the MCP request queue file for new pending entries and surfaces
/// them to the app model for user approval.
///
/// Uses a `DispatchSourceFileSystemObject` to watch the queue file's parent
/// directory for write events — more efficient than polling, and avoids the
/// latency of a timer-based approach. The monitor creates the app-support
/// directory before opening the file descriptor so first launch follows the
/// same event-driven path as subsequent launches.
///
/// The monitor must be started by calling ``start()`` and torn down by
/// calling ``stop()`` or letting it deinit. Only one monitor instance should
/// exist per process.
@MainActor
final class MCPRequestMonitor {
    /// Called on the main actor whenever a new pending request arrives.
    /// The app model hooks this to display the consent sheet.
    var onNewRequests: (([MCPPendingRequest]) -> Void)?

    /// Whether ``start()`` has been called without a matching ``stop()``.
    /// Read by gating tests to assert the runtime tracks the feature flag +
    /// user setting; flips on ``start()`` and back off on ``stop()``
    /// regardless of whether the underlying file watch was installed (it is
    /// skipped in the unit-test host to avoid filesystem side effects).
    private(set) var isStarted = false

    private var dispatchSource: DispatchSourceFileSystemObject?

    /// The last set of request IDs we notified about. Used to avoid
    /// re-surfacing the same consent sheet if nothing changed between reads.
    private var notifiedIDs: Set<UUID> = []

    /// Designated initialiser. Marked `nonisolated` so it can be used as a
    /// default argument value in `CurfewAppModel.init`, which is evaluated
    /// before the `@MainActor` isolation is established.
    nonisolated init() {}

    deinit {
        dispatchSource?.cancel()
    }

    /// Starts monitoring. Idempotent — safe to call more than once.
    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        // Skip the real directory watch in the unit-test host: opening an
        // `O_EVTONLY` descriptor on `~/Library/Application Support/Curfew`
        // and scheduling a poll timer are filesystem side effects we do not
        // want fired during `xcodebuild test`. `isStarted` still flips so
        // gating tests can assert the flag + setting drove the start.
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        setupWatch()
        check()
    }

    /// Stops monitoring and releases the file watch descriptor.
    func stop() {
        isStarted = false
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    // MARK: - Private

    private func setupWatch() {
        let directoryURL = SharedPaths.applicationSupport
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            monitorLogger
                .error("Could not create mcp queue directory: \(error.localizedDescription)")
            return
        }

        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            monitorLogger.error("Could not open mcp queue directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.check()
            }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        dispatchSource = source
    }

    /// Reads the queue file and fires `onNewRequests` for any pending entries
    /// the monitor hasn't already surfaced.
    private func check() {
        let all = MCPRequestQueue.load()
        let pending = all.filter { $0.status == .pending }
        let newPending = pending.filter { !notifiedIDs.contains($0.id) }

        guard !newPending.isEmpty else {
            return
        }

        monitorLogger.info("new MCP requests: \(newPending.count)")
        notifiedIDs.formUnion(newPending.map(\.id))
        onNewRequests?(newPending)
    }
}
