@testable import CurfewKit
import Testing

struct AutomaticScheduleConsentPolicyTests {
    @Test("Completed Studio Dev installs require explicit weekly consent")
    func studioDevMigrationStaysOff() {
        #expect(!AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: nil,
            hasCompletedInitialSetup: true,
            flavor: .studioDevelopment
        ))
        #expect(AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: true,
            hasCompletedInitialSetup: true,
            flavor: .studioDevelopment
        ))
        #expect(!AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: false,
            hasCompletedInitialSetup: true,
            flavor: .studioDevelopment
        ))
    }

    @Test("A partially completed first run never arms from orphaned consent")
    func incompleteSetupStaysOff() {
        #expect(!AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: true,
            hasCompletedInitialSetup: false,
            flavor: .studioDevelopment
        ))
        #expect(AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: nil,
            hasCompletedInitialSetup: true,
            flavor: .production
        ))
    }
}
