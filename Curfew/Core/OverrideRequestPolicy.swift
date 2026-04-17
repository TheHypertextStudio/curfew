import Foundation

enum OverrideRequestPolicy {
    static let entryPrompt = "Need to get back in?"
    static let cooldownSeconds = 5 * 60
    static let minimumJustificationCharacters = 50
    static let confirmationHoldSeconds: Double = 3
    static let defaultOverrideDurationMinutes = 30

    static func cooldownEnd(startedAt now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(cooldownSeconds))
    }

    static func canConfirm(
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
