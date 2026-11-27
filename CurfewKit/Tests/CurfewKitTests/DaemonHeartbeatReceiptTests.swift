import CurfewKit
import Foundation
import Testing

struct DaemonHeartbeatReceiptTests {
    @Test func repeatedTimestampHeartbeatRestartsItsFullGrace() async throws {
        try await checkFreshReceipt(rearm: false)
    }

    @Test func repeatedTimestampArmRestartsItsFullGrace() async throws {
        try await checkFreshReceipt(rearm: true)
    }

    @Test func rejectedHeartbeatCannotRestartGrace() async throws {
        try await checkRejectedReceipt(failPersistence: false)
    }

    @Test func uncommittedHeartbeatCannotRestartGrace() async throws {
        try await checkRejectedReceipt(failPersistence: true)
    }

    private func checkFreshReceipt(rearm: Bool) async throws {
        let fixture = try ReceiptFixture()
        defer { fixture.cleanup() }
        try await fixture.arm()
        fixture.clock.set(fixture.start.addingTimeInterval(80))
        _ = await fixture.service.evaluateNow()
        #expect(fixture.observedAge.read() == 80)

        fixture.clock.set(fixture.start)
        let error = rearm ? await fixture.armError() : await fixture.heartbeatError()
        #expect(error == nil)
        try #require(fixture.observedAge.read() == 0)
        fixture.clock.set(fixture.start.addingTimeInterval(90))
        _ = await fixture.service.evaluateNow()
        #expect(fixture.observedAge.read() == 90)
        fixture.clock.set(fixture.start.addingTimeInterval(91))
        _ = await fixture.service.evaluateNow()
        #expect(fixture.observedAge.read() == 91)
    }

    private func checkRejectedReceipt(failPersistence: Bool) async throws {
        let fixture = try ReceiptFixture()
        defer { fixture.cleanup() }
        try await fixture.arm()
        fixture.clock.set(fixture.start.addingTimeInterval(80))
        _ = await fixture.service.evaluateNow()
        #expect(fixture.observedAge.read() == 80)
        if failPersistence {
            try FileManager.default.removeItem(at: fixture.stateURL)
            try FileManager.default.createDirectory(
                at: fixture.stateURL, withIntermediateDirectories: true
            )
        }
        fixture.clock.set(fixture.start)
        let error = await fixture.heartbeatError(
            lockoutID: failPersistence ? fixture.record.lockoutID : UUID()
        )
        #expect(error != nil)
        _ = await fixture.service.evaluateNow()
        #expect(fixture.observedAge.read() == 80)
        fixture.clock.set(fixture.start.addingTimeInterval(11))
        _ = await fixture.service.evaluateNow()
        #expect(fixture.observedAge.read() == 91)
    }
}

private final class ReceiptFixture {
    let start: Date
    let directory: URL
    let stateURL: URL
    let record: LockoutDeadlineRecord
    let clock: LockedReceiptValue<Date>
    let observedAge: LockedReceiptValue<TimeInterval>
    let service: AuthenticatedDaemonService

    init() throws {
        let start = Date(timeIntervalSince1970: 10000)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("state.json")
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: start, scheduledUnlockAt: start.addingTimeInterval(3600),
            kind: .scheduledTime
        )
        let clock = LockedReceiptValue(start)
        let age = LockedReceiptValue<TimeInterval>(-.infinity)
        self.start = start
        self.observedAge = age
        self.directory = directory
        self.stateURL = stateURL
        self.record = record
        self.clock = clock
        self.service = AuthenticatedDaemonService(
            store: PrivilegedDaemonStateStore(stateURL: stateURL),
            readExternal: { _, _ in nil },
            evaluate: { _, _, _, authenticatedAge in
                age.set(authenticatedAge)
                return false
            },
            discover: {}, clock: { clock.read() }
        )
    }

    func arm() async throws {
        let error = await armError()
        try #require(error == nil)
    }

    func armError() async -> NSError? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let request: Data
        do { request = try encoder.encode(record) } catch { return error as NSError }
        return await withCheckedContinuation { continuation in
            service.armLockout(request) { _, error in continuation.resume(returning: error) }
        }
    }

    func heartbeatError(lockoutID: UUID? = nil) async -> NSError? {
        let request: Data
        do {
            request = try JSONEncoder().encode(PrivilegedHeartbeatRequest(
                lockoutID: lockoutID ?? record.lockoutID
            ))
        } catch { return error as NSError }
        return await withCheckedContinuation { continuation in
            service.heartbeat(request) { _, error in continuation.resume(returning: error) }
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Test clock and output collection only; no heartbeat or grace logic is substituted.
private final class LockedReceiptValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}
