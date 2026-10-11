@testable import Curfew
import EventKit
import Testing

@MainActor
struct CalendarPresentationTests {
    @Test("Revoked or read-ineligible calendar access replaces a cached granted status")
    func revokedPermission() {
        for status in [EKAuthorizationStatus.denied, .restricted, .notDetermined, .writeOnly] {
            let monitor = CalendarMonitor(authorization: { status })
            monitor.seedDemoAuthorization(.fullAccess)
            monitor.sync()
            #expect(monitor.authorizationStatus == status)
            #expect(monitor.todayEvents.isEmpty)
            #expect(!monitor.hasCurrentEvent)
            #expect(monitor.nextEvent == nil)
        }
    }

    @Test("Calendar advice only offers an extension when the action is available")
    func extensionAdvice() {
        for available in [true, false] {
            let body = CalendarOverlapCopy.body(
                eventTitle: "Planning", startTime: "17:45", lockTime: "18:00",
                canRequestExtension: available
            )
            #expect(body.contains("Planning starts at 17:45"))
            #expect(body.contains("18:00"))
            #expect(body.contains("request an extension") == available)
        }
    }
}
