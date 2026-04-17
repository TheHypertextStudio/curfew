import Foundation

struct OverrideEvent: Codable, Equatable {
    var timestamp: Date
    var deviceName: String
    var reason: String
    var grantedDurationMinutes: Int
}

struct PendingScheduleChange: Codable, Equatable {
    var proposedSchedule: WeeklySchedule
    var requestedAt: Date
    var effectiveAt: Date
    var classification: ScheduleChangeClassification
}

struct CurfewSettings: Codable, Equatable {
    var schedule: WeeklySchedule
    var pendingScheduleChange: PendingScheduleChange?
    var hasCompletedInitialSetup: Bool
    var extensionWeeklyLimit: Int
    var extensionDurationMinutes: Int
    var overrideWeeklyLimit: Int
    var overrideDurationMinutes: Int
    var resetWeekday: Weekday
    var autoShutdownEnabled: Bool
    var autoShutdownDelayMinutes: Int
    var warningIntervals: WarningIntervals

    private enum CodingKeys: String, CodingKey {
        case schedule
        case pendingScheduleChange
        case hasCompletedInitialSetup
        case extensionWeeklyLimit
        case extensionDurationMinutes
        case overrideWeeklyLimit
        case overrideDurationMinutes
        case resetWeekday
        case autoShutdownEnabled
        case autoShutdownDelayMinutes
        case warningIntervals
    }

    init(
        schedule: WeeklySchedule,
        pendingScheduleChange: PendingScheduleChange?,
        hasCompletedInitialSetup: Bool,
        extensionWeeklyLimit: Int,
        extensionDurationMinutes: Int,
        overrideWeeklyLimit: Int,
        overrideDurationMinutes: Int,
        resetWeekday: Weekday,
        autoShutdownEnabled: Bool,
        autoShutdownDelayMinutes: Int,
        warningIntervals: WarningIntervals
    ) {
        self.schedule = schedule
        self.pendingScheduleChange = pendingScheduleChange
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.extensionWeeklyLimit = extensionWeeklyLimit
        self.extensionDurationMinutes = extensionDurationMinutes
        self.overrideWeeklyLimit = overrideWeeklyLimit
        self.overrideDurationMinutes = overrideDurationMinutes
        self.resetWeekday = resetWeekday
        self.autoShutdownEnabled = autoShutdownEnabled
        self.autoShutdownDelayMinutes = autoShutdownDelayMinutes
        self.warningIntervals = warningIntervals.normalized
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schedule = try container.decode(WeeklySchedule.self, forKey: .schedule)
        self.pendingScheduleChange = try container.decodeIfPresent(
            PendingScheduleChange.self,
            forKey: .pendingScheduleChange
        )
        self.hasCompletedInitialSetup = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedInitialSetup
        ) ?? false
        self.extensionWeeklyLimit = try container.decode(Int.self, forKey: .extensionWeeklyLimit)
        self.extensionDurationMinutes = try container.decode(
            Int.self,
            forKey: .extensionDurationMinutes
        )
        self.overrideWeeklyLimit = try container.decode(Int.self, forKey: .overrideWeeklyLimit)
        self.overrideDurationMinutes = try container.decode(
            Int.self,
            forKey: .overrideDurationMinutes
        )
        self.resetWeekday = try container.decode(Weekday.self, forKey: .resetWeekday)
        self.autoShutdownEnabled = try container.decode(Bool.self, forKey: .autoShutdownEnabled)
        self.autoShutdownDelayMinutes = try container.decode(
            Int.self,
            forKey: .autoShutdownDelayMinutes
        )
        self.warningIntervals = try (container.decodeIfPresent(
            WarningIntervals.self,
            forKey: .warningIntervals
        ) ?? .default).normalized
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schedule, forKey: .schedule)
        try container.encodeIfPresent(pendingScheduleChange, forKey: .pendingScheduleChange)
        try container.encode(hasCompletedInitialSetup, forKey: .hasCompletedInitialSetup)
        try container.encode(extensionWeeklyLimit, forKey: .extensionWeeklyLimit)
        try container.encode(extensionDurationMinutes, forKey: .extensionDurationMinutes)
        try container.encode(overrideWeeklyLimit, forKey: .overrideWeeklyLimit)
        try container.encode(overrideDurationMinutes, forKey: .overrideDurationMinutes)
        try container.encode(resetWeekday, forKey: .resetWeekday)
        try container.encode(autoShutdownEnabled, forKey: .autoShutdownEnabled)
        try container.encode(autoShutdownDelayMinutes, forKey: .autoShutdownDelayMinutes)
        try container.encode(warningIntervals.normalized, forKey: .warningIntervals)
    }

    static let `default` = CurfewSettings(
        schedule: .standardNineToFive,
        pendingScheduleChange: nil,
        hasCompletedInitialSetup: false,
        extensionWeeklyLimit: 3,
        extensionDurationMinutes: 15,
        overrideWeeklyLimit: 2,
        overrideDurationMinutes: OverrideRequestPolicy.defaultOverrideDurationMinutes,
        resetWeekday: .monday,
        autoShutdownEnabled: false,
        autoShutdownDelayMinutes: 10,
        warningIntervals: .default
    )
}

final class CurfewSettingsStore {
    private enum Key {
        static let settings = "curfew.settings.v1"
        static let hasShownInitialSetup = "curfew.initialSetupShown.v1"
        static let overrideEvents = "curfew.overrideEvents.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CurfewSettings {
        guard let data = defaults.data(forKey: Key.settings) else {
            return .default
        }
        return (try? decoder.decode(CurfewSettings.self, from: data)) ?? .default
    }

    func save(_ settings: CurfewSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: Key.settings)
    }

    func consumeShouldShowInitialSetup() -> Bool {
        let hasShownInitialSetup = defaults.bool(forKey: Key.hasShownInitialSetup)
        if hasShownInitialSetup {
            return false
        }

        defaults.set(true, forKey: Key.hasShownInitialSetup)
        return true
    }

    func loadOverrideEvents() -> [OverrideEvent] {
        guard let data = defaults.data(forKey: Key.overrideEvents) else {
            return []
        }
        return (try? decoder.decode([OverrideEvent].self, from: data)) ?? []
    }

    func appendOverrideEvent(_ event: OverrideEvent) {
        var events = loadOverrideEvents()
        events.append(event)
        guard let data = try? encoder.encode(events) else {
            return
        }
        defaults.set(data, forKey: Key.overrideEvents)
    }
}
