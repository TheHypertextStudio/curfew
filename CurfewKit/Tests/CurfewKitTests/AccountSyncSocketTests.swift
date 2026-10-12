@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct AccountSyncSocketTests {
    @Test("Actual consumer keeps handshake deadline until its first pong")
    func silentHandshakeCloses() async {
        let connection = SocketBoundary()
        var time = Duration.zero
        let socket = AccountSyncSocket(
            open: { connection }, onHint: {}, onFailure: { _, _, _, _ in true }, elapsed: { time }
        )
        socket.tick()
        await connection.waitForReceive()
        time = .seconds(30)
        socket.tick()
        #expect(connection.closed == 1)
        socket.stop()
    }

    @Test("Receive loop separates pongs from state hints and reports terminal closure once")
    func hintsAndRevocation() async {
        let connection = SocketBoundary()
        var hints = 0
        var failures = 0
        var time = Duration.zero
        let socket = AccountSyncSocket(
            open: { connection },
            onHint: { hints += 1 },
            onFailure: { _, reason, token, status in
                #expect(reason == "device_revoked")
                #expect(token == "test-access")
                #expect(status == nil)
                failures += 1
                return false
            },
            elapsed: { time }
        )
        socket.tick()
        await connection.waitForReceive()
        connection.deliver("pong")
        await connection.waitForReceive()
        #expect(hints == 0)
        connection.deliver("{\"type\":\"state_changed\"}")
        await connection.waitForReceive()
        #expect(hints == 1)
        connection.closeReason = "device_revoked"
        connection.reject()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(failures == 1)
        time = .seconds(86400)
        socket.tick()
        #expect(connection.receives == 3)
        socket.stop()
    }

    @Test("Stopping while the factory is suspended closes its late connection")
    func lateOpenIsClosed() async {
        let connection = SocketBoundary()
        var resume: CheckedContinuation<Void, Never>?
        let socket = AccountSyncSocket(
            open: {
                await withCheckedContinuation { resume = $0 }
                return connection
            },
            onHint: {}, onFailure: { _, _, _, _ in true }
        )
        socket.tick()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        socket.stop()
        resume?.resume()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(connection.closed == 1)
        #expect(connection.receives == 0)
    }
}

@MainActor
private final class SocketBoundary: AccountSyncSocketConnection {
    let accessToken = "test-access"
    var closeReason: String?
    var failureStatusCode: Int?
    var receives = 0
    var closed = 0
    private var receiver: CheckedContinuation<String, Error>?
    private var waiting: CheckedContinuation<Void, Never>?

    func receive() async throws -> String {
        receives += 1
        return try await withCheckedThrowingContinuation {
            receiver = $0
            waiting?.resume()
            waiting = nil
        }
    }

    func waitForReceive() async {
        if receiver != nil {
            return
        }
        await withCheckedContinuation { waiting = $0 }
    }

    func deliver(_ text: String) {
        let pending = receiver
        receiver = nil
        pending?.resume(returning: text)
    }

    func reject() {
        let pending = receiver
        receiver = nil
        pending?.resume(throwing: URLError(.networkConnectionLost))
    }

    func sendPing() async throws {}

    func close() {
        closed += 1
        reject()
    }
}
