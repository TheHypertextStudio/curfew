import Foundation
import ScreenSaver
import Testing

struct RestScreenSaverBundleTests {
    @Test("The app packages a loadable independently versioned native saver")
    func bundledCompanionLoads() throws {
        let url = try #require(Bundle.main.url(forResource: "Curfew", withExtension: "saver"))
        let companion = try #require(Bundle(url: url))
        #expect(companion.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "BNDL")
        let version = try #require(companion.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String)
        #expect(!version.isEmpty)
        #expect(companion.bundleIdentifier != Bundle.main.bundleIdentifier)
        try companion.loadAndReturnError()
        let principal = try #require(companion.principalClass as? NSObject.Type)
        #expect(principal.isSubclass(of: ScreenSaverView.self))
        // Xcode's test destination builds a native slice. Universal distribution
        // is checked against the actual artifact by verify-release-artifact.sh.
        #if arch(arm64)
            let hostArchitecture = NSBundleExecutableArchitectureARM64
        #elseif arch(x86_64)
            let hostArchitecture = NSBundleExecutableArchitectureX86_64
        #else
            Issue.record("Unsupported native screensaver test architecture")
            return
        #endif
        #expect(companion.executableArchitectures?.contains(
            NSNumber(value: hostArchitecture)
        ) == true)
    }
}
