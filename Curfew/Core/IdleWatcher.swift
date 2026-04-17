import CoreGraphics
import Foundation

/// Source of "how long since the user last touched the machine" — wrapped
/// behind a protocol so tests can supply deterministic values without
/// actually idling. Production uses `CGEventSourceIdleSource`, which calls
/// through to `CGEventSource.secondsSinceLastEventType(.combinedSessionState, ...)`.
protocol IdleTimeSource: AnyObject {
    /// Seconds since the most recent mouse move, keyboard event, or
    /// trackpad input. Returns `0` (or a very small value) when the user
    /// is actively interacting.
    func secondsSinceLastInput() -> TimeInterval
}

/// Tracks whether the user is currently idle by polling an
/// `IdleTimeSource`. Intended to be sampled by the enforcement tick so
/// idle minutes can be excluded from work-time accounting (§11) and
/// warning cadence can be paused when the user walks away.
///
/// This class is deliberately *not* a timer owner — it exposes `sample()`
/// and the caller decides when to poll. That keeps the test surface pure
/// (no Timer indirection) and matches the usage pattern: one sample per
/// 1 Hz `tick()` in `CurfewAppModel`.
final class IdleWatcher {
    /// Seconds of inactivity required before the watcher reports idle.
    /// Default matches the todos.md §11 specification (>5 min).
    static let defaultIdleThresholdSeconds: TimeInterval = 5 * 60

    /// Source of the current idle duration.
    private let source: IdleTimeSource

    /// Threshold above which the watcher considers the user idle.
    let idleThresholdSeconds: TimeInterval

    /// Last observed state. Exposed so consumers can check current status
    /// without re-sampling; mutated only inside `sample()`.
    private(set) var isIdle: Bool = false

    /// Invoked with `true` on every active→idle transition and `false` on
    /// every idle→active transition. Same-state samples produce no call.
    var onIdleStateChanged: ((Bool) -> Void)?

    init(
        source: IdleTimeSource,
        idleThresholdSeconds: TimeInterval = defaultIdleThresholdSeconds
    ) {
        self.source = source
        self.idleThresholdSeconds = idleThresholdSeconds
        // Seed the starting state off the first sample so `sample()`
        // below never reports a spurious "transition" on the initial
        // call. This matches the expectation that a fresh `IdleWatcher`
        // reflects the world as it actually is right now.
        self.isIdle = source.secondsSinceLastInput() >= idleThresholdSeconds
    }

    /// Reads the current idle duration and fires `onIdleStateChanged` if
    /// the computed state differs from the previous sample.
    func sample() {
        let nowIdle = source.secondsSinceLastInput() >= idleThresholdSeconds
        guard nowIdle != isIdle else {
            return
        }
        isIdle = nowIdle
        onIdleStateChanged?(nowIdle)
    }
}

/// Production `IdleTimeSource` that reads from the combined HID event
/// source — keyboard, mouse, and trackpad together.
///
/// `CGEventSource.secondsSinceLastEventType` is a static class method
/// keyed on a state ID + an event-type mask. `CGEventType(rawValue: ~0)`
/// is the documented sentinel for "any event" and is what every macOS
/// idle-tracking snippet in the wild uses; we isolate that magic number
/// behind ``anyInputEventType`` so call sites read cleanly.
final class CGEventSourceIdleSource: IdleTimeSource {
    func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: Self.anyInputEventType
        )
    }

    /// Bit-pattern sentinel for "any event type". `CGEventType` is an
    /// enum with numeric raw values; `~0` matches none of the named
    /// cases but is accepted by CoreGraphics as a wildcard.
    private static let anyInputEventType: CGEventType = .init(rawValue: ~0) ?? .null
}
