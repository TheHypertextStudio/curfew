import Foundation

public enum OverrideRequestPolicy {
    public static let entryPrompt = "Need to get back in?"
    public static let cooldownSeconds = 5 * 60
    public static let minimumJustificationCharacters = 50
    public static let confirmationHoldSeconds: Double = 3
    public static let defaultOverrideDurationMinutes = 30

    public static func cooldownEnd(startedAt now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(cooldownSeconds))
    }

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
