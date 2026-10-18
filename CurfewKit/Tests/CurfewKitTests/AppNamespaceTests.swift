@testable import CurfewKit
import Foundation
import Testing

struct AppNamespaceTests {
    @Test("Studio app identity cannot be overridden by an inherited flavor")
    func studioIdentityWins() {
        for identifier in [
            "studio.hypertext.apps.curfew.dev",
            "studio.hypertext.apps.curfew.studio.dev",
            "studio.hypertext.apps.curfew.studio.dev.widget"
        ] {
            for inherited in ["production", "development"] {
                #expect(CurfewFlavor.resolve(
                    environment: ["CURFEW_FLAVOR": inherited],
                    bundleIdentifier: identifier
                ) == .development)
            }
        }
    }

    @Test("Helper client trust and service identity match the supported app flavor")
    func signedClientUsesTheNewNamespace() throws {
        for flavor in CurfewFlavor.allCases {
            let identity = try #require(DaemonSigningIdentity(
                flavor: flavor, teamIdentifier: "SYNTHETIC1"
            ))
            #expect(identity.clientRequirement.contains(
                "identifier \"studio.hypertext.apps.curfew\(flavor.identifierSuffix)\""
            ))
            let expectedService = flavor == .production
                ? "studio.hypertext.curfew.daemon" : "studio.hypertext.apps.curfew.dev.daemon"
            #expect(identity.machServiceName == expectedService)
        }
    }

    @Test("Renaming the app preserves the existing settings and shared storage domains")
    func storageIdentityStaysStable() {
        for flavor in CurfewFlavor.allCases {
            #expect(SharedPaths.defaultsSuiteName(for: flavor)
                == "studio.hypertext.curfew\(flavor.storageIdentifierSuffix)")
            let expectedWidgetGroup = flavor == .production
                ? "group.studio.hypertext.apps.curfew"
                : "group.studio.hypertext.curfew\(flavor.storageIdentifierSuffix)"
            #expect(SharedPaths.widgetAppGroupIdentifier(for: flavor) == expectedWidgetGroup)
        }
    }

    @Test(
        "Activity history migration reads the historical group rather than the widget destination"
    )
    func activityMigrationKeepsHistoricalSource() {
        let suffix = CurfewFlavor.current.storageIdentifierSuffix
        #expect(SharedPaths.sharedContainerActivityDatabase.path.hasSuffix(
            "/Library/Group Containers/group.studio.hypertext.curfew\(suffix)/Curfew/activity.sqlite3"
        ))
        #expect(SharedPaths.activityDatabase.path.contains("/Library/Application Support/Curfew"))
        if CurfewFlavor.current == .production {
            #expect(SharedPaths.widgetSettingsSnapshot.path.contains(
                "/group.studio.hypertext.apps.curfew/Curfew/widget-settings.json"
            ))
            #expect(SharedPaths.sharedContainerActivityDatabase != SharedPaths.widgetSharedSupport
                .appendingPathComponent("activity.sqlite3"))
        }
    }

    @Test("Old and new owner records retain only their own flavor's priority")
    func ownershipSurvivesTheRename() {
        for flavor in CurfewFlavor.allCases {
            for identifier in [
                flavor.bundleIdentifier,
                SharedPaths.defaultsSuiteName(for: flavor)
            ] {
                let owner = EnforcementOwner(
                    flavor: flavor.rawValue,
                    bundleIdentifier: identifier,
                    displayName: "Curfew", processIdentifier: 1, acquiredAt: Date()
                )
                #expect(owner.hasRecognizedIdentity)
                for other in CurfewFlavor.allCases where other != flavor {
                    let forged = EnforcementOwner(
                        flavor: other.rawValue, bundleIdentifier: owner.bundleIdentifier,
                        displayName: "Curfew", processIdentifier: 1, acquiredAt: Date()
                    )
                    #expect(!forged.hasRecognizedIdentity)
                }
            }
        }
    }
}
