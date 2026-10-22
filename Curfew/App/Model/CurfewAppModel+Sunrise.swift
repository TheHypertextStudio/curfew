import CurfewKit
import Foundation
import Observation

/// Observable presentation status with explicitly injected effects; no live power factory.
@Observable
@MainActor
final class SunriseModelRuntime {
    @ObservationIgnored var coordinator: SunriseWakeCoordinator?
    @ObservationIgnored var onExternalPower: () -> Bool = { false }
    @ObservationIgnored var calendar: Calendar = .current
    var status: SunriseWakeCoordinator.Status = .disabled
}

@MainActor
extension CurfewAppModel {
    var sunriseWakeCoordinator: SunriseWakeCoordinator? {
        get { sunriseRuntime.coordinator }
        set { sunriseRuntime.coordinator = newValue }
    }

    var sunriseOnExternalPower: () -> Bool {
        get { sunriseRuntime.onExternalPower }
        set { sunriseRuntime.onExternalPower = newValue }
    }

    var sunriseCalendar: Calendar {
        get { sunriseRuntime.calendar }
        set { sunriseRuntime.calendar = newValue }
    }

    var sunriseStatus: SunriseWakeCoordinator.Status {
        get { sunriseRuntime.status }
        set { sunriseRuntime.status = newValue }
    }

    /// Inert pending actual native behavioral RED for model lifecycle composition.
    /// The eventual implementation must use the configured local schedule, never
    /// restriction authority, and requires an explicitly composed runtime.
    func reconcileSunriseWake() async {}
}
