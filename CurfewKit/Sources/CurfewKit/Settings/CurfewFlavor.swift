import Foundation

/// Identifies which build flavor of Curfew is running so every derived
/// identifier — App Group container, `UserDefaults` suite, Application Support
/// directory, widget kind — resolves to a flavor-specific value.
///
/// The point is isolation without disturbance: a developer build keeps its own
/// settings, schedule, and activity history so it can never read from or write
/// to the production install the user relies on day to day. Enforcement is the
/// deliberate exception — see ``enforcementPriority`` and the cross-flavor
/// ownership lock — because only one Curfew may ever lock the user out at once.
///
/// Production carries no suffix. Signed app identities use the Studio apps
/// namespace; established storage paths and service identifiers remain stable
/// so changing the app identity does not relocate existing data or deadlines.
public nonisolated enum CurfewFlavor: String, Sendable, CaseIterable {
    /// The signed, notarised build the user installs and runs day to day.
    case production
    /// The Studio-signed development build, installed as Curfew Dev.
    case development

    /// The flavor of the current process, resolved once at first access.
    public static let current: CurfewFlavor = resolve(
        environment: ProcessInfo.processInfo.environment,
        bundleIdentifier: Bundle.main.bundleIdentifier,
        executableURL: Bundle.main.executableURL
    )

    /// Pure resolver, exposed so tests can drive every branch without mutating
    /// the real process environment.
    ///
    /// Resolution order:
    /// 1. A recognized development app or widget bundle identity. This must not be
    ///    overridden by an inherited development or production environment.
    /// 2. The `CURFEW_FLAVOR` environment variable. The app exports this when it
    ///    spawns `curfew-ctl` / `curfew-mcp` and embeds it in the daemon plist,
    ///    so helper processes — whose own `Bundle.main` has no bundle id —
    ///    inherit the flavor of the app that launched them.
    /// 3. The running bundle identifier. A `dev` segment (which also covers the
    ///    widget's trailing `.widget`, e.g. `studio.hypertext.curfew.dev.widget`)
    ///    means development.
    /// 4. Production, the safe default.
    public static func resolve(
        environment: [String: String],
        bundleIdentifier: String?,
        executableURL: URL? = nil
    ) -> CurfewFlavor {
        if isDevelopmentBundle(bundleIdentifier) ||
            isDevelopmentBundle(containingAppIdentifier(for: executableURL)) {
            return .development
        }
        if let raw = environment["CURFEW_FLAVOR"]?.lowercased(), !raw.isEmpty {
            switch raw {
            case "dev", "development": return .development
            case "studiodevelopment": return .development
            case "prod", "production": return .production
            default: break
            }
        }
        if let identifier = bundleIdentifier,
           identifier.split(separator: ".").contains("dev") {
            return .development
        }
        return .production
    }

    private static func isDevelopmentBundle(_ identifier: String?) -> Bool {
        [
            "studio.hypertext.apps.curfew.dev",
            "studio.hypertext.apps.curfew.dev.widget",
            "studio.hypertext.apps.curfew.studio.dev",
            "studio.hypertext.apps.curfew.studio.dev.widget",
            "studio.hypertext.curfew.studio.dev",
            "studio.hypertext.curfew.studio.dev.widget"
        ].contains(identifier ?? "")
    }

    private static func containingAppIdentifier(for executableURL: URL?) -> String? {
        guard var ancestor = executableURL?.deletingLastPathComponent() else { return nil }
        while ancestor.path != "/" {
            if ancestor.pathExtension == "app" {
                return Bundle(url: ancestor)?.bundleIdentifier
            }
            ancestor.deleteLastPathComponent()
        }
        return nil
    }

    /// Signed app identity. Storage and service names retain their established
    /// identifiers so existing tester data is not relocated by this rename.
    public var bundleIdentifier: String {
        "studio.hypertext.apps.curfew\(identifierSuffix)"
    }

    /// Canonical app identity suffix. Storage and service identities use
    /// storageIdentifierSuffix independently for upgrade compatibility.
    public var identifierSuffix: String {
        switch self {
        case .production: ""
        case .development: ".dev"
        }
    }

    /// Human-facing app suffix. Never use this to derive a data directory.
    public var displaySuffix: String {
        switch self {
        case .production: ""
        case .development: " Dev"
        }
    }

    /// Compatibility identities of the installed development store. These are
    /// deliberately independent of the app name and canonical bundle suffix.
    public var storageIdentifierSuffix: String {
        self == .production ? "" : ".studio.dev"
    }

    public var storageDisplaySuffix: String {
        self == .production ? "" : " (Studio Dev)"
    }

    /// Value propagated to helper subprocesses through the `CURFEW_FLAVOR`
    /// environment variable so they resolve the same flavor as their launcher.
    public var environmentValue: String {
        rawValue
    }

    /// LaunchDaemon identity for this flavor. Development must never replace
    /// the production helper registration while staging is under test.
    public var daemonLabel: String {
        self == .production ? "studio.hypertext.curfew.daemon" : "studio.hypertext.apps.curfew.dev.daemon"
    }

    public var daemonPlistName: String {
        "\(daemonLabel).plist"
    }

    /// Precedence for the single-enforcer lock. The production install is the
    /// curfew the user actually depends on, so it always wins: a development
    /// build can never block a real curfew, and it steps aside the moment
    /// production needs to enforce. Higher wins.
    public var enforcementPriority: Int {
        switch self {
        case .production: 100
        case .development: 0
        }
    }
}
