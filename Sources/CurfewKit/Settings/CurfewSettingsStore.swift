import Foundation

/// A record of one granted "Convince Me" override.
///
/// Persisted in `UserDefaults` via `CurfewSettingsStore` and exposed on
/// `CurfewAppModel.overrideEvents` so the retrospective and MCP activity
/// tools can surface the full override history for the current device.
public struct OverrideEvent: Codable, Equatable {
    /// When the override was granted.
    public var timestamp: Date

    /// Human-readable name of the device that requested the override.
    /// Captured at grant time so multi-device retrospectives can attribute
    /// events correctly even after the device is renamed.
    public var deviceName: String

    /// The user-supplied justification text (minimum 50 characters as
    /// enforced by ``OverrideRequestPolicy/minimumJustificationCharacters``).
    public var reason: String

    /// How long the override was active, in minutes. Typically
    /// ``OverrideRequestPolicy/defaultOverrideDurationMinutes`` (30) unless
    /// the user has changed their override duration in Settings.
    public var grantedDurationMinutes: Int

    /// Memberwise initialiser. All fields are required — override
    /// events are only created post-confirmation so there's no
    /// degenerate "empty override" state.
    public init(
        timestamp: Date,
        deviceName: String,
        reason: String,
        grantedDurationMinutes: Int
    ) {
        self.timestamp = timestamp
        self.deviceName = deviceName
        self.reason = reason
        self.grantedDurationMinutes = grantedDurationMinutes
    }
}

/// A schedule mutation that has been queued but not yet applied.
///
/// The anti-bypass policy delays schedule changes: stricter changes take
/// effect the next calendar day; weaker changes require a 24-hour cooldown
/// from the moment of the request. This struct captures the full intent of a
/// pending change so the model can apply it when `effectiveAt` arrives.
public struct PendingScheduleChange: Codable, Equatable {
    /// The schedule that will replace the current one once `effectiveAt` passes.
    public var proposedSchedule: WeeklySchedule

    /// When the user submitted this change request.
    public var requestedAt: Date

    /// The earliest moment the proposed schedule may be applied.
    /// Computed by ``SchedulePolicyEngine/earliestEffectiveDate(for:requestedAt:)``.
    public var effectiveAt: Date

    /// Whether this change is stricter, weaker, or equivalent to the
    /// currently active schedule. Determines both the cooldown duration and
    /// the UI copy surfaced in the pending-change banner.
    public var classification: ScheduleChangeClassification

    /// Memberwise initialiser. Typically built by
    /// `SchedulePolicyEngine` + `CurfewAppModel.queueScheduleUpdate`
    /// rather than by callers directly.
    public init(
        proposedSchedule: WeeklySchedule,
        requestedAt: Date,
        effectiveAt: Date,
        classification: ScheduleChangeClassification
    ) {
        self.proposedSchedule = proposedSchedule
        self.requestedAt = requestedAt
        self.effectiveAt = effectiveAt
        self.classification = classification
    }
}

/// The full set of user-editable Curfew preferences.
///
/// Serialised to JSON and stored in `UserDefaults` by
/// ``CurfewSettingsStore``. CloudKit sync pushes and pulls this value as a
/// single `Data` blob — the whole struct is the unit of sync. This makes
/// conflict resolution trivial (last-write-wins on `modifiedAt`) at the
/// cost of granularity; that tradeoff is intentional.
///
/// All fields carry defaults via ``CurfewSettings/default`` so a fresh
/// install or a corrupted store always produces valid settings.
public struct CurfewSettings: Codable, Equatable {
    /// The active weekly lock/unlock schedule. Replaced atomically — pending
    /// changes live in ``pendingScheduleChange`` until their effective date.
    public var schedule: WeeklySchedule

    /// A schedule mutation that has been queued but not yet applied.
    public var pendingScheduleChange: PendingScheduleChange?

    /// Whether the user has completed the first-run onboarding flow.
    /// Enforcement is disarmed until this is `true` so a misconfigured
    /// schedule cannot lock the user out before they have reviewed it.
    public var hasCompletedInitialSetup: Bool

    /// How many extension requests the user may make per week before the
    /// budget is exhausted. Resets on ``resetWeekday``.
    public var extensionWeeklyLimit: Int

    /// Minutes added to the lock time when the user grants themselves an
    /// extension during the warning phase.
    public var extensionDurationMinutes: Int

    /// How many "Convince Me" overrides the user may request per week.
    public var overrideWeeklyLimit: Int

    /// Minutes the device stays unlocked after an override is confirmed.
    /// Defaults to ``OverrideRequestPolicy/defaultOverrideDurationMinutes``.
    public var overrideDurationMinutes: Int

    /// The weekday on which extension and override budgets reset. Defaults
    /// to Monday to align with a typical work week.
    public var resetWeekday: Weekday

