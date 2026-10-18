@testable import Curfew
@testable import CurfewKit
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
            ).rawValue == "development"
        )
        #expect(
            CurfewFlavor.resolve(
                environment: [:],
                bundleIdentifier: "studio.hypertext.curfew.studio.dev.widget"
            ).rawValue == "development"
        )
        #expect(
            CurfewFlavor.resolve(
                environment: ["CURFEW_FLAVOR": "studioDevelopment"],
                bundleIdentifier: nil
            ).rawValue == "development"
        )
        #expect(
            CurfewFlavor.resolve(
                environment: ["CURFEW_FLAVOR": "production"],
                bundleIdentifier: "studio.hypertext.curfew.studio.dev"
            ) == .development
        )
    }

    @Test("A bundled Studio helper recovers its flavor when launch environment is missing")
    func bundledHelperUsesContainingAppIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Curfew Dev.app")
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
        ) == .development)
        #expect(CurfewFlavor.resolve(
            environment: ["CURFEW_FLAVOR": "production"],
            bundleIdentifier: nil,
            executableURL: resources.appendingPathComponent("curfew-daemon")
        ) == .development)
    }

    @Test("Two app identities retain production and installed development storage")
    func derivedValues() {
        #expect(CurfewFlavor.allCases == [.production, .development])
        #expect(CurfewFlavor.development.bundleIdentifier == "studio.hypertext.apps.curfew.dev")
        #expect(CurfewFlavor.development.displaySuffix == " Dev")
        #expect(CurfewFlavor.development.storageIdentifierSuffix == ".studio.dev")
        #expect(CurfewFlavor.development.storageDisplaySuffix == " (Studio Dev)")
        #expect(SharedPaths
            .defaultsSuiteName(for: .development) == "studio.hypertext.curfew.studio.dev")
        #expect(SharedPaths
            .widgetAppGroupIdentifier(for: .development) ==
            "group.studio.hypertext.curfew.studio.dev")
        #expect(CurfewServiceEndpoints.forFlavor(.development)
            .keychainService == "studio.hypertext.curfew.account-e2ee.studio.dev")
        #expect(DocketServiceEndpoints.forFlavor(.development)
            .keychainService == "studio.hypertext.curfew.docket.studio.dev")
        #expect(CurfewFlavor.development.daemonLabel == "studio.hypertext.apps.curfew.dev.daemon")
        #expect(CurfewFlavor.production.enforcementPriority > CurfewFlavor.development
            .enforcementPriority)
    }
}
