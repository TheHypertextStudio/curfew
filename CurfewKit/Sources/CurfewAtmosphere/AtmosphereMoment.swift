import CurfewKit
import Foundation

/// A pure description of the sky at one instant — the single source the whole
/// app's atmosphere is rendered from. No SwiftUI, so the mapping (clock +
/// curfew window → light) is unit-testable in isolation (see `AtmosphereMomentTests`).
///
/// "Your sundown": when a curfew window exists the sky's sunset is pinned to the
/// *lock time* rather than the literal solar day, so the dusk deepens as your
/// curfew approaches and the night lifts toward your unlock. With no window it
/// falls back to the real time of day.
public struct AtmosphereMoment: Equatable {
    /// Overall lightness. `0` = deep night · `~0.45` = the horizon (dawn/dusk) ·
    /// `1` = midday. Drives gradient selection, star visibility, and glow.
    public var light: Double

    /// Whether the light is climbing (dawn side) or falling (dusk side). Anchors
    /// the sun glow to the top when rising, the horizon when falling.
    public var rising: Bool

    /// Continuous vertical glow anchor, avoiding a top/bottom jump at deep night.
    public var glowPosition: Double

    /// Nearness to the lock time, `0` (far) → `1` (at curfew). Kindles and
    /// reddens the ember as the deadline closes. Always `0` once locked, on a
    /// day off, or with no scheduled window.
    public var proximity: Double

    /// Clamps `light`/`proximity` into 0...1 so callers can pass raw ramps.
    public init(light: Double, rising: Bool, proximity: Double = 0, glowPosition: Double = 1) {
        self.light = min(max(light, 0), 1)
        self.rising = rising
        self.glowPosition = min(max(glowPosition, 0), 1)
        self.proximity = min(max(proximity, 0), 1)
    }
}

public extension AtmosphereMoment {
    /// Coarse semantic band, for callers that branch on it (e.g. copy or the
    /// menu-bar tint). The renderer itself interpolates continuously on `light`.
    enum Band: Equatable {
        case day
        case golden
        case dusk
        case night
        case dawn
    }

    /// The band this moment falls in. Dawn/dusk share the horizon range and are
    /// split by direction (`rising`).
    var band: Band {
        if light >= 0.78 {
            return .day
        }
        if light >= 0.6 {
            return .golden
        }
        if light >= 0.42 {
            return rising ? .dawn : .dusk
        }
        if rising, light >= 0.3 {
            return .dawn
        }
        return .night
    }

    /// Star-field opacity — fades in only after dusk, full in deep night.
    var starOpacity: Double {
        min(max((0.42 - light) / 0.42, 0), 1)
    }
}

// MARK: - Presets

public extension AtmosphereMoment {
    /// Bright warm afternoon.
    static let daylight = AtmosphereMoment(light: 0.92, rising: false)
    /// Golden hour — warm, the ember beginning to gather.
    static let golden = AtmosphereMoment(light: 0.66, rising: false, proximity: 0.3)
    /// Sunset at the horizon — the signature dusk.
    static let dusk = AtmosphereMoment(light: 0.46, rising: false, proximity: 0.7)
    /// Deep night — the lockout sky.
    static let night = AtmosphereMoment(light: 0.10, rising: false)
    /// First light — the sunrise sky.
    static let dawn = AtmosphereMoment(light: 0.44, rising: true)
}

// MARK: - Resolution from live state

extension AtmosphereMoment {
    /// Derives the moment from the current time and the curfew evaluation. This
    /// is the one function every surface's atmosphere ultimately comes from.
    public static func resolve(
        now: Date,
        lockDate: Date?,
        unlockDate: Date?,
        phase: EnforcementPhase,
        sunriseLeadMinutes: Int = 45
    ) -> AtmosphereMoment {
        if let lockDate, let unlockDate, unlockDate > lockDate,
           now >= lockDate {
            return locked(
                now: now,
                lockDate: lockDate,
                unlockDate: unlockDate,
                sunriseLeadMinutes: sunriseLeadMinutes
            )
        }
        switch phase {
        case .locked:
            return locked(
                now: now,
                lockDate: lockDate,
                unlockDate: unlockDate,
                sunriseLeadMinutes: sunriseLeadMinutes
            )
        case .working, .warning:
            if let lockDate {
                return approaching(now: now, lockDate: lockDate)
            }
            return timeOfDay(now)
        case .dayOff:
            return timeOfDay(now)
        }
    }

    /// Pre-lock descent: the sky lowers from afternoon toward the horizon over
    /// the final six hours, and the ember kindles across the last 90 minutes.
    private static func approaching(now: Date, lockDate: Date) -> AtmosphereMoment {
        let minutesToLock = lockDate.timeIntervalSince(now) / 60
        let descent = min(max(minutesToLock / (6 * 60), 0), 1) // 6h out … lock
        let light = 0.44 + 0.48 * descent // 0.92 … 0.44 at the horizon
        let proximity = 1 - min(max(minutesToLock / 90, 0), 1)
        return AtmosphereMoment(light: light, rising: false, proximity: proximity)
    }

    /// Night arc: darkest at the midpoint of the lock→unlock window, lifting
    /// back toward pre-dawn as the morning approaches.
    private static func locked(
        now: Date,
        lockDate: Date?,
        unlockDate: Date?,
        sunriseLeadMinutes: Int
    ) -> AtmosphereMoment {
        guard let lockDate, let unlockDate, unlockDate > lockDate else {
            return .night
        }
        let span = unlockDate.timeIntervalSince(lockDate)
        let elapsed = max(0, now.timeIntervalSince(lockDate))
        let approach = min(Double(max(1, sunriseLeadMinutes)) * 60, span / 2)
        let dawnStart = span - approach
        let light: Double
        if elapsed <= span / 2 {
            light = 0.44 - 0.38 * (elapsed / (span / 2))
        } else if elapsed < dawnStart {
            light = 0.06 + 0.06 * ((elapsed - span / 2) / (dawnStart - span / 2))
        } else if elapsed <= span {
            // A short night starts its dawn at the midpoint, where light is 0.06.
            let base = dawnStart > span / 2 ? 0.12 : 0.06
            light = base + (0.40 - base) * ((elapsed - dawnStart) / approach)
        } else {
            light = 0.40 + 0.52 * min((elapsed - span) / (15 * 60), 1)
        }
        let rise = min(max((elapsed - dawnStart) / (approach + 15 * 60), 0), 1)
        return AtmosphereMoment(
            light: light,
            rising: elapsed > span / 2,
            proximity: max(0, 1 - elapsed / min(15 * 60, span / 4)),
            glowPosition: 1 - 0.7 * rise
        )
    }

    /// No curfew window: map the literal clock to a smooth day/night curve —
    /// deep night around 1am, midday peak around 1pm.
    private static func timeOfDay(_ now: Date) -> AtmosphereMoment {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
        let light = 0.5 - 0.5 * cos(2 * .pi * (hour - 1) / 24)
        return AtmosphereMoment(light: light, rising: hour >= 1 && hour < 13)
    }
}
