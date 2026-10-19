@testable import CurfewKit
import Testing

struct AutomaticScheduleConsentPolicyTests {
    @Test("A signed development install does not arm its weekly schedule without consent")
    func developmentInstallDefaultsToRemoteOnly() {
        let flavor = CurfewFlavor.resolve(
            environment: [:],
            bundleIdentifier: "studio.hypertext.apps.curfew.dev"
        )
        #expect(flavor == .development)
        #expect(!AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: nil,
            hasCompletedInitialSetup: true,
            flavor: flavor
        ))
        #expect(AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: true,
            hasCompletedInitialSetup: true,
            flavor: flavor
        ))
    }

    @Test("A signed development bundle cannot inherit production schedule behavior")
    func developmentIdentityOverridesProductionEnvironment() {
        for bundleIdentifier in [
            "studio.hypertext.curfew.dev",
            "studio.hypertext.apps.curfew.dev"
        ] {
            let flavor = CurfewFlavor.resolve(
                environment: ["CURFEW_FLAVOR": "production"],
                bundleIdentifier: bundleIdentifier
            )
            #expect(flavor == .development)
            #expect(!AutomaticScheduleConsentPolicy.isEnabled(
                savedConsent: nil,
                hasCompletedInitialSetup: true,
                flavor: flavor
            ))
        }
    }

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
