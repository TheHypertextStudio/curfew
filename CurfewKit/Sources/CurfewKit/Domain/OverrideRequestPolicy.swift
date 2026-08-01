import Foundation

/// Namespace for the constants and pure functions that govern the "Convince Me"
/// override flow.
///
/// The override flow is the friction mechanism: the user must write at least 50
/// characters of justification, wait through a five-minute cooling-off period,
/// then hold a button for 3 seconds before the device unlocks.
///
/// `CurfewAppModel` calls ``canConfirm(reason:overridesRemaining:)`` to gate the
/// confirm action.
public enum OverrideRequestPolicy {
    /// Prompt shown at the top of the override composer sheet.
    public static let entryPrompt = "Need to get back in?"

    /// Minimum non-whitespace character count required in the justification
    /// field. Enforces a meaningful reason rather than accepting a single word.
    public static let minimumJustificationCharacters = 50

    /// Seconds the user must hold the confirm button before the override is
    /// granted. Deliberate physical friction to match the written friction
    /// of the justification field.
    public static let confirmationHoldSeconds: Double = 3

    /// Cooling-off period between requesting and confirming an override.
    public static let cooldownSeconds: TimeInterval = 5 * 60

    /// Minutes the device stays unlocked after an override is confirmed.
    /// Used as the default when no value has been persisted in `CurfewSettings`.
    public static let defaultOverrideDurationMinutes = 30

    /// Returns `true` when both gates pass: the reason is long enough and the
    /// weekly override budget is non-zero.
    public static func canConfirm(
        reason: String,
        overridesRemaining: Int,
        requestedAt: Date?,
        now: Date
    ) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumJustificationCharacters else {
            return false
        }
        guard overridesRemaining > 0, let requestedAt else { return false }
        return now.timeIntervalSince(requestedAt) >= cooldownSeconds
    }

    public static func cooldownRemaining(requestedAt: Date?, now: Date) -> TimeInterval {
        guard let requestedAt else { return cooldownSeconds }
        return max(0, cooldownSeconds - now.timeIntervalSince(requestedAt))
    }
}
