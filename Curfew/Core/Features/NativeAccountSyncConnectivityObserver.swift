import AppKit
import Network

/// Lifecycle signals only. It never opens windows or treats network reachability as sync success.
@MainActor
final class NativeAccountSyncConnectivityObserver {
    private let center = NSWorkspace.shared.notificationCenter
    private let monitor = NWPathMonitor()
    private var wakeObserver: NSObjectProtocol?
    private var wasSatisfied: Bool?
    private let onRestored: () -> Void

    init(onRestored: @escaping () -> Void) {
        self.onRestored = onRestored
        self.wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onRestored() }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in self?.pathChanged(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "studio.hypertext.curfew.account-connectivity"))
    }

    func stop() {
        monitor.cancel()
        if let wakeObserver {
            center.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    private func pathChanged(satisfied: Bool) {
        let restored = wasSatisfied == false && satisfied
        wasSatisfied = satisfied
        if restored {
            onRestored()
        }
    }

    deinit {
        monitor.cancel()
        if let wakeObserver {
            center.removeObserver(wakeObserver)
        }
    }
}
