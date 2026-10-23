import CurfewKit
import EventKit
import Foundation

/// Keeps permission and event reads injectable without opening a real TCC prompt in tests.
@MainActor
protocol CalendarEventSource {
    var authorizationStatus: EKAuthorizationStatus { get }
    @discardableResult func requestFullAccess() async throws -> Bool
    func events(from start: Date, to end: Date) -> [EKEvent]
}

/// EventKit adapter for the optional calendar integration.
final class SystemCalendarEventSource: CalendarEventSource {
    private let store = EKEventStore()

    nonisolated init() {}

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestFullAccess() async throws -> Bool {
        guard !RuntimeEnvironment.isUnitTestHost else { return false }
        return try await store.requestFullAccessToEvents()
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard authorizationStatus == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
    }
}
