import Foundation

/// User-configurable minute thresholds that govern when each ``WarningStage``
/// activates.
///
/// Stored as part of ``CurfewSettings`` and normalised on every write so
/// stages remain strictly ordered. ``WarningIntervals/default`` matches the
/// canonical 30 / 15 / 5 / 2 / 1 cadence; users can drag sliders in Settings
/// to tighten or relax the escalation timing.
///
/// Always use ``normalized`` before comparing values — raw user input may
/// violate the ordering invariant.
public struct WarningIntervals: Codable, Equatable {
    /// Minutes remaining when the T-30 stage fires.
    public var thirtyMinutes: Int

    /// Minutes remaining when the T-15 stage fires.
    /// Must be less than ``thirtyMinutes`` after normalisation.
    public var fifteenMinutes: Int

    /// Minutes remaining when the T-5 stage fires.
    /// Must be less than ``fifteenMinutes`` after normalisation.
    public var fiveMinutes: Int

    /// Minutes remaining when the T-2 stage fires.
    /// Must be less than ``fiveMinutes`` after normalisation.
    public var twoMinutes: Int

    /// Minutes remaining when the T-1 stage fires.
    /// Must be less than ``twoMinutes`` after normalisation (minimum 1).
    public var oneMinute: Int

    /// Memberwise initialiser. Values are clamped into a strictly-
    /// decreasing order by ``normalized`` before the engine consumes
    /// them, so callers may pass any non-negative integers.
    public init(
        thirtyMinutes: Int,
        fifteenMinutes: Int,
        fiveMinutes: Int,
        twoMinutes: Int,
        oneMinute: Int
    ) {
        self.thirtyMinutes = thirtyMinutes
        self.fifteenMinutes = fifteenMinutes
        self.fiveMinutes = fiveMinutes
        self.twoMinutes = twoMinutes
        self.oneMinute = oneMinute
    }

    /// Canonical escalation thresholds: 30 / 15 / 5 / 2 / 1 minutes.
    public static let `default` = WarningIntervals(
        thirtyMinutes: 30,
        fifteenMinutes: 15,
        fiveMinutes: 5,
        twoMinutes: 2,
        oneMinute: 1
    )

    /// Returns a copy with stages clamped to their valid ranges and sorted
    /// strictly ascending from `oneMinute` to `thirtyMinutes`.
    ///
    /// Normalisation caps each stage at a sensible ceiling (1–30 min, 2–45,
    /// 5–90, 15–180, 30–360) and then re-enforces the ordering bottom-up so
    /// out-of-range user input never produces a non-monotone sequence.
    public var normalized: WarningIntervals {
        var one = max(1, min(oneMinute, 30))
        var two = max(one + 1, min(twoMinutes, 45))
        var five = max(two + 1, min(fiveMinutes, 90))
        var fifteen = max(five + 1, min(fifteenMinutes, 180))
        let thirty = max(fifteen + 1, min(thirtyMinutes, 360))

        // Keep canonical lower stages when clamping higher ones.
        one = min(one, two - 1)
        two = min(two, five - 1)
        five = min(five, fifteen - 1)
        fifteen = min(fifteen, thirty - 1)

        return WarningIntervals(
            thirtyMinutes: thirty,
            fifteenMinutes: fifteen,
            fiveMinutes: five,
            twoMinutes: two,
            oneMinute: one
        )
    }
}

/// Fine-grained escalation stage orthogonal to ``EnforcementPhase``.
///
/// `CurfewEnforcementEngine` sets `warningStage` on every ``CurfewEvaluation``
/// so UI surfaces can graduate their responses — dim overlay opacity ramps up,
/// the floating timer appears, and the extension button activates — without
/// switching the broad phase. The stage is present even during `.working` so
/// the engine can signal T-30 before the lockout phase begins.
///
/// ``stage(forMinutesRemaining:intervals:)`` is the canonical constructor.
/// All other properties are derived from the case and carry no extra state.
public enum WarningStage: Equatable {
    /// No warning is active. The device is well within its working window.
    case none

    /// T-30: first visible warning. Dim overlay appears; extension and snooze
    /// buttons are enabled.
    case thirtyMinutes

    /// T-15: second warning. Same affordances as T-30.
    case fifteenMinutes

    /// T-5: urgency escalates. The floating countdown timer appears; overlay
    /// opacity increases. Extension / snooze no longer offered.
    case fiveMinutes

    /// T-2: high-urgency. Overlay darkens further.
    case twoMinutes

    /// T-1: final warning. Overlay is near-opaque.
    case oneMinute

    /// The working window has ended. Full-screen lockout is shown. Overlaps
    /// with ``EnforcementPhase/locked`` — the stage is set here so the engine
    /// can produce a fully self-contained evaluation.
    case lockout

    /// Returns the appropriate stage for `minutes` minutes remaining, using
    /// the thresholds in `intervals`.
    ///
    /// Normalises `intervals` internally so raw user input is safe to pass.
    /// Returns ``none`` when `minutes` exceeds every threshold.
    public static func stage(
        forMinutesRemaining minutes: Int,
        intervals: WarningIntervals = .default
    ) -> WarningStage {
        let normalized = intervals.normalized
        if minutes <= 0 {
            return .lockout
        }
        if minutes <= normalized.oneMinute {
            return .oneMinute
        }
        if minutes <= normalized.twoMinutes {
            return .twoMinutes
        }
        if minutes <= normalized.fiveMinutes {
            return .fiveMinutes
        }
        if minutes <= normalized.fifteenMinutes {
            return .fifteenMinutes
        }
        if minutes <= normalized.thirtyMinutes {
            return .thirtyMinutes
        }
        return .none
    }

    /// `true` when the user may snooze the warning from this stage. Only T-30
    /// and T-15 allow snoozing — late enough to be meaningful, early enough
    /// not to be trivially abused.
    public var supportsSnooze: Bool {
        switch self {
        case .thirtyMinutes, .fifteenMinutes:
            true
        case .none, .fiveMinutes, .twoMinutes, .oneMinute, .lockout:
            false
        }
    }

    /// `true` when the floating countdown timer should be visible. The timer
    /// appears at T-5 and below to create urgency without cluttering the
    /// screen during the earlier, softer warnings.
    public var showsFloatingTimer: Bool {
        switch self {
        case .fiveMinutes, .twoMinutes, .oneMinute:
            true
        case .none, .thirtyMinutes, .fifteenMinutes, .lockout:
            false
        }
    }

    /// Fractional opacity (0–1) of the dim overlay for this stage. `0` means
    /// no overlay. `1` means the full-screen lockout. Intermediate values
    /// progressively darken the screen to signal approaching lockout.
    public var overlayOpacity: Double {
        switch self {
        case .none, .thirtyMinutes, .fifteenMinutes:
            0
        case .fiveMinutes:
            0.10
        case .twoMinutes:
            0.25
        case .oneMinute:
            0.40
        case .lockout:
            1.0
        }
    }
}
