/// Socket transport liveness only; neither hints nor pongs acknowledge sync state.
public struct AccountSyncSocketLifecycle {
    public enum Action: Equatable { case connect, ping, close }
    private enum State { case waiting, connecting, open, terminal }
    private var state: State = .waiting
    private var nextConnect: Duration = .zero
    private var openedAt: Duration = .zero
    private var lastPong: Duration = .zero
    private var nextPing: Duration = .zero
    private var failures = 0
    private let retryJitter: Duration
    public init(retryJitter: Duration = .zero) {
        self.retryJitter = max(.zero, min(.seconds(5), retryJitter))
    }

    public mutating func action(at time: Duration) -> Action? {
        switch state {
        case .terminal: return nil
        case .waiting:
            guard time >= nextConnect else { return nil }
            state = .connecting
            openedAt = time
            return .connect
        case .connecting:
            guard time - openedAt >= .seconds(30) else { return nil }
            failed(at: time)
            return .close
        case .open:
            if time - lastPong >= .seconds(75) {
                failed(at: time)
                return .close
            }
            guard time >= nextPing else { return nil }
            nextPing = time + .seconds(30)
            return .ping
        }
    }

    public mutating func opened(at time: Duration) {
        guard state == .connecting else { return }
        state = .open
        openedAt = time
        lastPong = time
        nextPing = time
    }

    public mutating func receivedPong(at time: Duration) {
        guard state == .open else { return }
        lastPong = time
        if time - openedAt >= .seconds(60) {
            failures = 0
        }
    }

    public mutating func failed(at time: Duration, terminal: Bool = false) {
        guard state != .terminal else { return }
        if terminal {
            state = .terminal
            return
        }
        state = .waiting
        failures = min(failures + 1, 6)
        nextConnect = time + min(.seconds(300), .seconds(15 * (1 << (failures - 1))) + retryJitter)
    }
}
