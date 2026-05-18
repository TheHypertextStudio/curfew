import Foundation
import OSLog

private let lockdownLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "persistent-lockdown"
)

/// Abstracts over `launchctl` process invocation so tests can assert which
/// sub-commands a given `PersistentLockdown` *would* run without actually
/// mutating the developer's `launchd` state.
protocol LaunchctlRunning {
    /// Runs `/bin/launchctl <arguments...>` synchronously. Implementations
    /// throw on non-zero exit so callers can log and continue.
    func run(arguments: [String]) throws
}

/// Production `LaunchctlRunning`. Spawns `/bin/launchctl` via `Process`.
///
/// Uses the absolute path so `PATH` tampering can't redirect the call to
/// a malicious binary — important because the call is made from an app
/// that may already hold accessibility entitlements.
struct SystemLaunchctl: LaunchctlRunning {
    /// Executes `/bin/launchctl <arguments>` synchronously and throws
    /// `PersistentLockdownError.launchctlFailed` on a non-zero exit.
    func run(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw PersistentLockdownError.launchctlFailed(
                arguments: arguments,
                status: process.terminationStatus
            )
        }
    }
}

/// Errors surfaced by ``PersistentLockdown``. Kept narrow — callers treat
/// any failure as "couldn't install; proceed without the deterrent."
enum PersistentLockdownError: Error, Equatable {
    /// `launchctl` exited with non-zero status.
    case launchctlFailed(arguments: [String], status: Int32)
}

/// Abstracts the user-space respawn-on-kill deterrent so the app model can
/// drive install / arm / disarm against either ``PersistentLockdown``
/// (production) or ``NoOpRespawnGuard`` (debug builds and unit tests).
///
/// The seam matches the shape of ``ShutdownControlling`` so the model can
/// inject test doubles using the same convenience-init pattern.
protocol RespawnGuardControlling: AnyObject {
    /// Writes the plist and loads the LaunchAgent. Idempotent.
    func install() throws

    /// Unloads the LaunchAgent and removes the plist. Safe to call when not
    /// installed.
    func uninstall() throws

    /// Creates the trigger file so launchd respawns the app on exit. Called
    /// on ``EnforcementPhase/locked`` entry.
    func arm() throws

    /// Removes the trigger file so launchd stops respawning. Called on
    /// ``EnforcementPhase/locked`` exit.
    func disarm() throws
}

/// Null-object conformer used by debug builds (so launchd state isn't
/// polluted on every developer run) and by tests that don't exercise the
/// respawn deterrent. All methods are no-ops.
final class NoOpRespawnGuard: RespawnGuardControlling {
    /// Public init so tests and the debug-build path can construct one
    /// without going through a factory.
    init() {}
    func install() throws {}
    func uninstall() throws {}
    func arm() throws {}
    func disarm() throws {}
}

/// User-space bypass deterrent: installs a `LaunchAgent` whose
/// `KeepAlive.PathState` watches a trigger file. When the file exists
/// (lockout is active) launchd ensures Curfew stays running; if the
/// user kills Curfew, launchd respawns it within a second or two. When
/// the file is absent (normal operation) launchd leaves Curfew alone,
/// so quitting from the menu works as expected.
///
/// This is the v0.1 shim. A hardened v0.2 will move enforcement into a
/// root-owned privileged helper via `SMAppService`, but the mental model
/// (a trigger file gates a respawn policy) carries over — the v0.2
/// helper will watch the same path with a tighter TOCTOU guarantee.
///
/// **Not enabled by default**: v0.1 ships the class and its tests but
/// does not automatically install the agent. Users who want respawn-on-
/// kill must explicitly opt in. Debug builds should never install —
/// launchd respawning a debugger-attached process is painful.
@MainActor
final class PersistentLockdown: RespawnGuardControlling {
    /// `Label` used in the generated plist and as the plist filename.
    /// Kept stable across versions — changing it would leave stale
    /// agents registered under the old label on upgraded installs.
    static let agentLabel = "studio.hypertext.curfew.lockdown"

    /// Where the generated plist lives on disk, e.g.
    /// `~/Library/LaunchAgents/studio.hypertext.curfew.lockdown.plist`.
    let launchAgentsDirectory: URL

    /// Path to the trigger file. While this file exists, launchd
    /// ensures Curfew is running; when it's absent, launchd leaves
    /// Curfew alone.
    let triggerPath: URL

