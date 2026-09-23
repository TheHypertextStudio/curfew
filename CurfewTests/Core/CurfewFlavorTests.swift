@testable import Curfew
import Foundation
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

    @Test("Studio app and widget resolve to an isolated flavor")
    func studioDevelopmentResolution() {
        #expect(
            CurfewFlavor.resolve(
                environment: [:],
                bundleIdentifier: "studio.hypertext.curfew.studio.dev"
            ).rawValue == "studioDevelopment"
        )
        #expect(
            CurfewFlavor.resolve(
                environment: [:],
                bundleIdentifier: "studio.hypertext.curfew.studio.dev.widget"
            ).rawValue == "studioDevelopment"
        )
        #expect(
            CurfewFlavor.resolve(
                environment: ["CURFEW_FLAVOR": "studioDevelopment"],
                bundleIdentifier: nil
            ).rawValue == "studioDevelopment"
        )
        #expect(
            CurfewFlavor.resolve(
                environment: ["CURFEW_FLAVOR": "production"],
                bundleIdentifier: "studio.hypertext.curfew.studio.dev"
            ) == .studioDevelopment
        )
    }

    @Test("A bundled Studio helper recovers its flavor when launch environment is missing")
    func bundledHelperUsesContainingAppIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Curfew Studio Dev.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "studio.hypertext.curfew.studio.dev"
        ], format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))

        #expect(CurfewFlavor.resolve(
            environment: [:],
            bundleIdentifier: nil,
            executableURL: resources.appendingPathComponent("curfew-daemon")
        ) == .studioDevelopment)
        #expect(CurfewFlavor.resolve(
            environment: ["CURFEW_FLAVOR": "production"],
            bundleIdentifier: nil,
            executableURL: resources.appendingPathComponent("curfew-daemon")
        ) == .studioDevelopment)
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
        #expect(CurfewFlavor.studioDevelopment.identifierSuffix == ".studio.dev")
        #expect(CurfewFlavor.studioDevelopment.displaySuffix == " (Studio Dev)")
        #expect(CurfewFlavor.studioDevelopment
            .daemonLabel == "studio.hypertext.curfew.studio.dev.daemon")
        #expect(CurfewFlavor.studioDevelopment.enforcementPriority < CurfewFlavor.development
            .enforcementPriority)
        #expect(BrowserNativeInstallation
            .hostName(for: .studioDevelopment) == "studio.hypertext.curfew.studio.dev.browser")
        #expect(KeychainDeviceAssertionSecretStore
            .service(for: .studioDevelopment) == "studio.hypertext.curfew.studio.dev.coordinator")
        #expect(KeychainDeviceAssertionSecretStore
            .service(for: .studioDevelopment) != KeychainDeviceAssertionSecretStore
            .service(for: .development))
    }

    @Test("Studio development keeps preferences, App Group, and Claude registration separate")
    func studioMutableIdentitiesAreDisjoint() {
        #expect(SharedPaths.defaultsSuiteName(for: .studioDevelopment)
            == "studio.hypertext.curfew.studio.dev")
        #expect(SharedPaths.widgetAppGroupIdentifier(for: .studioDevelopment)
            == "group.studio.hypertext.curfew.studio.dev")
        #expect(ClaudeDesktopRegistration.serverKey(for: .studioDevelopment)
            == "curfew-studio-dev")
        #expect(SharedPaths.defaultsSuiteName(for: .production)
            == "studio.hypertext.curfew")
        #expect(SharedPaths.defaultsSuiteName(for: .development)
            == "studio.hypertext.curfew.dev")
        #expect(ClaudeDesktopRegistration.serverKey(for: .production) == "curfew")
        #expect(ClaudeDesktopRegistration.serverKey(for: .development) == "curfew-dev")
    }
}
