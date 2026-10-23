/// Registration requires a production process or an explicitly opted-in staging bundle.
public enum SupervisorRegistrationPolicy {
    public static func allowsRegistration(
        debugBuild: Bool, explicitStagingOptIn: Bool, testHost: Bool, demo: Bool
    ) -> Bool {
        !testHost && !demo && (!debugBuild || explicitStagingOptIn)
    }
}
