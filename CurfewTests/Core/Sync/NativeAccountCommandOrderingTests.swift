@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testFixtureShutdownWaitsForCanceledOwnedOperationToUnwind() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let transport = makeTransport(secrets: fixture.secrets)
        let started = expectation(description: "owned refresh suspended")
        let canceled = expectation(description: "owned refresh cancellation requested")
        var release: CheckedContinuation<Void, Never>?
        transport.tokenRefreshTask = Task<Void, Error> {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    release = continuation
                    started.fulfill()
                }
            } onCancel: {
                canceled.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 1)
        var finished = false
        let shutdown = Task {
            await transport.disconnectAndWaitForPendingOperations()
            finished = true
        }
        await fulfillment(of: [canceled], timeout: 1)
        XCTAssertFalse(finished, "Cancellation alone must not release fixture dependencies")
        release?.resume()
        await shutdown.value
        XCTAssertTrue(finished)
    }

    func testSharedResultRetryUsesAlreadyRotatedCredentials() async throws {
        let fixture = try makeFixture(accessToken: "expired-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true)
        )
        let result = try daemonResult(deviceID: fixture.deviceID)
        try exchange.publish([result])
        let events = NativeTransportEventRecorder()
        let rejected = expectation(description: "old-token result response suspended")
        let fetched = expectation(description: "commands follow retried result receipt")
        installRotatedResultHandler(
            exchange: exchange, result: result, events: events, rejected: rejected, fetched: fetched
        )
        NativeTransportURLProtocol.responseDelay = {
            $0.url?.path == "/sync/remote-control/commands/result" ? 0.1 : 0
        }
        defer {
            NativeTransportURLProtocol.handler = nil
            NativeTransportURLProtocol.responseDelay = nil
        }
        let transport = makeTransport(
            secrets: fixture.secrets,
            inboxStore: RemoteCommandInboxStore(directoryURL: root.appendingPathComponent("inbox")),
            resultExchangeStore: exchange
        )
        connectForOrderingTest(transport, deviceID: fixture.deviceID)
        await fulfillment(of: [rejected], timeout: 3)
        try fixture.secrets.save(Data("fresh-access-token".utf8), for: "oauth-access-token")
        await fulfillment(of: [fetched], timeout: 3)
        await transport.disconnectAndWaitForPendingOperations()
        XCTAssertEqual(events.values, ["expired-result", "fresh-result", "commands-after-receipt"])
    }

    func testScheduledCommandFetchWaitsForSharedResultReceipt() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true)
        )
        let result = try daemonResult(deviceID: fixture.deviceID)
        try exchange.publish([result])
        let events = NativeTransportEventRecorder()
        let fetched = expectation(description: "commands fetched after result receipt")
        NativeTransportURLProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/remote-control/commands/result":
                events.append("result")
                return try (200, CurfewProtocols.SignedRemoteCommandResultReceiptEnvelope(
                    compactJws: Self.syntheticReceiptJWS
                ).jsonData())
            case "/sync/remote-control/commands":
                let receipt = try exchange.pendingReceipt(for: result)
                events.append(receipt == nil ? "commands-before-receipt" : "commands-after-receipt")
                Task { @MainActor in fetched.fulfill() }
                return try Self.pollingResponse(for: request)
            default:
                return try Self.pollingResponse(for: request)
            }
        }
        NativeTransportURLProtocol.responseDelay = {
            $0.url?.path == "/sync/remote-control/commands/result" ? 0.1 : 0
        }
        defer {
            NativeTransportURLProtocol.handler = nil
            NativeTransportURLProtocol.responseDelay = nil
        }
        let transport = makeTransport(
            secrets: fixture.secrets,
            inboxStore: RemoteCommandInboxStore(directoryURL: root.appendingPathComponent("inbox")),
            resultExchangeStore: exchange
        )
        connectForOrderingTest(transport, deviceID: fixture.deviceID)
        await fulfillment(of: [fetched], timeout: 1)
        await transport.disconnectAndWaitForPendingOperations()
        XCTAssertEqual(events.values, ["result", "commands-after-receipt"])
    }

    private func connectForOrderingTest(_ transport: NativeAccountSyncTransport, deviceID: UUID) {
        transport.connect(
            deviceID: deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in }, onOffline: {}, onWakeStatus: { _ in },
                onRemoteOverride: { _ in }, onRemoteCommandResult: { _ in }, onFailure: { _ in }
            )
        )
    }

    private func installRotatedResultHandler(
        exchange: RemoteCommandResultExchangeStore, result: CurfewKit.RemoteCommandResult,
        events: NativeTransportEventRecorder, rejected: XCTestExpectation,
        fetched: XCTestExpectation
    ) {
        NativeTransportURLProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/remote-control/commands/result":
                if request
                    .value(forHTTPHeaderField: "Authorization") == "Bearer expired-access-token" {
                    events.append("expired-result")
                    Task { @MainActor in rejected.fulfill() }
                    return (401, Data())
                }
                events.append("fresh-result")
                return try (200, CurfewProtocols.SignedRemoteCommandResultReceiptEnvelope(
                    compactJws: Self.syntheticReceiptJWS
                ).jsonData())
            case "/sync/remote-control/commands":
                try events.append(exchange.pendingReceipt(for: result) == nil
                    ? "commands-before-receipt" : "commands-after-receipt")
                Task { @MainActor in fetched.fulfill() }
                return try Self.pollingResponse(for: request)
            default: return try Self.pollingResponse(for: request)
            }
        }
    }
}
