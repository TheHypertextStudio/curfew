public extension DayRule {
    /// Applies the fields carried by a queued clock edit to the rule at approval.
    /// Other settings may have changed while the request waited for consent.
    func applyingClockUpdate(
        lockMinutes: Int,
        unlockMinutes: Int? = nil,
        isDayOff: Bool? = nil
    ) -> DayRule {
        var updated = self
        updated.lockMinutes = lockMinutes
        if let unlockMinutes {
            updated.unlockMinutes = unlockMinutes
        }
        if let isDayOff {
            updated.isDayOff = isDayOff
        }
        return updated
    }
}
