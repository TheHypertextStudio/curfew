@testable import Curfew
import Foundation

/// A `CurfewAppModel` wired for status-reporting tests, alongside the fake
/// transport installed into it.
///
/// The transport override is installed before anything can tick, which is what
/// keeps these suites from ever constructing the real `URLSession`-backed
/// transport — no suite run opens a socket.
@MainActor
struct DeviceStatusWiringHarness {
    /// The model under test.
    let model: CurfewAppModel

    /// The transport installed on ``model``, holding every publish it saw.
    let transport: RecordingStatusTransport

    /// The fake presence sensor installed on ``model``. Opens nothing.
    let sensor: FakePresenceSensor

    /// A schedule with every day off, so `tick()` can never evaluate into
    /// `.warning` or `.locked`. Keeps a suite run from putting a lockout
    /// overlay on the screen of whoever is running it.
    static var allDaysOff: WeeklySchedule {
        WeeklySchedule(
            rules: Dictionary(
                uniqueKeysWithValues: Weekday.allCases.map { ($0, DayRule.weekendDefault) }
            )
        )
    }

    /// A schedule that locks the whole day, whatever the wall clock says. The
    /// pattern `LifecycleWiringTests` uses to reach a real `.locked` evaluation
    /// without depending on the time the suite happens to run.
    static var allDayLocked: WeeklySchedule {
        var schedule = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            schedule.rules[weekday] = DayRule(
                isDayOff: false,
                lockMinutes: 0,
                unlockMinutes: 1439
            )
        }
        return schedule
    }

    /// Builds a model over throwaway defaults with a fake transport and a fake
    /// presence sensor.
    ///
    /// - Parameters:
    ///   - reporting: The status-reporting policy to start with. Defaults to
    ///     the shipped one, which is off.
    ///   - schedule: The schedule to evaluate against. Defaults to all days off.
    ///   - outcome: What the fake transport answers every publish with.
    ///   - idleSeconds: How idle the fake HID source reports.
    init(
        reporting: DeviceStatusReportingPolicy = .default,
        schedule: WeeklySchedule? = nil,
        outcome: DeviceStatusPublishOutcome = .accepted,
        idleSeconds: TimeInterval = 600
    ) {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.schedule = schedule ?? Self.allDaysOff
        settings.statusReporting = reporting
        store.save(settings)

        // An isolated deadline file, for the same reason `LifecycleWiringTests`
        // uses one: a durable record left by another run would push the model
        // back into `.locked` on the first tick.
        let deadlineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-status-deadline-\(UUID().uuidString).json")

        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            activityRecorder: NullActivityRecording(),
            idleWatcher: IdleWatcher(
                source: MutableIdleSource(seconds: idleSeconds),
                idleThresholdSeconds: 300
            ),
            lockoutDeadlineStore: LockoutDeadlineStore(recordURL: deadlineURL),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        let transport = RecordingStatusTransport(outcome: outcome)
        model.deviceStatusTransportOverride = transport
        let sensor = FakePresenceSensor(authorization: .authorized)
        model.presenceSensorOverride = sensor

        self.model = model
        self.transport = transport
        self.sensor = sensor
    }

    /// A reporting policy pointed at a usable endpoint, with a device
    /// identifier already minted.
    static func configured(
        heartbeatSeconds: Int = DeviceStatusReportingPolicy.heartbeatFloorSeconds
    ) -> DeviceStatusReportingPolicy {
        DeviceStatusReportingPolicy(
            isEnabled: true,
            baseURL: "https://coordinator.example",
            deviceToken: "test-token",
            deviceID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            heartbeatSeconds: heartbeatSeconds
        )
    }

    /// Waits for every publish the model has started to reach the transport.
    func settle() async {
        await model.deviceStatusReporter.settle()
    }

    /// The `phase` value of the publish at `index`, or `nil` if there is none.
    func publishedPhase(at index: Int) -> String? {
        transport.decodedBody(at: index)?["phase"] as? String
    }
}
