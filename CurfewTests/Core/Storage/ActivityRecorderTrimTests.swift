@testable import Curfew
import Foundation
import Testing

/// Verifies that `ActivityRecorder.trim` forwards to the underlying
/// `ActivityStore.trimEvents`, enforcing the 52-week rolling retention
/// the app advertises in `PRIVACY.md`. Regression guard — before this
/// hook, `trimEvents` existed but was never invoked outside tests and
/// the SQLite file grew without bound.
@MainActor
struct ActivityRecorderTrimTests {
    @Test("Trim removes events older than the retention horizon")
    func trimDelegatesToStore() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "recorder-trim")
        let recorder = ActivityRecorder(store: store)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try store.append(
            ActivityEvent(
                timestamp: now.addingTimeInterval(-400 * 24 * 60 * 60),
                gateKind: GateKind.curfew,
                kind: .lockoutStarted,
                minutesValue: nil,
                note: nil
            )
        )
        try store.append(
            ActivityEvent(
                timestamp: now.addingTimeInterval(-7 * 24 * 60 * 60),
                gateKind: GateKind.curfew,
                kind: .lockoutStarted,
                minutesValue: nil,
                note: nil
            )
        )

        recorder.trim(olderThan: 52 * 7 * 24 * 60 * 60, now: now)

        let survivors = try store.events(
            in: now.addingTimeInterval(-500 * 24 * 60 * 60) ... now
        )
        #expect(survivors.count == 1)
    }

    @Test("Null recorder swallows trim calls without error")
    func nullTrimIsNoop() {
        let recorder = NullActivityRecording()
        recorder.trim(olderThan: 60, now: Date())
        // No expectation beyond "doesn't throw and compiles" — the contract
        // is that a null recorder never affects observable state.
    }

    @Test("CSV export terminates rows with CRLF per RFC 4180")
    func csvUsesCRLF() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "csv-crlf")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try store.append(
            ActivityEvent(
                timestamp: now,
                gateKind: GateKind.curfew,
                kind: .lockoutStarted,
                minutesValue: nil,
                note: nil
            )
        )

        let csv = try store.exportCSV(
            in: now.addingTimeInterval(-60) ... now.addingTimeInterval(60)
        )
        #expect(csv.contains("\r\n"))
        #expect(!csv.contains("\n\n"))
    }
}
