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
    var sunriseRuntime: SunriseModelRuntime {
        restRuntime.sunrise
    }

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

    /// Uses the configured local schedule, never restriction authority. Test/demo
    /// models have no live runtime unless a test explicitly supplies fake effects.
    func reconcileSunriseWake() async {
        guard !isDemoSession, let coordinator = sunriseWakeCoordinator else {
            sunriseStatus = .disabled
            return
        }
        let preferences = restAppearance
        let plan = SunriseWakePlanner(owner: CurfewFlavor.current.daemonLabel + ".sunrise")
            .presentationPlan(
                schedule: settings.schedule, appearance: preferences,
                at: currentTime, calendar: sunriseCalendar
            )
        await coordinator.reconcile(
            plan: plan, enabled: preferences.sunriseWakeEnabled,
            batteryOptIn: preferences.sunriseOnBatteryEnabled,
            onExternalPower: sunriseOnExternalPower(), now: currentTime
        )
        guard sunriseWakeCoordinator === coordinator, !isDemoSession else { return }
        sunriseStatus = coordinator.status
    }
}
