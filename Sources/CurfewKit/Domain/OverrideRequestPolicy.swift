import Foundation

/// Namespace for the constants and pure functions that govern the "Convince Me"
/// override flow.
///
/// The override flow is the primary friction mechanism: the user must wait out
/// a 5-minute cooldown, write at least 50 characters of justification, then
/// hold a button for 3 seconds before the device unlocks. Each step is
/// configurable via these constants so the policy can tighten without
/// touching UI code.
///
/// `CurfewAppModel` calls ``canConfirm(reason:now:cooldownEndsAt:overridesRemaining:)``
/// to gate the confirm action, and ``cooldownEnd(startedAt:)`` to compute the
/// timestamp shown in the countdown UI.
public enum OverrideRequestPolicy {
    /// Prompt shown at the top of the override composer sheet.
    public static let entryPrompt = "Need to get back in?"

    /// Seconds the user must wait before the confirm button becomes available.
    /// The 5-minute cooldown discourages impulsive overrides.
    public static let cooldownSeconds = 5 * 60

    /// Minimum non-whitespace character count required in the justification
    /// field. Enforces a meaningful reason rather than accepting a single word.
    public static let minimumJustificationCharacters = 50

    /// Seconds the user must hold the confirm button before the override is
    /// granted. Deliberate physical friction to match the written friction
    /// of the justification field.
    public static let confirmationHoldSeconds: Double = 3

    /// Minutes the device stays unlocked after an override is confirmed.
    /// Used as the default when no value has been persisted in `CurfewSettings`.
    public static let defaultOverrideDurationMinutes = 30

    /// Returns the `Date` at which the cooldown expires, given that it started
    /// at `now`.
    public static func cooldownEnd(startedAt now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(cooldownSeconds))
    }

    /// Returns `true` when all three gates pass: the reason is long enough,
    /// the weekly override budget is non-zero, and the cooldown has elapsed (or
    /// was never started).
    public static func canConfirm(
        reason: String,
        now: Date,
        cooldownEndsAt: Date?,
        overridesRemaining: Int
    ) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumJustificationCharacters else {
            return false
        }
        guard overridesRemaining > 0 else {
            return false
        }
        guard let cooldownEndsAt else {
            return true
        }
        return now >= cooldownEndsAt
    }
}
