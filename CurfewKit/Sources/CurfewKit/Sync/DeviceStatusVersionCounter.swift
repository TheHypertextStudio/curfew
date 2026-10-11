import Foundation

/// Hands out the strictly increasing `statusVersion` a coordinator's staleness
/// guard needs.
///
/// The guard on the server side is "reject any report whose `statusVersion` is
/// not greater than the one already stored". That only protects the coordinator
/// if this device never reuses or rewinds a number — so the counter is
/// persisted, and it is a counter rather than a clock. A timestamp-derived
/// version would rewind the moment the user's clock stepped backwards (NTP
/// correction, timezone-tool misfire, a deliberate skew attempt), and a rewind
/// is exactly the condition that lets a delayed report overwrite a newer one.
///
/// Reads and writes go straight through `UserDefaults` on every call rather
/// than caching in memory, so two `CurfewAppModel` instances in one process
/// (which the test suite creates constantly) cannot hand out the same number.
public struct DeviceStatusVersionCounter {
    /// Storage key. Versioned like every other key in `CurfewSettingsStore` so
    /// a future format change can migrate rather than collide.
    static let storageKey = "curfew.sync.statusVersion.v1"

    private let defaults: UserDefaults

    /// Creates a counter backed by `defaults`. Tests pass an isolated suite so
    /// one suite's versions never leak into another's.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The highest version handed out so far, or `-1` when none has been.
    ///
    /// Clamped at `-1` on the way out: a corrupted, absent, or hand-edited
    /// negative value must not let ``next()`` return something the schema
    /// rejects (`statusVersion` has `minimum: 0`).
    public var lastIssued: Int {
        guard defaults.object(forKey: Self.storageKey) != nil else { return -1 }
        return max(-1, defaults.integer(forKey: Self.storageKey))
    }

    /// Reserves and returns the next version. Persisted before it is returned,
    /// so a crash between reserving and publishing costs a skipped number
    /// rather than a reused one — the guard tolerates gaps, not repeats.
    public func next() -> Int {
        let issued = lastIssued + 1
        defaults.set(issued, forKey: Self.storageKey)
        return issued
    }
}