    /// Absolute path to the Curfew executable that launchd will spawn
    /// if the current process dies. Typically
    /// `/Applications/Curfew.app/Contents/MacOS/Curfew`.
    ///
    /// **Must be a trusted path.** Whatever binary lives here will be
    /// run by launchd on every respawn, with the user's privileges. The
    /// caller is responsible for passing the real Curfew binary — don't
    /// derive this from user input or environment variables.
    let curfewExecutableURL: URL

    /// Process runner — injected for testability.
    private let launchctl: LaunchctlRunning

    /// Creates a lockdown controller. All URL parameters are explicit so
    /// tests can point at a temp directory; `launchctl` defaults to the
    /// production `SystemLaunchctl` and is overridden in tests to assert
    /// the emitted argument list without mutating real `launchd` state.
    init(
        launchAgentsDirectory: URL,
        triggerPath: URL,
        curfewExecutableURL: URL,
        launchctl: LaunchctlRunning = SystemLaunchctl()
    ) {
        self.launchAgentsDirectory = launchAgentsDirectory
        self.triggerPath = triggerPath
        self.curfewExecutableURL = curfewExecutableURL
        self.launchctl = launchctl
    }

    /// Production factory: wires the user's `~/Library/LaunchAgents`, the
    /// app's shared support directory for the trigger file, and the running
    /// bundle's executable URL. Used by ``CurfewAppModel``'s zero-arg
    /// convenience init in Release builds; Debug builds use
    /// ``NoOpRespawnGuard`` instead so a developer running the app from
    /// Xcode doesn't pollute launchd state.
    ///
    /// `Bundle.main.executableURL` is the safe source for the path that
    /// will be respawned — it's the binary the user is already running,
    /// not derived from any user-tainted input.
    static func production() -> PersistentLockdown {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let launchAgents = home.appendingPathComponent(
            "Library/LaunchAgents",
            isDirectory: true
        )
        let trigger = SharedPaths.applicationSupport.appendingPathComponent(
            "respawn-trigger"
        )
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: "/Applications/Curfew.app/Contents/MacOS/Curfew")
        return PersistentLockdown(
            launchAgentsDirectory: launchAgents,
            triggerPath: trigger,
            curfewExecutableURL: executable
        )
    }

    /// Writes the plist and asks launchd to load it. Idempotent —
    /// re-running overwrites the file and re-loads. Any launchctl
    /// failure is re-thrown so the caller can decide whether to warn
    /// the user or silently fall back to the weaker single-process
    /// deterrent.
    func install() throws {
        try FileManager.default.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )
        let plistURL = plistURL()
        let data = try PropertyListSerialization.data(
            fromPropertyList: renderPlist(),
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
        try launchctl.run(arguments: ["load", plistURL.path])
        lockdownLogger.info("launchagent installed at \(plistURL.path)")
    }

    /// Unloads the agent and removes the plist. Safe to call when not
    /// installed — the file-exists check guards the unlink.
    func uninstall() throws {
        let plistURL = plistURL()
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try launchctl.run(arguments: ["unload", plistURL.path])
            try FileManager.default.removeItem(at: plistURL)
            lockdownLogger.info("launchagent uninstalled from \(plistURL.path)")
        }
    }

    /// Creates the trigger file so launchd's `KeepAlive.PathState`
    /// resolves to `true` → Curfew is kept alive. Call on lockout start.
    func arm() throws {
        try FileManager.default.createDirectory(
            at: triggerPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let empty = Data()
        try empty.write(to: triggerPath, options: .atomic)
    }

    /// Removes the trigger file so launchd's `KeepAlive.PathState`
    /// resolves to `false` → Curfew is no longer respawned on exit.
    /// Call on lockout end. Safe to call when the file isn't present.
    func disarm() throws {
        guard FileManager.default.fileExists(atPath: triggerPath.path) else {
            return
        }
        try FileManager.default.removeItem(at: triggerPath)
    }

    /// Builds the plist dictionary launchd will read. Exposed (rather
    /// than kept private) so tests can assert keys directly without
    /// re-parsing XML; `install()` serialises on its way to disk.
    func renderPlist() -> [String: Any] {
        [
            "Label": Self.agentLabel,
            "ProgramArguments": [curfewExecutableURL.path],
            "RunAtLoad": false,
            "KeepAlive": [
                "PathState": [
                    triggerPath.path: true
                ]
            ]
        ]
    }

    private func plistURL() -> URL {
        launchAgentsDirectory.appendingPathComponent(
            "\(Self.agentLabel).plist"
        )
    }
}
