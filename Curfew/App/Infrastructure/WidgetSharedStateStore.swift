import Foundation
import OSLog

private let widgetSharedStateLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "widget-shared-state"
)

/// Live enforcement snapshot the widget can read between timeline pulls.
/// Mirrors the subset of ``CurfewEvaluation`` the widget renders — phase
/// label, minutes remaining, and whether an extension request is offered —
/// so the timeline doesn't have to re-derive them from raw settings.
public struct WidgetEnforcementSnapshot: Codable, Equatable {
    public var phase: String
    public var minutesRemaining: Int
    public var canRequestExtension: Bool
    public var lockDate: Date?
    public var unlockDate: Date?
    public var updatedAt: Date

    public init(
        phase: String,
        minutesRemaining: Int,
        canRequestExtension: Bool,
        lockDate: Date?,
        unlockDate: Date?,
        updatedAt: Date
    ) {
        self.phase = phase
        self.minutesRemaining = minutesRemaining
        self.canRequestExtension = canRequestExtension
        self.lockDate = lockDate
        self.unlockDate = unlockDate
        self.updatedAt = updatedAt
    }
}

/// Bridges app-owned state into widget-readable storage.
///
/// The main app owns its private `UserDefaults` domain and its activity log
/// (in Application Support). This store mirrors the subset the widget needs —
/// a settings snapshot and a live enforcement snapshot — into the App Group
/// container so the sandboxed widget can read them. These writes only happen
/// when ``FeatureFlags/widgetKitEnabled`` is on, so a default install never
/// touches the shared container (and so never raises the macOS "access data
/// from other apps" prompt).
struct WidgetSharedStateStore {
    let fileManager: FileManager
    let settingsURL: URL
    let enforcementURL: URL

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    init(
        fileManager: FileManager = .default,
        settingsURL: URL = SharedPaths.widgetSettingsSnapshot,
        enforcementURL: URL = SharedPaths.widgetSharedSupport
            .appendingPathComponent("widget-enforcement.json")
    ) {
        self.fileManager = fileManager
        self.settingsURL = settingsURL
        self.enforcementURL = enforcementURL
    }

    /// Persists a JSON snapshot the widget can decode independently of the
    /// app's private `UserDefaults` suite.
    func sync(settings: CurfewSettings) throws {
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
        widgetSharedStateLogger.info("widget settings snapshot synced")
    }

    /// Reads the mirrored settings snapshot, or defaults when no snapshot has
    /// been written yet (first launch / pre-migration installs).
    func loadSettings() -> CurfewSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return .default
        }
        return (try? decoder.decode(CurfewSettings.self, from: data)) ?? .default
    }

    /// Persists the live enforcement snapshot the widget renders. Called on
    /// every phase transition so the timeline ring/label reflect the same
    /// state the menu bar and overlays do, not a stale settings-derived
    /// estimate. Failures are logged but not fatal.
    func sync(enforcement snapshot: WidgetEnforcementSnapshot) throws {
        try fileManager.createDirectory(
            at: enforcementURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: enforcementURL, options: .atomic)
        widgetSharedStateLogger.info("widget enforcement snapshot synced")
    }

    /// Reads the mirrored enforcement snapshot, or `nil` when none has
    /// been written yet — widget treats `nil` as "use settings-derived
    /// default" so a fresh install still renders sensibly.
    func loadEnforcement() -> WidgetEnforcementSnapshot? {
        guard let data = try? Data(contentsOf: enforcementURL) else {
            return nil
        }
        return try? decoder.decode(WidgetEnforcementSnapshot.self, from: data)
    }
}
