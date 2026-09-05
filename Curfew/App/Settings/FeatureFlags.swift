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
    ///
    /// Many tests assert against this all-off shape; do not change it.
    static let `default` = FeatureFlags(
        widgetKitEnabled: false,
        cloudSyncEnabled: false,
        mcpServerEnabled: false,
        privilegedHelperEnabled: false,
        calendarEnabled: false
    )

    /// Conservative initial-release configuration.
    ///
    /// The local MCP server remains available so user-approved agent access to
    /// schedules, curfews and user-authored reflections ships as advertised.
    /// CloudKit, WidgetKit and Calendar stay disabled until each has passed its
    /// provisioning validation. Remote MCP requires the privileged helper, so
    /// shipping builds expose its installation/status UI and heartbeat path.
    /// Selected by ``resolved`` when the binary is compiled with the
    /// `RELEASE_FEATURES` condition. Debug / test builds never see this, so
    /// `.default` remains the value exercised by the unit-test host.
    static let shipping = FeatureFlags(
        widgetKitEnabled: false,
        cloudSyncEnabled: false,
        mcpServerEnabled: true,
        privilegedHelperEnabled: true,
        calendarEnabled: false
    )

    /// The flag set the running app should use, chosen from the build
    /// configuration with a developer escape hatch.
    ///
    /// Returns ``shipping`` when the binary is built with the
    /// `RELEASE_FEATURES` compilation condition, otherwise ``default``.
    /// Setting the environment variable `CURFEW_CONSERVATIVE_FLAGS=1` forces
    /// ``default`` even under `RELEASE_FEATURES`, mirroring the Debug-only
    /// `CURFEW_SKIP_ENFORCEMENT` escape hatch used by ``CurfewLaunchBehavior``
    /// so a release binary can be run with every deferred module off when
    /// diagnosing a regression.
    static var resolved: FeatureFlags {
        #if RELEASE_FEATURES
            let releaseFeaturesEnabled = true
        #else
            let releaseFeaturesEnabled = false
        #endif
        return resolve(
            releaseFeaturesEnabled: releaseFeaturesEnabled,
            environment: ProcessInfo.processInfo.environment
        )
    }

    /// Pure resolution policy behind ``resolved``, split out so it can be
    /// unit-tested without depending on the build configuration or the live
    /// process environment.
    ///
    /// - Parameters:
    ///   - releaseFeaturesEnabled: whether the `RELEASE_FEATURES` condition is
    ///     compiled in.
    ///   - environment: the process environment to consult for the escape hatch.
    static func resolve(
        releaseFeaturesEnabled: Bool,
        environment: [String: String]
    ) -> FeatureFlags {
        guard releaseFeaturesEnabled else { return .default }
        if environment["CURFEW_CONSERVATIVE_FLAGS"] == "1" {
            return .default
        }
        return .shipping
    }
}

/// Deferred integrations that should only surface in the UI when the
/// current build actually enables them.
enum DeferredFeaturePanel: String, CaseIterable, Identifiable {
    case widgetKit
    case calendar
    case cloudSync
    case privilegedHelper

    var id: String {
        rawValue
    }

    static func visible(for flags: FeatureFlags) -> [DeferredFeaturePanel] {
        var panels: [DeferredFeaturePanel] = []
        if flags.widgetKitEnabled {
            panels.append(.widgetKit)
        }
        if flags.calendarEnabled {
            panels.append(.calendar)
        }
        if flags.cloudSyncEnabled {
            panels.append(.cloudSync)
        }
        if flags.privilegedHelperEnabled {
            panels.append(.privilegedHelper)
        }
        return panels
    }
}
