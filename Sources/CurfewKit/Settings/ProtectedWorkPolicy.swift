import Foundation

/// What enforcement must never destroy, and for how long it may wait.
///
/// Curfew's default lockout is a display and keyboard shield: it darkens every
/// screen and swallows the escape chords, but it never touches a process. Two
/// paths do end processes — `ShutdownWorkflow`'s graceful-terminate sweep and
/// the privileged daemon's `/sbin/shutdown` — and both of them take a
/// terminal's child processes down with the terminal. A background agent
/// surviving the night is therefore an accident of which paths happen to be
/// switched off, not a property of the product.
///
/// This policy makes it a property. It answers two questions:
///
/// 1. *Which applications does graceful termination skip?* — the allowlist in
///    ``protectedBundleIdentifiers`` and ``protectedProcessNames``.
/// 2. *How long may a destructive action wait for work that is mid-flight?* —
///    ``maximumDeferralMinutes``, bounded so a wedged claim cannot disable
///    enforcement outright.
///
/// The defaults name common terminal emulators and agent CLIs because that is
/// where delegated work actually lives. They are configuration, not
/// architecture: every entry is user-editable and nothing in the enforcement
/// paths knows any specific bundle identifier.
public struct ProtectedWorkPolicy: Codable, Equatable, Sendable {
    /// Hard ceiling on ``maximumDeferralMinutes``, applied on decode as well
    /// as on construction. Enforcement that can be postponed indefinitely is
    /// not enforcement, so the user cannot configure past this number and a
    /// hand-edited settings file or policy mirror cannot either.
    public static let deferralCeilingMinutes = 120

    /// Hard ceiling on a single claim's lease. A claim is a heartbeat, not a
    /// reservation: an agent that dies mid-task stops renewing and its
    /// protection lapses within one lease.
    public static let leaseCeilingMinutes = 30

    /// Bundle identifiers `ShutdownWorkflow` must never send `terminate()` to.
    /// Matched case-insensitively against `NSRunningApplication.bundleIdentifier`.
    public var protectedBundleIdentifiers: [String]

    /// Executable names `ShutdownWorkflow` must never terminate, for processes
    /// that carry no bundle identifier. Matched case-insensitively against the
    /// last path component of the executable URL.
    public var protectedProcessNames: [String]

    /// Executable names whose *mere liveness* postpones a destructive action,
    /// with no claim filed and nothing to remember. Matched case-insensitively
    /// and exactly against a process's `p_comm` by
    /// ``LiveProtectedWorkMonitor``.
    ///
    /// Deliberately a different, narrower list than
    /// ``protectedProcessNames``, because the two answer different questions.
    /// "Do not send this `terminate()`" is cheap to be generous with: sparing
    /// a terminal emulator costs nothing if the Mac powers off anyway. "Hold
    /// the shutdown while this is alive" is not — `tmux`, `screen`, and every
    /// terminal emulator are alive on a working machine essentially always, so
    /// reusing that list here would spend the full deferral window every
    /// single night for most users. That is not a carve-out for delegated
    /// work; that is enforcement quietly becoming thirty minutes weaker.
    ///
    /// So this list names things that are alive *because a job is running*
    /// and exit when it finishes.
    public var deferringProcessNames: [String]

    /// Whether a live login session from another host postpones a destructive
    /// action — someone working on this Mac over SSH.
    ///
    /// Separate from ``deferringProcessNames`` because the signal is
    /// different in kind: `sshd` runs whenever Remote Login is enabled, so
    /// only the login database can tell an accepting machine from an occupied
    /// one. See ``LoginSession/isRemote``.
    public var defersForRemoteSessions: Bool

    /// Whether an external agent may assert work-in-progress through the MCP
    /// `curfew_declare_work` tool. Off means only the app and `curfew-ctl` can
    /// file a claim.
    public var acceptsAgentClaims: Bool

    /// Longest a destructive action may be postponed while a claim is live,
    /// measured from the moment that action first came due. Clamped to
    /// `1 ... deferralCeilingMinutes`.
    public var maximumDeferralMinutes: Int

