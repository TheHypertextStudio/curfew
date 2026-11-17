@testable import Curfew
import Foundation
import IOKit.ps
import Testing

/// Whether this Mac has a lid and a battery, behind an injected provider, and
/// the wake requirement each kind of Mac is told.
struct SunriseHardwareTests {
    private struct Provider: SunriseHardwareProviding {
        let clamshell: Bool
        let types: [String]?
        func hasClamshell() -> Bool {
            clamshell
        }

        func powerSourceTypes() -> [String]? {
            types
        }
    }

    @Test("A laptop has a lid and an internal battery")
    func laptop() {
        let hardware = SunriseHardware.resolve(
            Provider(clamshell: true, types: [kIOPSInternalBatteryType])
        )
        #expect(hardware == .laptop)
        #expect(hardware.wakeRequirement == "Needs the Curfew helper and power. Keep the lid open.")
    }

    @Test("A desktop Mac has neither; a UPS is not this Mac's battery")
    func desktop() {
        #expect(SunriseHardware.resolve(Provider(clamshell: false, types: [])) == .desktop)
        #expect(SunriseHardware.resolve(Provider(clamshell: false, types: ["UPS Power Source"]))
            == .desktop)
        #expect(SunriseHardware.desktop.wakeRequirement == "Needs the Curfew helper.")
    }

    @Test("A battery state that cannot be read counts as no battery")
    func unreadable() {
        #expect(!SunriseHardware.resolve(Provider(clamshell: true, types: nil)).hasBattery)
    }
}
