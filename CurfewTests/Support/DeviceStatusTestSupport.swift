@testable import Curfew
import Foundation

/// A transport that answers from a script and remembers everything it was
/// handed. Opens no socket, so every suite using it is deterministic and
/// runs with the network down.
///
/// A `final class` behind a lock rather than an actor, because the reporter
/// hands work to it from a `Task` and the assertions read it from the test's
/// main-actor body; a lock keeps both sides simple without making the test
/// await the recorder as well as the reporter.
final class RecordingStatusTransport: DeviceStatusTransporting, @unchecked Sendable {
    /// One publish, as the transport saw it.
    struct Call: Equatable {
        let body: Data
        let endpoint: URL
        let bearerToken: String
    }

    private let lock = NSLock()
    private var storedCalls: [Call] = []
    private let outcome: DeviceStatusPublishOutcome

    /// Creates a transport that answers every publish with `outcome`.
    init(outcome: DeviceStatusPublishOutcome = .accepted) {
        self.outcome = outcome
    }

    /// Every publish so far, oldest first.
    var calls: [Call] {
        lock.withLock { storedCalls }
    }

    /// The `statusVersion` of every publish so far, in the order they were made.
    /// The ordering guarantee is what most of these suites are actually about.
    var publishedVersions: [Int] {
        calls.compactMap { call in
            let json = try? JSONSerialization.jsonObject(with: call.body) as? [String: Any]
            return json?["statusVersion"] as? Int
        }
    }

    /// The decoded body of the publish at `index`, or `nil` if there is none.
    func decodedBody(at index: Int) -> [String: Any]? {
        let calls = calls
        guard calls.indices.contains(index) else { return nil }
        return try? JSONSerialization.jsonObject(with: calls[index].body) as? [String: Any]
    }

    func publish(
        _ body: Data,
        to endpoint: URL,
        bearerToken: String
    ) async -> DeviceStatusPublishOutcome {
        lock.withLock {
            storedCalls.append(Call(body: body, endpoint: endpoint, bearerToken: bearerToken))
        }
        return outcome
    }
}

/// A transport that never answers until it is released, so a suite can hold a
/// publish open and observe what the reporter does with the reports arriving
/// behind it.
final class BlockingStatusTransport: DeviceStatusTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [RecordingStatusTransport.Call] = []
    private let gate = AsyncGate()

    /// Every publish so far, oldest first.
    var calls: [RecordingStatusTransport.Call] {
        lock.withLock { storedCalls }
    }

    /// The `statusVersion` of every publish so far, in order.
    var publishedVersions: [Int] {
        calls.compactMap { call in
            let json = try? JSONSerialization.jsonObject(with: call.body) as? [String: Any]
            return json?["statusVersion"] as? Int
        }
    }

    /// Lets every waiting and future publish complete.
    func release() {
        gate.open()
    }

    func publish(
        _ body: Data,
        to endpoint: URL,
        bearerToken: String
    ) async -> DeviceStatusPublishOutcome {
        lock.withLock {
            storedCalls.append(
                RecordingStatusTransport.Call(
                    body: body,
                    endpoint: endpoint,
                    bearerToken: bearerToken
                )
            )
        }
        await gate.wait()
        return .accepted
    }
}

/// Lets the reporter's detached publish task get a turn on the main actor.
///
/// Needed because `DeviceStatusReporter.report(...)` is deliberately
/// fire-and-forget: it creates a `Task` and returns without awaiting it, so a
/// test that calls it and immediately reads the transport sees nothing at all.
/// That is the property under test, not a flaw — but it means a suite watching a
/// transport that never answers (where `settle()` would wait forever) has to
/// yield by hand instead.
@MainActor
func pumpMainActor(_ turns: Int = 20) async {
    for _ in 0 ..< turns {
        await Task.yield()
    }
}

/// A one-shot latch: everything waiting resumes when it opens, and anything
/// arriving afterwards passes straight through.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        let resuming: [CheckedContinuation<Void, Never>] = lock.withLock {
            isOpen = true
            let waiting = waiters
            waiters = []
            return waiting
        }
        resuming.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeNow: Bool = lock.withLock {
                if isOpen {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResumeNow {
                continuation.resume()
            }
        }
    }
}