    /// When `true` the app will call `shutdown -h` after the auto-shutdown
    /// delay once lockout begins.
    public var autoShutdownEnabled: Bool

    /// How long (in minutes) the app waits after lockout begins before
    /// issuing the shutdown command. Range 1–60; default 10.
    public var autoShutdownDelayMinutes: Int

    /// User-customised thresholds for each warning escalation stage.
    /// Normalised on write so stages are strictly ordered; see
    /// ``WarningIntervals/normalized``.
    public var warningIntervals: WarningIntervals

    /// Whether the MCP control-plane server subprocess may accept write-tool
    /// requests. Toggled in Settings → Integrations.
    public var mcpEnabled: Bool

    /// Whether `curfew-mcp` also binds a loopback-only Streamable HTTP
    /// transport so remote MCP clients (editors over SSH, multi-process
    /// setups) can reach the tool registry. Off by default — the primary
    /// stdio transport covers every in-the-box host.
    public var mcpHTTPEnabled: Bool

    /// Port the HTTP transport listens on when `mcpHTTPEnabled` is true.
    /// Defaults to 9847 per plan.md §9.1.
    public var mcpHTTPPort: Int

    /// Which applications enforcement must never terminate, and how long a
    /// destructive action may wait for delegated work that is mid-flight.
    /// See ``ProtectedWorkPolicy``.
    public var protectedWork: ProtectedWorkPolicy

    /// Whether Curfew may use the camera to tell presence from absence, and
    /// how it nudges a user who is present but idle. Camera off by default;
    /// see ``PresenceDetectionPolicy``.
    public var presence: PresenceDetectionPolicy

    /// Whether Curfew publishes this device's enforcement status to a
    /// curfew-sync coordinator, and where. Off with no endpoint by default;
    /// see ``DeviceStatusReportingPolicy``.
    public var statusReporting: DeviceStatusReportingPolicy

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
        case mcpEnabled
        case mcpHTTPEnabled
        case mcpHTTPPort
        case protectedWork
        case presence
        case statusReporting
    }

    /// Memberwise initialiser. `warningIntervals` is normalised on
    /// assignment so out-of-range values written directly to the
    /// struct (e.g. in tests) are corrected. `mcpHTTPEnabled` /
    /// `mcpHTTPPort` default to safe off so a persisted value from a
    /// v0.1 client (which didn't emit them) round-trips correctly.
    public init(
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
        warningIntervals: WarningIntervals,
        mcpEnabled: Bool,
        mcpHTTPEnabled: Bool = false,
        mcpHTTPPort: Int = 9847,
        protectedWork: ProtectedWorkPolicy = .default,
        presence: PresenceDetectionPolicy = .default,
        statusReporting: DeviceStatusReportingPolicy = .default
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
        self.mcpEnabled = mcpEnabled
        self.mcpHTTPEnabled = mcpHTTPEnabled
        self.mcpHTTPPort = mcpHTTPPort
        self.protectedWork = protectedWork
        self.presence = presence
        self.statusReporting = statusReporting
    }

    /// Custom decoder so pre-existing persisted settings (v0.1 payloads
    /// without `mcpHTTPEnabled`, `mcpHTTPPort`, and `pendingScheduleChange`
    /// in some cases) upgrade cleanly. Every new field uses
    /// `decodeIfPresent` so the upgrade path stays one-way-safe.
    public init(from decoder: Decoder) throws {
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
        self.mcpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? true
        self.mcpHTTPEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .mcpHTTPEnabled
        ) ?? false
        self.mcpHTTPPort = try container.decodeIfPresent(
            Int.self,
            forKey: .mcpHTTPPort
        ) ?? 9847
        self.protectedWork = try container.decodeIfPresent(
            ProtectedWorkPolicy.self,
            forKey: .protectedWork
        ) ?? .default
        // Absent on every payload written before presence detection shipped,
        // and `.default` has the camera off — so an upgrade cannot turn a
        // camera on, and neither can a corrupted or truncated blob.
        self.presence = try container.decodeIfPresent(
            PresenceDetectionPolicy.self,
            forKey: .presence
        ) ?? .default
        // Absent on every payload written before status reporting shipped, and
        // `.default` is off with no endpoint — so an upgrade cannot start
        // talking to a coordinator, and neither can a truncated blob.
        self.statusReporting = try container.decodeIfPresent(
            DeviceStatusReportingPolicy.self,
            forKey: .statusReporting
        ) ?? .default
    }

    /// Encodes to JSON. `warningIntervals` is normalised before encoding so
    /// any out-of-range values written directly to the struct (e.g. in tests)
    /// are corrected on the way out rather than persisted.
    public func encode(to encoder: Encoder) throws {
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
        try container.encode(mcpEnabled, forKey: .mcpEnabled)
        try container.encode(mcpHTTPEnabled, forKey: .mcpHTTPEnabled)
        try container.encode(mcpHTTPPort, forKey: .mcpHTTPPort)
        try container.encode(protectedWork, forKey: .protectedWork)
        try container.encode(presence, forKey: .presence)
        try container.encode(statusReporting, forKey: .statusReporting)
    }

    /// Factory defaults for a fresh install: 9-to-5 schedule, 3 × 15 min
    /// extensions/week, 2 × 30 min overrides/week, Monday reset, auto-
    /// shutdown off, canonical warning intervals, MCP on, loopback HTTP
    /// off, camera presence detection off, status reporting off with no
    /// coordinator endpoint. Consumed by
    /// `CurfewSettingsStore.load()` when the `UserDefaults` key is absent.
    public static let `default` = CurfewSettings(
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
        warningIntervals: .default,
        mcpEnabled: true
    )
}

