import Foundation
import OSLog

private let recorderLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "activity-recorder"
)

/// Bridge between live `CurfewAppModel` state transitions and an activity
/// log. Split into a protocol so the app can hold a non-optional recorder
/// at all times: production wraps ``ActivityStore`` in ``ActivityRecorder``;
/// when the store fails to open, the app substitutes
/// ``NullActivityRecording`` which silently discards writes.
///
/// Alternative — `ActivityRecorder?` sprinkled through the tick loop —
/// would force every call site to `?.` even though the failure mode is
/// intrinsically "can't log, keep running."
@MainActor
protocol ActivityRecording: AnyObject {
    func recordPhaseTransition(
        from previous: EnforcementPhase,
        to current: EnforcementPhase,
        at timestamp: Date
    )

    func recordExtensionGranted(minutes: Int, at timestamp: Date)

    /// Records an override grant via the "Convince Me" flow. `reason` is
    /// persisted verbatim for retrospective display.
    func recordOverrideGranted(minutes: Int, reason: String, at timestamp: Date)

    /// Records a warning stage escalation. `stageDescriptor` is a stable
    /// string token (e.g. "T-30") so rollups can bucket without coupling
    /// to the Swift enum.
    func recordWarningEscalation(
        stageDescriptor: String,
        minutesRemaining: Int,
        at timestamp: Date
    )

    /// Returns events in the given date range. The recorder is the single
    /// entry point for both writes and reads so consumers don't need to
    /// separately hold the underlying store. Failure modes (store closed,
    /// SQLite error) collapse to an empty array — the retrospective UI
    /// treats "no events" and "read failed" identically, which is
    /// appropriate for a non-critical surface.
    func events(in range: ClosedRange<Date>) -> [ActivityEvent]

    /// Returns a CSV string for all events in `range`, or throws on I/O
    /// failure. Callers that want failure-safe behaviour should catch and
    /// fall back to the header-only string.
    func exportCSV(in range: ClosedRange<Date>) throws -> String

    /// Deletes events older than `seconds` relative to `now`. Called on
    /// day rollover to enforce the 52-week retention window advertised in
    /// PRIVACY.md. Failures are logged and swallowed — a trim that fails
    /// must never block the tick loop.
    func trim(olderThan seconds: TimeInterval, now: Date)

    /// Monotonic counter bumped on every successful write. Lets views
    /// (notably `ThisWeekView`) memoise expensive rollups and invalidate
    /// only when data actually changes — not on every tick. Wraps around
    /// at `Int.max` but in practice will not approach that for any
    /// realistic lifetime of an install.
    var mutationCount: Int { get }
}

/// Production ``ActivityRecording`` that writes to a SQLite-backed
/// ``ActivityStore``.
///
/// Errors from the store are swallowed and routed to `os.Logger` — a log
/// write failing must not prevent the user from continuing to work, and
/// the alternative (throwing up into the tick loop) would create far
/// worse UX than a missing row in the retrospective. `os.Logger` is used
/// instead of `stderr` so failures are captured by Console.app + sysdiagnose
/// for post-hoc diagnosis on real user installs.
@MainActor
final class ActivityRecorder: ActivityRecording {
    private let store: ActivityStore
    private let gateKind: String
    private(set) var mutationCount: Int = 0

    init(store: ActivityStore, gateKind: String = GateKind.curfew) {
        self.store = store
        self.gateKind = gateKind
    }

    /// Emits a pair of events on `working|warning → locked` and a single
    /// `lockoutEnded` on the inverse. Same-phase calls are no-ops and
    /// never touch the store — important because `tick()` fires at 1 Hz
    /// and most ticks are same-phase.
    func recordPhaseTransition(
        from previous: EnforcementPhase,
        to current: EnforcementPhase,
        at timestamp: Date
    ) {
        guard previous != current else {
            return
        }

        if current == .locked, previous != .locked {
            if previous == .working || previous == .warning {
                appendSafely(.init(
                    timestamp: timestamp,
                    gateKind: gateKind,
                    kind: .sessionEnded,
                    minutesValue: nil,
                    note: nil
                ))
            }
            appendSafely(.init(
                timestamp: timestamp,
                gateKind: gateKind,
                kind: .lockoutStarted,
                minutesValue: nil,
                note: nil
            ))
        } else if previous == .locked, current != .locked {
            appendSafely(.init(
                timestamp: timestamp,
                gateKind: gateKind,
                kind: .lockoutEnded,
                minutesValue: nil,
                note: nil
            ))
        }
    }

    func recordExtensionGranted(minutes: Int, at timestamp: Date) {
        appendSafely(.init(
            timestamp: timestamp,
            gateKind: gateKind,
            kind: .extensionGranted,
            minutesValue: minutes,
            note: nil
        ))
    }

    func recordOverrideGranted(minutes: Int, reason: String, at timestamp: Date) {
        appendSafely(.init(
            timestamp: timestamp,
            gateKind: gateKind,
            kind: .overrideGranted,
            minutesValue: minutes,
            note: reason
        ))
    }

    func recordWarningEscalation(
        stageDescriptor: String,
        minutesRemaining: Int,
        at timestamp: Date
    ) {
        appendSafely(.init(
            timestamp: timestamp,
            gateKind: gateKind,
            kind: .warningEscalated,
            minutesValue: minutesRemaining,
            note: stageDescriptor
        ))
    }

    /// Returns events within the range, swallowing (and logging) any
    /// SQLite error. See protocol doc for the rationale behind empty-on-
    /// failure semantics.
    func events(in range: ClosedRange<Date>) -> [ActivityEvent] {
        do {
            return try store.events(in: range)
        } catch {
            recorderLogger.error("activity fetch failed: \(String(describing: error))")
            return []
        }
    }

    /// Delegates to `ActivityStore.exportCSV(in:)`, propagating any I/O error.
    func exportCSV(in range: ClosedRange<Date>) throws -> String {
        try store.exportCSV(in: range)
    }

    func trim(olderThan seconds: TimeInterval, now: Date) {
        do {
            try store.trimEvents(olderThan: seconds, now: now)
        } catch {
            recorderLogger.error("activity trim failed: \(String(describing: error))")
        }
    }

    private func appendSafely(_ event: ActivityEvent) {
        do {
            try store.append(event)
            mutationCount &+= 1
        } catch {
            recorderLogger.error("activity append failed: \(String(describing: error))")
        }
    }
}

/// No-op ``ActivityRecording`` used when the SQLite store couldn't be
/// opened. Writes silently succeed (by doing nothing) so the rest of the
/// app continues to enforce without special-casing a missing recorder.
@MainActor
final class NullActivityRecording: ActivityRecording {
    func recordPhaseTransition(
        from previous: EnforcementPhase,
        to current: EnforcementPhase,
        at timestamp: Date
    ) {}

    func recordExtensionGranted(minutes: Int, at timestamp: Date) {}

    func recordOverrideGranted(minutes: Int, reason: String, at timestamp: Date) {}

    func recordWarningEscalation(
        stageDescriptor: String,
        minutesRemaining: Int,
        at timestamp: Date
    ) {}

    func events(in range: ClosedRange<Date>) -> [ActivityEvent] {
        []
    }

    func exportCSV(in range: ClosedRange<Date>) throws -> String {
        "id,timestamp,gate_kind,kind,minutes_value,note"
    }

    func trim(olderThan seconds: TimeInterval, now: Date) {}

    /// Always zero — a null recorder writes nothing so consumers treating
    /// this as "nothing has changed ever" keep stable cached state.
    let mutationCount: Int = 0
}
