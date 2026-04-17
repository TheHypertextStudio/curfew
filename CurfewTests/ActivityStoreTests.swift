@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for `ActivityStore`, the SQLite-backed activity log.
///
/// Each test opens its own database in a fresh temp directory via
/// `ActivityTestSupport.makeEphemeralStore(label:)`, so the suite is
/// hermetic and parallel-safe.
@MainActor
struct ActivityStoreTests {
    @Test("Appending an event makes it retrievable by date range")
    func appendAndFetch() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "append")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = ActivityEvent(
            timestamp: now,
            gateKind: GateKind.curfew,
            kind: .lockoutStarted,
            minutesValue: nil,
            note: nil
        )

        try store.append(event)

        let fetched = try store.events(
            in: now.addingTimeInterval(-60) ... now.addingTimeInterval(60)
        )
        #expect(fetched.count == 1)
        #expect(fetched.first?.kind == .lockoutStarted)
        #expect(fetched.first?.gateKind == GateKind.curfew)
    }

    @Test("Events outside the requested range are excluded")
    func dateRangeFilter() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "range")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.append(
            ActivityEvent(
                timestamp: base,
                gateKind: GateKind.curfew,
                kind: .extensionGranted,
                minutesValue: 15,
                note: nil
            )
        )
        try store.append(
            ActivityEvent(
                timestamp: base.addingTimeInterval(7 * 24 * 60 * 60),
                gateKind: GateKind.curfew,
                kind: .extensionGranted,
                minutesValue: 15,
                note: nil
            )
        )

        let onlyFirst = try store.events(
            in: base.addingTimeInterval(-60) ... base.addingTimeInterval(60)
        )
        #expect(onlyFirst.count == 1)

        let both = try store.events(
            in: base.addingTimeInterval(-60) ... base.addingTimeInterval(10 * 24 * 60 * 60)
        )
        #expect(both.count == 2)
    }

    @Test("Retention trims events older than the retention horizon")
    func retentionTrimming() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "retention")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldEvent = ActivityEvent(
            timestamp: now.addingTimeInterval(-400 * 24 * 60 * 60),
            gateKind: GateKind.curfew,
            kind: .lockoutStarted,
            minutesValue: nil,
            note: nil
        )
        let recentEvent = ActivityEvent(
            timestamp: now.addingTimeInterval(-7 * 24 * 60 * 60),
            gateKind: GateKind.curfew,
            kind: .lockoutStarted,
            minutesValue: nil,
            note: nil
        )
        try store.append(oldEvent)
        try store.append(recentEvent)

        try store.trimEvents(olderThan: 52 * 7 * 24 * 60 * 60, now: now)

        let survivors = try store.events(
            in: now.addingTimeInterval(-500 * 24 * 60 * 60) ... now
        )
        #expect(survivors.count == 1)
        #expect(survivors.first?.timestamp == recentEvent.timestamp)
    }

    @Test("Optional fields round-trip through the store")
    func optionalFieldRoundTrip() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "roundtrip")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = ActivityEvent(
            timestamp: now,
            gateKind: GateKind.curfew,
            kind: .overrideGranted,
            minutesValue: 30,
            note: "Fix urgent production bug"
        )
        try store.append(event)

        let fetched = try #require(
            try store.events(
                in: now.addingTimeInterval(-60) ... now.addingTimeInterval(60)
            ).first
        )
        #expect(fetched.kind == .overrideGranted)
        #expect(fetched.minutesValue == 30)
        #expect(fetched.note == "Fix urgent production bug")
    }
}
