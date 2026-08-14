import Foundation

/// Canonical filesystem paths shared by the Curfew app, `curfew-ctl`, and
/// `curfew-mcp`.
///
/// Keeping paths in one place prevents the three processes from disagreeing
/// about where settings, the activity log, or MCP request queues live.
/// All three processes must read from / write to the same files; any
/// divergence here silently produces stale reads.
public enum SharedPaths {
    /// `~/Library/Application Support/Curfew/` — or `Curfew (Dev)` for a
    /// development build, so a dev run's database, request queue, and settings
    /// never touch the production install the user relies on. The suffix is
    /// empty for production, so its directory is unchanged.
    ///
    /// The Curfew app creates this directory on first launch. CLI/MCP tools
    /// assume it exists and fail gracefully when it doesn't (no app run yet).
    public static var applicationSupport: URL {
        applicationSupportBase.appendingPathComponent(
            "Curfew\(CurfewFlavor.current.displaySuffix)",
            isDirectory: true
        )
    }

    /// The system Application Support directory, falling back to the well-known
    /// location when the lookup fails. Shared by ``applicationSupport`` (which
    /// appends the flavor-specific app folder) and the deliberately
    /// flavor-neutral ``enforcementOwnerLock``.
    private static var applicationSupportBase: URL {
        // Root processes must not resolve this through the system lookup: for a
        // LaunchDaemon it answers `/var/root/Library/Application Support`, which
        // is not where the app writes. ``userHomeDirectory`` redirects to the
        // console user's home in that case and is a no-op for everyone else.
        if geteuid() == 0 {
            return userHomeDirectory
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
    }

    // MARK: - Home resolution for privileged processes

    /// Home directory of the human whose Curfew state these paths describe.
    ///
    /// Everything Curfew shares between processes lives under the user's home.
    /// The privileged daemon runs as root, where `NSHomeDirectory()` answers
    /// `/var/root` and every derived path silently misses the files the app
    /// actually writes — a stale read that reads as "no lockout, no protected
    /// work" and would let root-level enforcement run against nothing. Root
    /// therefore resolves the console user's home instead.
    public static var userHomeDirectory: URL {
        URL(
            fileURLWithPath: resolveHomeDirectory(
                processHome: NSHomeDirectory(),
                effectiveUserID: geteuid(),
                consoleUserHome: consoleUserHomeDirectory()
            ),
            isDirectory: true
        )
    }

    /// Pure resolution policy behind ``userHomeDirectory``, split out so tests
    /// can drive the root branch without running as root.
    ///
    /// Non-root processes always get `processHome` back, so the resolved path
    /// is byte-identical to what every existing caller already saw.
    public static func resolveHomeDirectory(
        processHome: String,
        effectiveUserID: uid_t,
        consoleUserHome: String?
    ) -> String {
        guard effectiveUserID == 0 else {
            return processHome
        }
        guard let consoleUserHome, !consoleUserHome.isEmpty else {
            return processHome
        }
        return consoleUserHome
    }

    /// Home directory of the user currently logged in at the display, found by
    /// asking who owns `/dev/console`. Returns `nil` when nobody is logged in
    /// or when the console is still owned by root (pre-login), in which case
    /// there is no user state to read anyway.
    private static func consoleUserHomeDirectory() -> String? {
        var info = stat()
        guard stat("/dev/console", &info) == 0, info.st_uid != 0 else {
            return nil
        }
        guard let entry = getpwuid(info.st_uid), let directory = entry.pointee.pw_dir else {
            return nil
        }
        return String(cString: directory)
    }

    /// App Group / shared-container identifier reserved for the future
    /// WidgetKit extension. The main app and bundled CLI tools use the
    /// explicit filesystem path below today; the widget target will gain the
    /// actual entitlement when it is wired into the Xcode project.
    /// Flavor-suffixed for development (`group.studio.hypertext.curfew.dev`) so
    /// a dev build's shared container is distinct; empty suffix leaves the
    /// production group untouched. The main app is unsandboxed and reaches the
    /// container through the filesystem fallback below, so the suffix needs no
    /// entitlement change.
    public static let widgetAppGroupIdentifier =
        "group.studio.hypertext.curfew\(CurfewFlavor.current.identifierSuffix)"

    /// `~/Library/Group Containers/group.studio.hypertext.curfew/`
    ///
    /// Uses the system-resolved App Group container when available, otherwise
    /// falls back to the well-known filesystem location so unsandboxed helper
    /// binaries (`curfew-ctl`, `curfew-mcp`) can still cooperate with the same
    /// storage root before the widget target is wired in.
    public static var widgetSharedContainer: URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: widgetAppGroupIdentifier
        ) {
            return container
        }

