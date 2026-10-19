/// Resolves the local opt-in for automatic weekly lockouts for every process
/// that reads Curfew's settings. Remote fixed-duration commands and durable
/// active deadlines are independent of this weekly-schedule choice.
public enum AutomaticScheduleConsentPolicy {
    public static func isEnabled(
        savedConsent: Bool?,
        hasCompletedInitialSetup: Bool,
        flavor: CurfewFlavor
    ) -> Bool {
        guard hasCompletedInitialSetup else { return false }
        return savedConsent ?? (flavor == .production)
    }
}
