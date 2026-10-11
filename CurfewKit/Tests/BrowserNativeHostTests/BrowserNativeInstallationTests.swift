@testable import CurfewKit
import Foundation
import Testing

struct BrowserNativeInstallationTests {
    @Test func developmentAndProductionInstallAndUninstallIndependently() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let production = home.appendingPathComponent("Production.app/helper")
        let development = home.appendingPathComponent("Development.app/helper")
        try createExecutable(at: production)
        try createExecutable(at: development)
        let productionManifest = try BrowserNativeInstallation.install(
            extensionID: "abcdefghijklmnopabcdefghijklmnop", executable: production, home: home,
            flavor: .production
        )
        let productionData = try Data(contentsOf: productionManifest)
        let developmentManifest = try BrowserNativeInstallation.install(
            extensionID: BrowserNativeInstallation.developmentExtensionID, executable: development,
            home: home, flavor: .development
        )
        #expect(productionManifest.lastPathComponent == "studio.hypertext.curfew.browser.json")
        #expect(developmentManifest.lastPathComponent == "studio.hypertext.curfew.dev.browser.json")
        #expect(try Data(contentsOf: productionManifest) == productionData)
        let object = try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: developmentManifest)) as? [String: Any])
        #expect(object["name"] as? String == "studio.hypertext.curfew.dev.browser")
        try BrowserNativeInstallation.removeManifest(
            home: home,
            executable: development,
            flavor: .development
        )
        #expect(!FileManager.default.fileExists(atPath: developmentManifest.path))
        #expect(try Data(contentsOf: productionManifest) == productionData)
        let productionStore = BrowserNativeStore(directory: BrowserNativeInstallation
            .browserDirectory(
                home: home,
                flavor: .production
            ))
        #expect(try productionStore.isActive())
    }

    @Test(arguments: ["missing", "directory", "symlink", "nonExecutable"])
    func installationRejectsUnsafeExecutable(kind: String) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let executable = home.appendingPathComponent("helper")
        switch kind {
        case "directory":
            try FileManager.default.createDirectory(
                at: executable,
                withIntermediateDirectories: true
            )
        case "symlink":
            try FileManager.default.createSymbolicLink(
                at: executable,
                withDestinationURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        case "nonExecutable":
            try Data("not executable".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: executable.path
            )
        default: break
        }
        #expect(throws: (any Error).self) {
            try BrowserNativeInstallation.install(
                extensionID: BrowserNativeInstallation.developmentExtensionID,
                executable: executable,
                home: home
            )
        }
        #expect(!FileManager.default
            .fileExists(atPath: BrowserNativeInstallation.manifestURL(home: home).path))
    }

    @Test func uninstallPreservesManifestReplacedByAnotherFlavor() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let installed = home
            .appendingPathComponent(
                "Production.app/Contents/Resources/studio.hypertext.curfew.browser"
            )
        try createExecutable(at: installed)
        let manifest = try BrowserNativeInstallation.install(
            extensionID: BrowserNativeInstallation.developmentExtensionID,
            executable: installed,
            home: home
        )
        try BrowserNativeInstallation.removeManifest(
            home: home,
            executable: home
                .appendingPathComponent(
                    "Development.app/Contents/Resources/studio.hypertext.curfew.browser"
                )
        )
        #expect(FileManager.default.fileExists(atPath: manifest.path))
    }

    @Test func installationPinsOriginAndAbsoluteExecutable() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let id = "abcdefghijklmnopabcdefghijklmnop"
        let executable = home
            .appendingPathComponent("Curfew.app/Contents/Resources/studio.hypertext.curfew.browser")
        try createExecutable(at: executable)
        let manifestURL = try BrowserNativeInstallation.install(
            extensionID: id,
            executable: executable,
            home: home
        )
        #expect(manifestURL.path
            .hasSuffix(
                "Library/Application Support/Google/Chrome/NativeMessagingHosts/studio.hypertext.curfew.browser.json"
            ))
        let object = try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        #expect(object["path"] as? String == executable.path)
        #expect(object["allowed_origins"] as? [String] == ["chrome-extension://\(id)/"])
        #expect(try BrowserNativeInstallation.validateCaller(
            "chrome-extension://\(id)/",
            extensionID: id
        ))
        #expect(throws: (any Error).self) {
            try BrowserNativeInstallation.validateCaller(
                "chrome-extension://pppppppppppppppppppppppppppppppp/",
                extensionID: id
            )
        }
        try BrowserNativeInstallation.removeManifest(home: home, executable: executable)
        #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
    }

    @Test(arguments: [
        "",
        "*",
        "REPLACE_ME",
        "abcdefghijklmnopabcdefghijklmnox",
        "abcdefghijklmnopabcdefghijklmnop/"
    ])
    func rejectsInvalidIDs(id: String) {
        #expect(throws: (any Error).self) { try BrowserNativeInstallation.origin(extensionID: id) }
    }

    @Test func developmentIdentityMatchesItsPublicKey() throws {
        #expect(try BrowserNativeInstallation
            .extensionID(publicKey: BrowserNativeInstallation.developmentPublicKey) ==
            BrowserNativeInstallation.developmentExtensionID)
        #expect(try BrowserNativeInstallation
            .origin(extensionID: BrowserNativeInstallation.developmentExtensionID)
            .hasPrefix("chrome-extension://"))
    }

    private func createExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
