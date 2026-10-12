@testable import CurfewKit
import Testing

struct AccountSyncSocketLifecycleTests {
    @Test("A silent socket closes even when hints keep arriving")
    func halfOpenDeadline() {
        var socket = AccountSyncSocketLifecycle()
        #expect(socket.action(at: .zero) == .connect)
        socket.opened(at: .zero)
        #expect(socket.action(at: .zero) == .ping)
        #expect(socket.action(at: .seconds(30)) == .ping)
        #expect(socket.action(at: .seconds(75)) == .close)
        #expect(socket.action(at: .seconds(89)) == nil)
        #expect(socket.action(at: .seconds(90)) == .connect)
    }

    @Test("Pongs maintain liveness without treating socket opening as healthy recovery")
    func healthyPongsResetBackoff() {
        var socket = AccountSyncSocketLifecycle()
        _ = socket.action(at: .zero)
        socket.failed(at: .zero)
        #expect(socket.action(at: .seconds(15)) == .connect)
        socket.opened(at: .seconds(15))
        socket.receivedPong(at: .seconds(45))
        socket.failed(at: .seconds(46))
        #expect(socket.action(at: .seconds(75)) == nil)
        #expect(socket.action(at: .seconds(76)) == .connect)
        socket.opened(at: .seconds(76))
        socket.receivedPong(at: .seconds(106))
        socket.receivedPong(at: .seconds(136))
        socket.failed(at: .seconds(137))
        #expect(socket.action(at: .seconds(152)) == .connect)
    }

    @Test("A failed handshake cannot hang the reconnect loop indefinitely")
    func handshakeDeadline() {
        var socket = AccountSyncSocketLifecycle()
        _ = socket.action(at: .zero)
        #expect(socket.action(at: .seconds(30)) == .close)
        #expect(socket.action(at: .seconds(45)) == .connect)
    }

    @Test("Terminal revocation never reconnects without an explicit restart")
    func terminalFailure() {
        var socket = AccountSyncSocketLifecycle()
        _ = socket.action(at: .zero)
        socket.failed(at: .seconds(1), terminal: true)
        #expect(socket.action(at: .seconds(86400)) == nil)
    }
}
