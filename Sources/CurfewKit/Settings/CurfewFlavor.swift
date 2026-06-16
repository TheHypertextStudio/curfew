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
/// Production is the *neutral* flavor: it carries no suffix, so its identifiers
/// and paths are byte-for-byte what they have always been. Only non-production
/// flavors diverge, which means shipping the flavor split requires zero data
/// migration for existing users.
public enum CurfewFlavor: String, Sendable, CaseIterable {
    /// The signed, notarised build the user installs and runs day to day.
    case production
    /// A local developer build (Debug configuration, bundle id `…curfew.dev`).
    case development

    /// The flavor of the current process, resolved once at first access.
    public static let current: CurfewFlavor = resolve(
        environment: ProcessInfo.processInfo.environment,
        bundleIdentifier: Bundle.main.bundleIdentifier
    )

    /// Pure resolver, exposed so tests can drive every branch without mutating
    /// the real process environment.
    ///
    /// Resolution order:
    /// 1. The `CURFEW_FLAVOR` environment variable. The app exports this when it
    ///    spawns `curfew-ctl` / `curfew-mcp` and embeds it in the daemon plist,
    ///    so helper processes — whose own `Bundle.main` has no bundle id —
    ///    inherit the flavor of the app that launched them.
    /// 2. The running bundle identifier. A `dev` segment (which also covers the
    ///    widget's trailing `.widget`, e.g. `studio.hypertext.curfew.dev.widget`)
    ///    means development.
    /// 3. Production, the safe default.
    public static func resolve(
        environment: [String: String],
        bundleIdentifier: String?
    ) -> CurfewFlavor {
        if let raw = environment["CURFEW_FLAVOR"]?.lowercased(), !raw.isEmpty {
            switch raw {
            case "dev", "development": return .development
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

    /// Dotted suffix appended to reverse-DNS identifiers (App Group, defaults
    /// suite, widget kind). Empty for production so those identifiers — and the
    /// data behind them — never move for an existing install.
    public var identifierSuffix: String {
        switch self {
        case .production: ""
        case .development: ".dev"
        }
    }

    /// Parenthetical appended to human-facing names and the Application Support
    /// directory, e.g. `" (Dev)"`. Empty for production.
    public var displaySuffix: String {
        switch self {
        case .production: ""
        case .development: " (Dev)"
        }
    }

    /// Value propagated to helper subprocesses through the `CURFEW_FLAVOR`
    /// environment variable so they resolve the same flavor as their launcher.
    public var environmentValue: String {
        rawValue
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
