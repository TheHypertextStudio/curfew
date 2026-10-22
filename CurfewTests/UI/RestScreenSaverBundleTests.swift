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
        #expect(companion.executableArchitectures?.contains(
            NSNumber(value: NSBundleExecutableArchitectureARM64)
        ) == true)
        #expect(companion.executableArchitectures?.contains(
            NSNumber(value: NSBundleExecutableArchitectureX86_64)
        ) == true)
    }
}
