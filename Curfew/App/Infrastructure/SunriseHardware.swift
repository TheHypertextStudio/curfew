import Foundation
import IOKit
import IOKit.ps

/// What this Mac physically has that matters to a Sunrise wake: a lid that
/// can be closed, and a battery it can run on. A Mac mini, Studio, iMac or
/// Mac Pro has neither, so nothing about power or a lid applies to it.
nonisolated struct SunriseHardware: Equatable, Sendable {
    let hasLid: Bool
    let hasBattery: Bool

    static let laptop = SunriseHardware(hasLid: true, hasBattery: true)
    static let desktop = SunriseHardware(hasLid: false, hasBattery: false)

    /// What the wake needs on this Mac, as one sentence.
    var wakeRequirement: String {
        let needs = hasBattery ? "Needs the Curfew helper and power." : "Needs the Curfew helper."
        return hasLid ? "\(needs) Keep the lid open." : needs
    }
}

/// Reads the two facts. Injected so both kinds of Mac are tested.
nonisolated protocol SunriseHardwareProviding: Sendable {
    /// Whether the power management root reports a clamshell state, which
    /// only a Mac with a built-in display and a lid has.
    func hasClamshell() -> Bool
    /// The type of each power source, such as `kIOPSInternalBatteryType`.
    /// `nil` when the power sources cannot be read.
    func powerSourceTypes() -> [String]?
}

extension SunriseHardware {
    /// A battery counts only when a power source says it is an internal
    /// battery; a state that cannot be read counts as no battery.
    static func resolve(_ provider: any SunriseHardwareProviding) -> SunriseHardware {
        let battery = provider.powerSourceTypes()?.contains(kIOPSInternalBatteryType) ?? false
        return SunriseHardware(hasLid: provider.hasClamshell(), hasBattery: battery)
    }
}

/// The live IOKit and power source queries. Read-only.
nonisolated struct IOKitSunriseHardwareProvider: SunriseHardwareProviding {
    func hasClamshell() -> Bool {
        let root = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain")
        )
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(
            root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )
        return state != nil
    }

    func powerSourceTypes() -> [String]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        return list.compactMap { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any]
            else { return nil }
            return description[kIOPSTypeKey] as? String
        }
    }
}