    /// Lease length granted to a claim that does not ask for one. Clamped to
    /// `1 ... leaseCeilingMinutes`.
    public var defaultLeaseMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case protectedBundleIdentifiers
        case protectedProcessNames
        case deferringProcessNames
        case defersForRemoteSessions
        case acceptsAgentClaims
        case maximumDeferralMinutes
        case defaultLeaseMinutes
    }

    /// Memberwise initialiser. Both minute fields are clamped on assignment so
    /// an out-of-range value written directly to the struct is corrected
    /// rather than persisted.
    public init(
        protectedBundleIdentifiers: [String],
        protectedProcessNames: [String],
        deferringProcessNames: [String] = ProtectedWorkPolicy.defaultDeferringProcessNames,
        defersForRemoteSessions: Bool = true,
        acceptsAgentClaims: Bool,
        maximumDeferralMinutes: Int,
        defaultLeaseMinutes: Int
    ) {
        self.protectedBundleIdentifiers = protectedBundleIdentifiers
        self.protectedProcessNames = protectedProcessNames
        self.deferringProcessNames = deferringProcessNames
        self.defersForRemoteSessions = defersForRemoteSessions
        self.acceptsAgentClaims = acceptsAgentClaims
        self.maximumDeferralMinutes = Self.clampDeferral(maximumDeferralMinutes)
        self.defaultLeaseMinutes = Self.clampLease(defaultLeaseMinutes)
    }

    /// Decoder tolerant of a v0.1 payload that carried none of these keys, and
    /// of a hand-edited one carrying absurd numbers.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        self.protectedBundleIdentifiers = try container.decodeIfPresent(
            [String].self,
            forKey: .protectedBundleIdentifiers
        ) ?? fallback.protectedBundleIdentifiers
        self.protectedProcessNames = try container.decodeIfPresent(
            [String].self,
            forKey: .protectedProcessNames
        ) ?? fallback.protectedProcessNames
        self.deferringProcessNames = try container.decodeIfPresent(
            [String].self,
            forKey: .deferringProcessNames
        ) ?? fallback.deferringProcessNames
        self.defersForRemoteSessions = try container.decodeIfPresent(
            Bool.self,
            forKey: .defersForRemoteSessions
        ) ?? fallback.defersForRemoteSessions
        self.acceptsAgentClaims = try container.decodeIfPresent(
            Bool.self,
            forKey: .acceptsAgentClaims
        ) ?? fallback.acceptsAgentClaims
        self.maximumDeferralMinutes = try Self.clampDeferral(
            container.decodeIfPresent(Int.self, forKey: .maximumDeferralMinutes)
                ?? fallback.maximumDeferralMinutes
        )
        self.defaultLeaseMinutes = try Self.clampLease(
            container.decodeIfPresent(Int.self, forKey: .defaultLeaseMinutes)
                ?? fallback.defaultLeaseMinutes
        )
    }

    // MARK: - Queries

    /// Whether graceful termination must skip this application.
    ///
    /// Both comparisons are case-insensitive and exact — no prefix or glob
    /// matching, because a prefix rule is a footgun on reverse-DNS bundle
    /// identifiers (`com.apple.Terminal` would shield everything Apple ships).
    public func protectsApplication(
        bundleIdentifier: String?,
        executableName: String?
    ) -> Bool {
        if let bundleIdentifier,
           protectedBundleIdentifiers
           .contains(where: { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
            return true
        }
        if let executableName,
           protectedProcessNames
           .contains(where: { $0.caseInsensitiveCompare(executableName) == .orderedSame }) {
            return true
        }
        return false
    }

    /// Whether a live process with this executable name should postpone a
    /// destructive action for as long as it keeps running.
    ///
    /// Exact and case-insensitive, matching
    /// ``protectsApplication(bundleIdentifier:executableName:)``. An empty
    /// ``deferringProcessNames`` therefore turns liveness-based deferral off
    /// completely, which is the supported way to opt out of it.
    public func defersForProcess(named executableName: String) -> Bool {
        deferringProcessNames
            .contains { $0.caseInsensitiveCompare(executableName) == .orderedSame }
    }

    /// ``maximumDeferralMinutes`` as a `TimeInterval`, for the gate.
    public var maximumDeferral: TimeInterval {
        TimeInterval(maximumDeferralMinutes * 60)
    }

    /// Lease length to grant a claim that asked for `requested` minutes, or
    /// the configured default when it asked for nothing.
    public func leaseMinutes(requested: Int?) -> Int {
        guard let requested else {
            return defaultLeaseMinutes
        }
        return Self.clampLease(requested)
    }

    // MARK: - Defaults

    /// Factory defaults: common terminal emulators and agent CLIs protected,
    /// agent claims accepted, 30-minute deferral bound, 10-minute leases.
    ///
    /// The 30-minute bound is the product's answer to "how much unfinished
    /// agent work is a night of enforcement worth?" It comfortably outlasts a
    /// single agent turn and is a rounding error against a lockout window
    /// measured in hours, so a claim that never gets released costs the user
    /// half an hour of curfew rather than the whole night.
    /// Agent CLIs whose liveness postpones a destructive action.
    ///
    /// Every entry is a foreground process that exists only while a job is
    /// running, so an idle machine holds nothing. Note what is *absent*
    /// relative to ``protectedProcessNames``: `tmux`, `screen`, `ssh`, and
    /// `mosh` are all spared from `terminate()` but do not open a deferral
    /// window, because a multiplexer or a parked client can sit alive for
    /// weeks and would make the hold permanent rather than occasional.
    ///
    /// Held separately from ``default`` so the memberwise initialiser can
    /// default to it without referring to a static that is still being built.
    public static let defaultDeferringProcessNames = [
        "claude",
        "codex",
        "aider",
        "goose",
        "gemini"
    ]

    public static let `default` = ProtectedWorkPolicy(
        protectedBundleIdentifiers: [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "io.alacritty",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable",
            "co.zeit.hyper",
            "com.microsoft.VSCode",
            // Cursor ships under a ToDesktop-issued identifier rather than a
            // vendor-readable one; it is listed by value because there is
            // nothing else to match on.
            "com.todesktop.230313mzl4w4u92"
        ],
        protectedProcessNames: [
            "claude",
            "codex",
            "aider",
            "goose",
            "gemini",
            "ssh",
            "mosh",
            "tmux",
            "screen"
        ],
        deferringProcessNames: defaultDeferringProcessNames,
        defersForRemoteSessions: true,
        acceptsAgentClaims: true,
        maximumDeferralMinutes: 30,
        defaultLeaseMinutes: 10
    )

    // MARK: - Private

    private static func clampDeferral(_ minutes: Int) -> Int {
        min(max(1, minutes), deferralCeilingMinutes)
    }

    private static func clampLease(_ minutes: Int) -> Int {
        min(max(1, minutes), leaseCeilingMinutes)
    }
}

// MARK: - Cross-process mirror

public extension ProtectedWorkPolicy {
    /// Writes the policy where a process that cannot read the user's
    /// `UserDefaults` — the root daemon — can still find it.
    func writeMirror(to url: URL = SharedPaths.protectedWorkPolicySnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Reads the mirror, falling back to ``default`` for a missing or
    /// malformed file. Failing to `default` rather than to "protect nothing"
    /// is deliberate: a corrupt mirror must not turn into a licence to kill
    /// the user's terminals.
    static func loadMirror(
        from url: URL = SharedPaths.protectedWorkPolicySnapshot
    ) -> ProtectedWorkPolicy {
        guard let data = try? BoundedRegularFileReader.read(
            url,
            maximumBytes: 65536
        ),
            let policy = try? JSONDecoder().decode(ProtectedWorkPolicy.self, from: data)
        else {
            return .default
        }
        return policy
    }
}
