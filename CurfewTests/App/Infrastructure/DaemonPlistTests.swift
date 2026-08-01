@testable import Curfew
import CurfewKit
import Foundation
import Testing

struct DaemonPlistTests {
    @Test("LaunchDaemon plist uses BundleProgram for the embedded helper")
    func plistUsesEmbeddedBundleProgram() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Curfew/Resources/LaunchDaemons/studio.hypertext.curfew.daemon.plist"
            )

        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )

        #expect(plist["Label"] as? String == "studio.hypertext.curfew.daemon")
        #expect(plist["BundleProgram"] as? String == "Contents/Resources/curfew-daemon")
        #expect(plist["ProgramArguments"] == nil)

        #expect(plist["RunAtLoad"] as? Bool == true)
        let machServices = try #require(plist["MachServices"] as? [String: Bool])
        #expect(machServices[PrivilegedDaemonConstants.machServiceName] == true)
        #expect(plist["KeepAlive"] == nil)
    }
}
