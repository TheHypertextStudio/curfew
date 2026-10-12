import CurfewKit
import Foundation

@MainActor
final class NativeAccountSyncSocketConnection: AccountSyncSocketConnection {
    private let task: URLSessionWebSocketTask
    let accessToken: String

    init(task: URLSessionWebSocketTask, accessToken: String) {
        self.task = task
        self.accessToken = accessToken
    }

    var closeReason: String? {
        task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
    }

    var failureStatusCode: Int? {
        guard let response = task.response as? HTTPURLResponse,
              response.statusCode >= 400 else { return nil }
        return response.statusCode
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw NativeAccountSyncError.invalidResponse
            }
            return text
        @unknown default: throw NativeAccountSyncError.invalidResponse
        }
    }

    func sendPing() async throws {
        try await task.send(.string("ping"))
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
