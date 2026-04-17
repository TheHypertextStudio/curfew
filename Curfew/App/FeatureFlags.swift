import Foundation

/// Runtime on/off flags for Curfew modules that ship in-binary but are not yet
/// enabled by default for end users.
///
/// Flags exist so WidgetKit, CloudKit sync, the MCP server, and the privileged
/// helper can land in the repository incrementally without exposing incomplete
/// surfaces. Every flag defaults to `false` so a fresh install behaves as the
/// stable v0.1 schedule + lockout app regardless of what ships alongside.
///
/// Intended usage: the app instantiates a single `FeatureFlags` value during
/// startup (defaulting to ``FeatureFlags/default``) and passes it into
/// `CurfewAppModel`. Consumers of Pro surfaces should also consult
/// `LicenseGate` — flags gate whether the code path is *reachable at all*,
/// whereas licensing gates whether the reachable feature is *unlocked*.
struct FeatureFlags: Equatable {
    /// Whether the WidgetKit extension should be wired into the home-screen
    /// timeline providers. When `false`, the widget target is skipped at runtime.
    var widgetKitEnabled: Bool

    /// Whether CloudKit multi-device sync should run. When `false`, the app
    /// remains local-only. Disabling this also prevents Pro users from
    /// accidentally burning their iCloud quota before the schema stabilises.
    var cloudSyncEnabled: Bool

    /// Whether the `curfew-mcp` MCP server subprocess may be launched by the app.
    /// When `false`, AI-controlled gating is disabled end-to-end — the binary may
    /// still exist on disk but the main app will not spawn or connect to it.
    var mcpServerEnabled: Bool

    /// Whether the root-owned privileged helper should be installed via
    /// `SMAppService`. When `false`, the app relies on its user-space
    /// respawning LaunchAgent for bypass deterrence.
    var privilegedHelperEnabled: Bool

    /// Whether EventKit calendar awareness should run. When `false`, the
    /// `CalendarMonitor` object is never started and EventKit access is
    /// never requested. Also requires `LicenseGate.isProUnlocked`.
    var calendarEnabled: Bool

    /// Safe defaults for first launch: every deferred module off.
    ///
    /// Keep this permanently conservative — turning a flag on in `.default`
    /// will affect *every* Curfew install including fresh ones, so flip flags
    /// individually at the call site where the risk is understood, not here.
    static let `default` = FeatureFlags(
        widgetKitEnabled: false,
        cloudSyncEnabled: false,
        mcpServerEnabled: false,
        privilegedHelperEnabled: false,
        calendarEnabled: false
    )
}
