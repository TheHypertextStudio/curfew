import CurfewKit
import Foundation
import OSLog

private let reflectionRecorderLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "reflection-recorder"
)

/// Bridge between `CurfewAppModel` and the reflection log, mirroring
/// ``ActivityRecording``. A protocol so the app can hold a non-optional
/// recorder at all times: production wraps ``ReflectionStore`` in
/// ``ReflectionRecorder``; when the store can't be opened the app substitutes
/// ``NullReflectionRecording`` which silently discards writes.
///
/// The content store is separate from the activity log; a lightweight
/// ``ActivityEventKind/reflectionRecorded`` marker is written through
/// ``ActivityRecording/recordReflectionRecorded(gate:at:)`` so timelines can
/// still note that a reflection happened.
@MainActor
protocol ReflectionRecording: AnyObject {
    /// Persists one completed ``Reflection``. Failures collapse to a logged
    /// no-op — a reflection that fails to save must never block the user.
    func record(_ reflection: Reflection)

    /// Returns reflections whose timestamp falls in `range`, ascending.
    /// Failure modes collapse to an empty array, matching ``ActivityRecording``.
    func reflections(in range: ClosedRange<Date>) -> [Reflection]

    /// Deletes reflections older than `seconds` relative to `now`. Called on
    /// day rollover to share the activity log's 52-week retention window.
    func trim(olderThan seconds: TimeInterval, now: Date)

    /// Monotonic counter bumped on every successful write. Lets the Journal
    /// memoise its reflection fetch and invalidate only when data changes.
    var mutationCount: Int { get }
}

/// Production ``ReflectionRecording`` backed by a SQLite ``ReflectionStore``.
/// Errors are swallowed and routed to `os.Logger`, matching
/// ``ActivityRecorder``'s rationale: a failed log write must not interrupt the
/// user, and throwing into the gate-handling path would be worse UX than a
/// missing Journal row.
@MainActor
final class ReflectionRecorder: ReflectionRecording {
    private let store: ReflectionStore
    /// Monotonic write counter. See ``ReflectionRecording`` for rationale.
    private(set) var mutationCount: Int = 0

    /// Wraps `store` as the active reflection recorder.
    init(store: ReflectionStore) {
        self.store = store
    }

    func record(_ reflection: Reflection) {
        do {
            try store.append(reflection)
            mutationCount &+= 1
        } catch {
            reflectionRecorderLogger.error(
                "reflection append failed: \(String(describing: error))"
            )
        }
    }

    func reflections(in range: ClosedRange<Date>) -> [Reflection] {
        do {
            return try store.reflections(in: range)
        } catch {
            reflectionRecorderLogger.error(
                "reflection fetch failed: \(String(describing: error))"
            )
            return []
        }
    }

    func trim(olderThan seconds: TimeInterval, now: Date) {
        do {
            try store.trimReflections(olderThan: seconds, now: now)
        } catch {
            reflectionRecorderLogger.error(
                "reflection trim failed: \(String(describing: error))"
            )
        }
    }
}

/// No-op ``ReflectionRecording`` used when the SQLite store couldn't be
/// opened. Writes silently succeed (by doing nothing) so the rest of the app
/// continues to function without special-casing a missing recorder.
@MainActor
final class NullReflectionRecording: ReflectionRecording {
    /// `nonisolated` so it can be used as a default argument for the
    /// `@MainActor`-isolated `CurfewAppModel` initialiser — the body only sets
    /// a constant, touching no actor-isolated state.
    nonisolated init() {}

    /// No-op. Conforms to `ReflectionRecording`.
    func record(_ reflection: Reflection) {}

    /// Always returns an empty array — there's nothing stored.
    func reflections(in range: ClosedRange<Date>) -> [Reflection] {
        []
    }

    /// No-op. Conforms to `ReflectionRecording`.
    func trim(olderThan seconds: TimeInterval, now: Date) {}

    /// Always zero — a null recorder writes nothing.
    let mutationCount: Int = 0
}
