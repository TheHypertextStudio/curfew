@testable import CurfewKit
import Testing

struct AutomaticScheduleConsentPolicyTests {
    @Test("Completed Curfew Dev installs require explicit weekly consent")
    func studioDevMigrationStaysOff() {
        #expect(!AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: nil,
            hasCompletedInitialSetup: true,
            flavor: .development
        ))
        #expect(AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: true,
            hasCompletedInitialSetup: true,
            flavor: .development
        ))
        #expect(!AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: false,
            hasCompletedInitialSetup: true,
            flavor: .development
        ))
    }

    @Test("A partially completed first run never arms from orphaned consent")
    func incompleteSetupStaysOff() {
        #expect(!AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: true,
            hasCompletedInitialSetup: false,
            flavor: .development
        ))
        #expect(AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: nil,
            hasCompletedInitialSetup: true,
            flavor: .production
        ))
    }
}
