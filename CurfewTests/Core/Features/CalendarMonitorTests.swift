@testable import Curfew
import CurfewKit
import EventKit
import Foundation
import Testing

@MainActor
struct CalendarMonitorTests {
    @Test("Revocation during a fetch discards the returned meetings")
    func revokedDuringFetchDiscardsEvents() {
        let source = CalendarSourceFake(status: .fullAccess)
        source.onRead = { source.authorizationStatus = .denied }
        let monitor = CalendarMonitor(source: source)
        defer { monitor.stop() }
        monitor.requestAccessAndSync()
        #expect(source.readCount == 1)
        #expect(monitor.authorizationStatus == .denied)
        #expect(monitor.todayEvents.isEmpty)
        #expect(!monitor.hasCurrentEvent)
        #expect(monitor.nextEvent == nil)
    }

    @Test("An old permission reply cannot change a restarted monitoring session")
    func oldReplyCannotResumeRestartedSession() async throws {
        let source = CalendarSourceFake(status: .notDetermined)
        let monitor = CalendarMonitor(source: source)
        defer { monitor.stop() }
        monitor.requestAccessAndSync()
        await source.waitUntilRequested()
        let oldReply = try #require(source.pendingReply)
        monitor.stop()
        monitor.requestAccessAndSync()
        await source.waitUntilRequested(count: 2)
        let newReply = try #require(source.pendingReply)
        source.authorizationStatus = .fullAccess
        oldReply.resume(returning: true)
        await source.waitUntilReplyReturned()
        #expect(source.readCount == 0)
        #expect(monitor.todayEvents.isEmpty)
        newReply.resume(returning: true)
        await source.waitUntilReplyReturned(count: 2)
        #expect(source.readCount == 1)
        #expect(monitor.todayEvents.count == 2)
    }

    @Test("Write-only access never permits calendar reads")
    func writeOnlyDoesNotReadEvents() {
        let source = CalendarSourceFake(status: .writeOnly)
        let monitor = CalendarMonitor(source: source)
        defer { monitor.stop() }
        monitor.requestAccessAndSync()
        #expect(source.readCount == 0)
        #expect(monitor.authorizationStatus == .writeOnly)
    }

    @Test("Revocation clears cached meetings and blocks the next read")
    func revokedAccessClearsEvents() {
        let source = CalendarSourceFake(status: .fullAccess)
        let monitor = CalendarMonitor(source: source)
        defer { monitor.stop() }
        monitor.requestAccessAndSync()
        #expect(monitor.todayEvents.count == 2)
        #expect(monitor.hasCurrentEvent)
        #expect(monitor.nextEvent != nil)
        source.authorizationStatus = .denied
        let reads = source.readCount
        monitor.sync()
        #expect(source.readCount == reads)
        #expect(monitor.authorizationStatus == .denied)
        #expect(monitor.todayEvents.isEmpty)
        #expect(!monitor.hasCurrentEvent)
        #expect(monitor.nextEvent == nil)
    }

    @Test("Stopping the feature clears cached meetings")
    func stopClearsEvents() {
        let source = CalendarSourceFake(status: .fullAccess)
        let monitor = CalendarMonitor(source: source)
        monitor.requestAccessAndSync()
        monitor.stop()
        #expect(monitor.todayEvents.isEmpty)
        #expect(!monitor.hasCurrentEvent)
        #expect(monitor.nextEvent == nil)
    }

    @Test("A permission reply after stop cannot restart calendar reads")
    func permissionReplyAfterStopIsIgnored() async throws {
        let source = CalendarSourceFake(status: .notDetermined)
        let monitor = CalendarMonitor(source: source)
        monitor.requestAccessAndSync()
        await source.waitUntilRequested()
        monitor.stop()
        source.authorizationStatus = .fullAccess
        let reply = try #require(source.pendingReply)
        reply.resume(returning: true)
        await source.waitUntilReplyReturned()
        #expect(source.readCount == 0)
        #expect(monitor.todayEvents.isEmpty)
    }

    @Test("Denied permission replies never read events")
    func deniedReplyDoesNotReadEvents() async throws {
        let source = CalendarSourceFake(status: .notDetermined)
        let monitor = CalendarMonitor(source: source)
        defer { monitor.stop() }
        monitor.requestAccessAndSync()
        await source.waitUntilRequested()
        source.authorizationStatus = .denied
        let reply = try #require(source.pendingReply)
        reply.resume(returning: false)
        await source.waitUntilReplyReturned()
        #expect(source.readCount == 0)
        #expect(monitor.authorizationStatus == .denied)
    }
}

@MainActor
private final class CalendarSourceFake: CalendarEventSource {
    var authorizationStatus: EKAuthorizationStatus
    private(set) var readCount = 0
    var onRead: (() -> Void)?
    var pendingReply: CheckedContinuation<Bool, any Error>? {
        pendingReplies.last
    }

    private var pendingReplies: [CheckedContinuation<Bool, any Error>] = []
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var requestWaitCount = 1
    private var replyWaiter: CheckedContinuation<Void, Never>?
    private var replyWaitCount = 1
    private var returnedReplies = 0
    private let store = EKEventStore()

    init(status: EKAuthorizationStatus) {
        self.authorizationStatus = status
    }

    func requestFullAccess() async throws -> Bool {
        defer {
            returnedReplies += 1
            if returnedReplies >= replyWaitCount {
                replyWaiter?.resume()
                replyWaiter = nil
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingReplies.append(continuation)
            if pendingReplies.count >= requestWaitCount {
                requestWaiter?.resume()
                requestWaiter = nil
            }
        }
    }

    func waitUntilRequested(count: Int = 1) async {
        if pendingReplies.count >= count {
            return
        }
        requestWaitCount = count
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func waitUntilReplyReturned(count: Int = 1) async {
        if returnedReplies >= count {
            return
        }
        replyWaitCount = count
        await withCheckedContinuation { replyWaiter = $0 }
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        readCount += 1
        onRead?()
        let now = Date()
        return [-60.0, 600.0].map { offset in
            let event = EKEvent(eventStore: store)
            event.startDate = now.addingTimeInterval(offset)
            event.endDate = event.startDate.addingTimeInterval(300)
            return event
        }
    }
}
