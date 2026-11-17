import Foundation

/// What the lock preview shows. Plain values: the preview never reads or
/// writes enforcement state, so it cannot arm anything or record anything.
struct LockPreviewContent: Equatable {
    let curfew: Date
    let unlock: Date
}

@MainActor
protocol LockPreviewPresenting: AnyObject {
    /// Shows the preview. `onEnd` is the preview's own way out (its button,
    /// Escape, or a click).
    func show(_ content: LockPreviewContent, onEnd: @escaping () -> Void)
    func hide()
}

/// A short, timed look at the lock from setup step 3. It always ends: after
/// `duration`, or at once when the person ends it.
@MainActor
final class LockPreviewController {
    static let defaultDuration: Duration = .seconds(8)

    private let presenter: any LockPreviewPresenting
    private let duration: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var timeout: Task<Void, Never>?

    private(set) var isPresenting = false

    init(
        presenter: any LockPreviewPresenting,
        duration: Duration = LockPreviewController.defaultDuration,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.presenter = presenter
        self.duration = duration
        self.sleep = sleep
    }

    func present(_ content: LockPreviewContent) {
        dismiss()
        isPresenting = true
        presenter.show(content) { [weak self] in self?.dismiss() }
        let duration = duration
        let sleep = sleep
        timeout = Task { [weak self] in
            await sleep(duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        guard isPresenting else { return }
        isPresenting = false
        presenter.hide()
        // Cancelling only stops a pending sleep; it is harmless when the
        // timed end is the caller.
        timeout?.cancel()
        timeout = nil
    }

    /// Test seam: waits for the timed end.
    func waitUntilEnded() async {
        await timeout?.value
    }
}