        return userHomeDirectory
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(widgetAppGroupIdentifier, isDirectory: true)
    }

    /// Shared storage root used by the app, bundled CLI tools, and the future
    /// widget extension for files that must cross the sandbox boundary.
    public static var widgetSharedSupport: URL {
        widgetSharedContainer.appendingPathComponent("Curfew", isDirectory: true)
    }

    /// Canonical SQLite database written by the app's `ActivityStore` and read
    /// by the bundled CLI tools (`curfew-ctl`, `curfew-mcp`).
    ///
    /// Lives in the app's own Application Support — *not* the App Group
    /// container. A non-sandboxed app touching its App Group container raises
    /// the macOS "access data from other apps" prompt, and the activity log
    /// has no cross-sandbox consumer (the CLI tools run in the user context;
    /// the widget is not yet shipped). When the WidgetKit extension lands it
    /// will mirror what it needs into the shared container, gated behind
    /// ``FeatureFlags/widgetKitEnabled``.
    public static var activityDatabase: URL {
        applicationSupport.appendingPathComponent("activity.sqlite3")
    }

    /// The App Group container location the activity database lived in before
    /// it moved back to ``activityDatabase``. Used once, on first launch of the
    /// new layout, to migrate any existing history into the canonical store.
    public static var sharedContainerActivityDatabase: URL {
        widgetSharedSupport.appendingPathComponent("activity.sqlite3")
    }

    /// Canonical SQLite database written by the app's `ReflectionStore` and
    /// read by the bundled CLI/MCP tools. Lives beside ``activityDatabase`` in
    /// the app's own Application Support for the same reason: reflections have
    /// no cross-sandbox consumer today, so keeping the file out of the App
    /// Group container avoids the macOS "access data from other apps" prompt.
    public static var reflectionDatabase: URL {
        applicationSupport.appendingPathComponent("reflections.sqlite3")
    }

    /// JSON queue file for pending MCP write-tool requests.
    ///
    /// `curfew-mcp` appends new `MCPPendingRequest` entries here.
    /// The Curfew app monitors this file via `MCPRequestMonitor` and
    /// surfaces a consent sheet for each pending entry. After the user
    /// approves or denies, the app updates the entry's `status` in-place.
    /// `curfew-mcp` polls this file to resolve the response it returns to
    /// the MCP client.
    public static var mcpRequestQueue: URL {
        applicationSupport.appendingPathComponent("mcp-requests.json")
    }

    /// Mirrored settings snapshot for the widget extension. The main app writes
    /// this JSON whenever persisted settings change; the widget reads it
    /// without depending on the app's private `UserDefaults` domain.
    public static var widgetSettingsSnapshot: URL {
        widgetSharedSupport.appendingPathComponent("widget-settings.json")
    }

    /// User Defaults suite name used by the Curfew app (= its bundle ID).
    /// CLI/MCP tools pass this to `UserDefaults(suiteName:)` to read the
    /// same preferences plist the app writes via `UserDefaults.standard`.
    ///
    /// Flavor-suffixed so the suite still equals the running app's bundle id
    /// (`studio.hypertext.curfew.dev` for development). Helper tools resolve the
    /// flavor from `CURFEW_FLAVOR`, so they read the matching plist.
    public static let defaultsSuiteName =
        "studio.hypertext.curfew\(CurfewFlavor.current.identifierSuffix)"

    // MARK: - Privileged daemon paths (root-readable, user-writable via App Group)

    /// `/Library/Application Support/Curfew/` — written by the app, read by
    /// the privileged daemon. The app writes a sentinel file here when lockout
    /// starts; the daemon uses `KeepAlive.PathState` to watch the sentinel so
    /// it wakes up when the file appears and exits cleanly when it disappears.
    public static var privilegedApplicationSupport: URL {
        URL(fileURLWithPath: "/Library/Application Support/Curfew", isDirectory: true)
    }

    /// Sentinel file that signals an active lockout to the privileged daemon.
    /// The app creates this file on `working → locked` transition and deletes
    /// it on `locked → working/dayOff`. The daemon wakes on file creation and
    /// exits on deletion (via `KeepAlive.PathState`).
    public static var lockoutActiveSentinel: URL {
        privilegedApplicationSupport.appendingPathComponent("lockout-active")
    }

    /// JSON record of the active lockout window. Written by the app on
    /// `.locked` entry, cleared on natural unlock. The privileged daemon
    /// reads this to know how long it must keep the Mac armed even if the
    /// Curfew app process disappears (force-kill, crash, force-shutdown).
    /// Lives in the user-writable shared container today; the v0.2 daemon
    /// shadow-copies it to ``privilegedApplicationSupport`` so a delete by
    /// the user can't end-run the deadline.
    public static var lockoutDeadline: URL {
        widgetSharedSupport.appendingPathComponent("lockout-deadline.json")
    }

    /// Last authenticated account wake status and its monotonic counters.
    /// Persisting this independently of live connectivity lets a restarted
    /// Mac preserve the same rollback gate and deterministic final deadline.
    public static var accountWakeLedger: URL {
        applicationSupport.appendingPathComponent("account-wake-ledger.json")
    }

    /// Root-owned shadow copy of the durable lockout deadline. The daemon
    /// writes this from the user-side record once and re-reads it on
    /// every loop iteration; if the user deletes the user-side file the
    /// shadow is still authoritative until `scheduledUnlockAt` passes.
    public static var lockoutDeadlineShadow: URL {
        privilegedApplicationSupport.appendingPathComponent("lockout-deadline.json")
    }

    /// Timestamp file the app touches every tick so the daemon can tell
    /// whether the Curfew app process is still alive. Stale heartbeat plus
    /// an active deadline triggers the daemon's shutdown enforcement.
    public static var appHeartbeat: URL {
        widgetSharedSupport.appendingPathComponent("app-heartbeat")
    }

    /// Symmetric key used by `MCPRequestSigner` to authenticate MCP queue
    /// entries. Mode 0600 owned by the user; both the app and the
    /// `curfew-mcp` subprocess read it under the same UID. An attacker
    /// with shell access already trumps this; the file's job is to close
    /// the `aiConsentPolicy = .autoApprove` bypass surface, not to
    /// authenticate against a stronger threat model.
    public static var mcpSharedSecret: URL {
        applicationSupport.appendingPathComponent(".mcp-secret")
    }

    // MARK: - Protected delegated work

    /// JSON list of live ``ProtectedWorkClaim`` leases. Written by the app,
    /// `curfew-ctl work claim`, and the `curfew_declare_work` MCP tool; read
    /// by the app's shutdown workflow and by the privileged daemon.
    ///
    /// Deliberately in the app's own Application Support rather than the App
    /// Group container: a non-sandboxed app touching its group container
    /// raises the macOS "access data from other apps" prompt, and every
    /// consumer here runs in the user context (or as root, which reads the
    /// user's home through ``userHomeDirectory``).
    public static var protectedWorkClaims: URL {
        applicationSupport.appendingPathComponent("protected-work.json")
    }

    /// Mirror of the user's ``ProtectedWorkPolicy``, written by the app on
    /// every settings save. The daemon runs as root and therefore cannot read
    /// the user's `UserDefaults` domain; this file is how the policy reaches
    /// it. A missing or malformed mirror leaves the daemon on
    /// ``ProtectedWorkPolicy/default``.
    public static var protectedWorkPolicySnapshot: URL {
        applicationSupport.appendingPathComponent("protected-work-policy.json")
    }

    // MARK: - Break-glass emergency release

    /// Signed ``BreakGlassRelease`` record written by `curfew-ctl break-glass`.
    /// The app and the privileged daemon both honor a verified record whose
    /// `issuedAt` falls inside the current lockout window, and both refuse to
    /// take destructive action while one is present.
    public static var breakGlassRelease: URL {
        applicationSupport.appendingPathComponent("break-glass.json")
    }

    /// Symmetric key that authenticates ``BreakGlassRelease`` records, mode
    /// 0600 owned by the user. Same threat model as ``mcpSharedSecret``: it
    /// does not stop somebody with the user's shell, it stops a stray file
    /// write or a stale record from standing enforcement down by accident.
    public static var breakGlassSecret: URL {
        applicationSupport.appendingPathComponent(".break-glass-secret")
    }

    /// Root-owned marker recording when the daemon *first* deferred a shutdown
    /// for protected work. Persisting it means restarting the daemon cannot
    /// reset the bounded-deferral clock.
    public static var enforcementDeferralMarker: URL {
        privilegedApplicationSupport.appendingPathComponent("deferral-started")
    }

    // MARK: - Cross-flavor enforcement ownership

    /// Lock file recording which Curfew flavor currently holds the user in
    /// lockout. Unlike every other path here it is deliberately *flavor-neutral*
    /// — it always resolves to the canonical `Curfew` directory regardless of
    /// the running flavor — because it is the one rendezvous every flavor must
    /// agree on to guarantee that only one Curfew locks the user out at a time.
    /// See `EnforcementOwnership`.
    public static var enforcementOwnerLock: URL {
        applicationSupportBase
            .appendingPathComponent("Curfew", isDirectory: true)
            .appendingPathComponent("enforcement-owner.json")
    }
}
