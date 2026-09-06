@testable import Curfew
import Testing

/// Unit tests for ``CurfewFlavor`` resolution and its derived identifiers — the
/// single source of truth that keeps a development build's data and identity
/// separate from the production install.
struct CurfewFlavorTests {
    @Test("CURFEW_FLAVOR overrides the bundle identifier")
    func environmentOverridesBundle() {
        #expect(
            CurfewFlavor.resolve(
                environment: ["CURFEW_FLAVOR": "development"],
                bundleIdentifier: "studio.hypertext.curfew"
            ) == .development
        )
        #expect(
            CurfewFlavor.resolve(
                environment: ["CURFEW_FLAVOR": "prod"],
                bundleIdentifier: "studio.hypertext.curfew.dev"
            ) == .production
        )
    }

    @Test("A dev segment in the bundle id resolves to development")
    func bundleIdentifierResolution() {
        #expect(
            CurfewFlavor.resolve(environment: [:], bundleIdentifier: "studio.hypertext.curfew")
                == .production
        )
        #expect(
            CurfewFlavor.resolve(environment: [:], bundleIdentifier: "studio.hypertext.curfew.dev")
                == .development
        )
        // The widget's `…dev.widget` bundle id still carries the dev segment.
        #expect(
            CurfewFlavor.resolve(
                environment: [:],
                bundleIdentifier: "studio.hypertext.curfew.dev.widget"
            ) == .development
        )
        #expect(
            CurfewFlavor.resolve(
                environment: [:],
                bundleIdentifier: "studio.hypertext.curfew.widget"
            ) == .production
        )
    }

    @Test("Unknown or missing inputs default to production")
    func defaultsToProduction() {
        #expect(CurfewFlavor.resolve(environment: [:], bundleIdentifier: nil) == .production)
        #expect(
            CurfewFlavor.resolve(environment: ["CURFEW_FLAVOR": "weird"], bundleIdentifier: nil)
                == .production
        )
    }

    @Test("Derived suffixes and precedence match the flavor")
    func derivedValues() {
        #expect(CurfewFlavor.production.identifierSuffix == "")
        #expect(CurfewFlavor.development.identifierSuffix == ".dev")
        #expect(CurfewFlavor.production.displaySuffix == "")
        #expect(CurfewFlavor.development.displaySuffix == " (Dev)")
        #expect(CurfewFlavor.production.daemonPlistName == "studio.hypertext.curfew.daemon.plist")
        #expect(
            CurfewFlavor.development.daemonPlistName
                == "studio.hypertext.curfew.dev.daemon.plist"
        )
        #expect(
            CurfewFlavor.production.enforcementPriority
                > CurfewFlavor.development.enforcementPriority
        )
    }
}
