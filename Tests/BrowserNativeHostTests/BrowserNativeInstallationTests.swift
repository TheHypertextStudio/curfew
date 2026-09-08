@testable import CurfewKit
import Foundation
import Testing

struct BrowserNativeInstallationTests {
    @Test func uninstallPreservesManifestReplacedByAnotherFlavor() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let installed = home
            .appendingPathComponent(
                "Production.app/Contents/Resources/studio.hypertext.curfew.browser"
            )
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
}