/// Reads and writes ``CurfewSettings`` and auxiliary records to
/// `UserDefaults`.
///
/// The store is the single source of truth for persisted settings within the
/// process. `CurfewAppModel` holds the live in-memory copy; the store is
/// only touched on load (startup), save (mutation), and explicit reads
/// (`loadOverrideEvents`).
///
/// `UserDefaults` was chosen over a plist file to stay in the same storage
/// location already read by `curfew-ctl` and `curfew-mcp` via
/// `SharedPaths.defaultsSuiteName`. If the storage layer ever needs to
/// change, this is the only class that needs updating.
public final class CurfewSettingsStore {
    private enum Key {
        static let settings = "curfew.settings.v1"
        static let hasShownInitialSetup = "curfew.initialSetupShown.v1"
        static let overrideEvents = "curfew.overrideEvents.v1"
        static let reflectionConfig = "curfew.reflectionConfig.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a store backed by `defaults`. Pass a custom suite in tests
    /// to avoid polluting `UserDefaults.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The suite this store reads and writes.
    ///
    /// Exposed so sibling persistence that must live in the *same* suite can
    /// find it without a second injection point — currently
    /// ``DeviceStatusVersionCounter``, whose monotonicity guarantee is only
    /// worth anything if a test's isolated suite isolates it too.
    public var storageDefaults: UserDefaults {
        defaults
    }

    /// Returns the stored settings, or ``CurfewSettings/default`` when no
    /// settings have been saved yet or decoding fails.
    public func load() -> CurfewSettings {
        guard let data = defaults.data(forKey: Key.settings) else {
            return .default
        }
        return (try? decoder.decode(CurfewSettings.self, from: data)) ?? .default
    }

    /// Persists `settings` as JSON. Silently no-ops on encoding failure
    /// (should never happen in practice for a known-good `Codable` type).
    public func save(_ settings: CurfewSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: Key.settings)
    }

    /// Returns `true` and records the flag on first call; returns `false` on
    /// all subsequent calls. Used to decide whether to auto-open the
    /// Getting Started window at launch.
    public func consumeShouldShowInitialSetup() -> Bool {
        let hasShownInitialSetup = defaults.bool(forKey: Key.hasShownInitialSetup)
        if hasShownInitialSetup {
            return false
        }

        defaults.set(true, forKey: Key.hasShownInitialSetup)
        return true
    }

    /// Returns all persisted override events, or `[]` when none have been
    /// recorded yet or decoding fails.
    public func loadOverrideEvents() -> [OverrideEvent] {
        guard let data = defaults.data(forKey: Key.overrideEvents) else {
            return []
        }
        return (try? decoder.decode([OverrideEvent].self, from: data)) ?? []
    }

    /// Appends `event` to the persisted override log. The full array is
    /// read, mutated, and written back on every call — acceptable given the
    /// low write frequency (at most a few per week in typical usage).
    public func appendOverrideEvent(_ event: OverrideEvent) {
        var events = loadOverrideEvents()
        events.append(event)
        guard let data = try? encoder.encode(events) else {
            return
        }
        defaults.set(data, forKey: Key.overrideEvents)
    }

    /// Returns the stored reflection configuration, or
    /// ``ReflectionConfiguration/default`` when none has been saved yet or
    /// decoding fails. Read by `CurfewAppModel` (to gate prompting and render
    /// the prompts) and by the reflection settings panel (to edit them).
    public func loadReflectionConfiguration() -> ReflectionConfiguration {
        guard let data = defaults.data(forKey: Key.reflectionConfig) else {
            return .default
        }
        return (try? decoder.decode(ReflectionConfiguration.self, from: data)) ?? .default
    }

    /// Persists `configuration` as JSON. Silently no-ops on encoding failure
    /// (should never happen for a known-good `Codable` type).
    public func saveReflectionConfiguration(_ configuration: ReflectionConfiguration) {
        guard let data = try? encoder.encode(configuration) else {
            return
        }
        defaults.set(data, forKey: Key.reflectionConfig)
    }
}
