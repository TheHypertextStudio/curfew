@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Behaviour tests for `ActivityRecorder` — the bridge from
/// `CurfewAppModel` state transitions to `ActivityStore` writes.
@MainActor
struct ActivityRecorderTests {
    @Test("Working → locked transition records lockoutStarted")
    func recordsLockoutEntry() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "recorder-entry")
        let recorder = ActivityRecorder(store: store)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        recorder.recordPhaseTransition(from: .working, to: .locked, at: now)

        let events = try store.events(
            in: now.addingTimeInterval(-1) ... now.addingTimeInterval(1)
        )
        let kinds = events.map(\.kind)
        #expect(kinds.contains(.sessionEnded))
        #expect(kinds.contains(.lockoutStarted))
    }

    @Test("Locked → working transition records lockoutEnded")
    func recordsLockoutExit() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "recorder-exit")
        let recorder = ActivityRecorder(store: store)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        recorder.recordPhaseTransition(from: .locked, to: .working, at: now)

        let events = try store.events(
            in: now.addingTimeInterval(-1) ... now.addingTimeInterval(1)
        )
        #expect(events.map(\.kind) == [.lockoutEnded])
    }

    @Test("Same-phase transitions produce no events")
    func noOpTransition() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "recorder-noop")
        let recorder = ActivityRecorder(store: store)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        recorder.recordPhaseTransition(from: .working, to: .working, at: now)

        let events = try store.events(in: .distantPast ... .distantFuture)
        #expect(events.isEmpty)
    }

    @Test("Extension grant event carries minutes payload")
    func extensionGrantPayload() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "recorder-ext")
        let recorder = ActivityRecorder(store: store)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        recorder.recordExtensionGranted(minutes: 15, at: now)

        let fetched = try #require(
            try store.events(in: .distantPast ... .distantFuture).first
        )
        #expect(fetched.kind == .extensionGranted)
        #expect(fetched.minutesValue == 15)
    }

    @Test("Override grant event carries minutes and reason")
    func overrideGrantPayload() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "recorder-override")
        let recorder = ActivityRecorder(store: store)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        recorder.recordOverrideGranted(minutes: 30, reason: "urgent fix", at: now)

        let fetched = try #require(
            try store.events(in: .distantPast ... .distantFuture).first
        )
        #expect(fetched.kind == .overrideGranted)
        #expect(fetched.minutesValue == 30)
        #expect(fetched.note == "urgent fix")
    }
}
