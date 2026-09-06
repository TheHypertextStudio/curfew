@testable import Curfew
import Foundation
import Testing

struct DaemonPlistTests {
    @Test("Production and development helpers have isolated identities and paths")
    func helperPlistsAreFlavorSpecific() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Curfew/Resources/LaunchDaemons")

        for flavor in CurfewFlavor.allCases {
            let plistURL = resources.appendingPathComponent(flavor.daemonPlistName)
            let data = try Data(contentsOf: plistURL)
            let plist = try #require(
                PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: Any]
            )

            #expect(plist["Label"] as? String == flavor.daemonLabel)
            #expect(plist["BundleProgram"] as? String == "Contents/Resources/curfew-daemon")
            #expect(plist["ProgramArguments"] == nil)
            let environment = try #require(plist["EnvironmentVariables"] as? [String: String])
            #expect(environment["CURFEW_FLAVOR"] == flavor.environmentValue)

            let keepAlive = try #require(plist["KeepAlive"] as? [String: Any])
            let pathState = try #require(keepAlive["PathState"] as? [String: Bool])
            let sentinel = SharedPaths.privilegedApplicationSupport(for: flavor)
                .appendingPathComponent("lockout-active")
            #expect(pathState[sentinel.path] == true)
            #expect(plist["StartInterval"] as? Int == 15)
        }
    }
}
