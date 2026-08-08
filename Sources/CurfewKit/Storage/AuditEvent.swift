import Foundation

/// Schema version stamped on every audit record as `v`.
///
/// Bump only for a *breaking* change to the record envelope (a renamed or
/// removed top-level field, or a change to how `hash` is computed). Adding a
/// new ``AuditEventType`` or a new key inside `detail` is additive and does
/// **not** bump this — parsers are required to ignore unknown event types and
/// unknown detail keys. See `Documentation/audit-log.md`.
public let auditSchemaVersion = 1

/// Which on-disk stream a record belongs to.
///
/// One stream means one writer process. The app and the root daemon never
/// share a file, which is how Curfew avoids interleaved writes without a lock
/// protocol it could not test. The value is stamped into every record as
/// `stream` so a merged, time-sorted view still says who wrote each line.
public enum AuditStream: String, Codable, Equatable, CaseIterable, Sendable {
    /// Written by the Curfew app under the user's UID.
    case app

    /// Written by `curfew-daemon` as root.
    case daemon
}

/// Who caused the event, as distinct from who wrote the line.
///
/// The writer is always the process that owns the stream. The actor is the
/// origin of the action, which is frequently *not* the writer: a schedule
/// change requested over MCP is written by the app but attributed to the
/// calling client. Keeping the two separate is what lets the log answer
/// "who asked for this?" and "who attests to it?" independently.
public enum AuditActor: Equatable, Sendable {
    /// The Curfew app acted on its own — a tick-loop transition, a policy
    /// decision, an automatic grant.
    case app

    /// The privileged daemon acted.
    case daemon

    /// A person acting directly in Curfew's own UI.
    case user

    /// `curfew-ctl` originated the request.
    case cli

    /// An MCP client originated the request. The associated value is the
    /// client identifier when one is known, otherwise `nil`.
    case mcp(client: String?)

    /// macOS itself (wake, launchd, TCC) originated the event.
    case system

    /// The wire token written to the `actor` field. `mcp` renders as
    /// `mcp:<client>` when a client is known and plain `mcp` when it is not,
    /// so a parser can split on the first `:` and always get a valid actor
    /// class in the head position.
    public var token: String {
        switch self {
        case .app: "app"
        case .daemon: "daemon"
        case .user: "user"
        case .cli: "cli"
        case .system: "system"
        case .mcp(let client):
            if let client, !client.isEmpty {
                "mcp:\(AuditActor.sanitize(client))"
            } else {
                "mcp"
            }
        }
    }

    /// Strips anything that would make the token ambiguous or unreadable.
    /// MCP client identifiers arrive from an external process, so they are
    /// untrusted input: a client calling itself `app` or embedding a newline
    /// must not be able to forge a different actor class or a second line.
    private static func sanitize(_ client: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let scrubbed = String(
            client.unicodeScalars
                .map { allowed.contains($0) ? Character($0) : "_" }
                .prefix(64)
        )
        return scrubbed.isEmpty ? "unknown" : scrubbed
    }
}

/// Every event Curfew can write to the audit log.
///
/// Raw values are the stable wire format and use `namespace.event` dotted
/// naming so an auditor can `grep '"event":"daemon\.'` for one subsystem.
/// Never rename a case — a rename silently breaks every parser and every
/// already-written file on a user's disk. Add a new case instead.
public enum AuditEventType: String, Codable, Equatable, CaseIterable, Sendable {
    // MARK: Audit stream meta

    /// A writer opened the stream. Carries the rotation configuration and
    /// whether the hash chain was recovered from an existing file, so a
    /// reader can tell a fresh install from a broken chain.
    case streamOpened = "audit.stream_opened"

    /// The active segment reached its size cap and was rotated.
    case rotated = "audit.rotated"

    // MARK: App lifecycle

    /// The app process started.
    case appLaunched = "app.launched"

    /// The app process is terminating through the normal AppKit path. Absence
    /// of this record before the next `app.launched` means the app was killed.
    case appTerminating = "app.terminating"

    /// Accessibility trust changed. `from`/`to` are `granted` / `denied`.
    case accessibilityChanged = "app.accessibility_changed"

    /// The folded enforcement-health verdict changed — the single best signal
    /// for "was the keyboard shield actually up while the user was locked out?"
    case enforcementHealthChanged = "app.enforcement_health_changed"

    /// The user-space respawn LaunchAgent was armed or disarmed.
    case respawnGuardChanged = "app.respawn_guard_changed"

    // MARK: Enforcement

    /// The enforcement phase moved. `from`/`to` are ``EnforcementPhase``
    /// tokens; `detail` carries the schedule that produced the decision.
    case phaseChanged = "enforcement.phase_changed"

    /// The warning escalation stage moved (T-30 → T-15 → …).
    case warningStageChanged = "enforcement.warning_stage_changed"

    /// Lockout began.
    case lockoutStarted = "lockout.started"

    /// Lockout ended. `detail.reason` says whether the schedule, an override,
    /// or a day-off boundary ended it.
    case lockoutEnded = "lockout.ended"

    // MARK: Schedule

    /// A schedule change was submitted and classified by `SchedulePolicyEngine`.
    case scheduleChangeRequested = "schedule.change_requested"

    /// A due schedule change was deliberately held back — today only by the
    /// anti-bypass rule that refuses to apply a weaker schedule during lockout.
    case scheduleChangeDeferred = "schedule.change_deferred"

    /// A pending schedule change reached its effective date and was applied.
    case scheduleChangeApplied = "schedule.change_applied"

    /// A queued schedule change was withdrawn before it took effect.
    case scheduleChangeCancelled = "schedule.change_cancelled"

    // MARK: Grants

    /// An extension was asked for.
    case extensionRequested = "extension.requested"

    /// An extension was granted; `detail` carries minutes and remaining budget.
    case extensionGranted = "extension.granted"

    /// An extension was refused; `detail.reason` is a stable token.
    case extensionDenied = "extension.denied"

    /// An override was asked for through the Convince Me composer.
    case overrideRequested = "override.requested"

    /// An override was granted; `detail` carries minutes, expiry, and budget.
    case overrideGranted = "override.granted"

    /// An override was refused; `detail.reason` is a stable token.
    case overrideDenied = "override.denied"

    // MARK: Presence

    /// The user went idle or came back. `from`/`to` are `active` / `idle`.
    case presenceChanged = "presence.changed"

    // MARK: Auto-shutdown (app side)

    /// The app queued a shutdown attempt for a future moment.
    case shutdownScheduled = "shutdown.scheduled"

    /// The first attempt failed and a retry was queued.
    case shutdownRetryScheduled = "shutdown.retry_scheduled"

    /// The app dispatched the shutdown command successfully.
    case shutdownExecuted = "shutdown.executed"

    /// Apple Events automation was denied, so the app cannot shut the Mac down.
    case shutdownPermissionDenied = "shutdown.permission_denied"

    /// Both attempts failed. Lockout stays up by other means.
    case shutdownFailed = "shutdown.failed"

    /// A queued shutdown was abandoned because lockout ended or the setting
    /// was turned off before the fire date.
    case shutdownCancelled = "shutdown.cancelled"

    /// A protected-work claim is holding the app's shutdown back, bounded by
    /// `ProtectedWorkPolicy.maximumDeferral`.
    case shutdownDeferred = "shutdown.deferred"

    /// A verified break-glass release stood the app's shutdown down. Not
    /// terminal — revoking the release re-arms the workflow.
    case shutdownReleasedByBreakGlass = "shutdown.released_by_break_glass"

    // MARK: MCP / CLI

    /// A write request arrived on the MCP queue. `actor` names the origin.
    case mcpRequestReceived = "mcp.request_received"

    /// The consent policy approved the request with no human in the loop.
    case mcpRequestAutoApproved = "mcp.request_auto_approved"

    /// The request was parked for the consent sheet.
    case mcpRequestQueued = "mcp.request_queued"

    /// A human approved the request in the consent sheet.
    case mcpRequestApproved = "mcp.request_approved"

    /// The request was refused, by policy or by a human.
    case mcpRequestDenied = "mcp.request_denied"

    // MARK: Protected-work carve-out

    /// An unexpired protected-work claim exists, so a destructive enforcement
    /// action may be held back. The antecedent for any `*.deferred` or
    /// `daemon.shutdown_held` line that follows.
    case protectedWorkActive = "protected_work.active"

    /// No unexpired claim remains, so nothing is holding enforcement back.
    case protectedWorkCleared = "protected_work.cleared"

    /// A verified break-glass release covering the lockout window in progress
    /// was read. Carries the release identifier so an auditor can trace it to
    /// the `curfew-ctl` invocation that issued it.
    case breakGlassObserved = "break_glass.observed"

    // MARK: Daemon

    /// The privileged daemon started.
    case daemonStarted = "daemon.started"

    /// The daemon exited its loop. `detail.reason` says why.
    case daemonStopped = "daemon.stopped"

    /// The daemon read a lockout deadline record. `detail.source` is `user`
    /// or `shadow` depending on which copy it came from.
    case daemonDeadlineObserved = "daemon.deadline_observed"

    /// The lockout window ended on its own terms and the daemon stood down.
    case daemonDeadlineElapsed = "daemon.deadline_elapsed"

    /// The app heartbeat aged past the daemon's tolerance during a live
    /// lockout — the app was killed, crashed, or was force-quit.
    case daemonHeartbeatStale = "daemon.heartbeat_stale"

    /// The app heartbeat came back inside the tolerance, which is what a
    /// LaunchAgent respawn looks like from the daemon's side.
    case daemonHeartbeatRecovered = "daemon.heartbeat_recovered"

    /// The daemon invoked `/sbin/shutdown`.
    case daemonShutdownIssued = "daemon.shutdown_issued"

    /// The daemon could not invoke `/sbin/shutdown`.
    case daemonShutdownFailed = "daemon.shutdown_failed"

    /// A due shutdown is being held back because protected work is live. The
    /// `until` bound is the deferral budget, not a promise.
    case daemonShutdownHeld = "daemon.shutdown_held"

    /// A `/sbin/shutdown` this daemon already issued was called off. The
    /// highest-consequence line the daemon can write: it is the difference
    /// between the machine powering off in under a minute and not.
    case daemonShutdownCancelled = "daemon.shutdown_cancelled"

    /// A verified break-glass release covers this lockout window, so the
    /// daemon stood down. This is the privileged escape hatch from an
    /// enforced lockout, so it is recorded on every use.
    case daemonStandDown = "daemon.stand_down"

    /// The bounded deferral window opened — the clock that limits how long
    /// protected work may hold enforcement off started here.
    case daemonDeferralOpened = "daemon.deferral_opened"

    /// The bounded deferral window closed, either because the work finished
    /// or because the daemon no longer has an action to defer.
    case daemonDeferralClosed = "daemon.deferral_closed"
}

/// A JSON scalar allowed inside a record's `detail` object.
///
/// Deliberately not `Any`: the audit log has to round-trip through a parser
/// written by somebody who only read the spec, so nested objects and arrays
/// are excluded. Anything structured gets flattened into dotted keys instead.
public enum AuditValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    /// The JSON text for this value, ready to be spliced into a line.
    var jsonFragment: String {
        switch self {
        case .string(let text): AuditJSON.quote(text)
        case .int(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        case .double(let value):
            value.isFinite ? String(format: "%g", value) : "null"
        }
    }
}

/// One audit record, before serialization.
///
/// `hash` is absent here on purpose: it is derived from the serialized bytes
/// of everything else, so only ``AuditLineEncoder`` can produce it.
public struct AuditRecord: Equatable, Sendable {
    /// Stream the record will be written to.
    public var stream: AuditStream

    /// Moment the event happened, serialized as ISO-8601 with an explicit
    /// UTC offset and millisecond precision.
    public var timestamp: Date

    /// Monotonic per-stream counter, assigned by the writer at append time.
    /// `0` on a record that has not been appended yet.
    public var sequence: Int

    /// Origin of the action.
    public var actor: AuditActor

    /// What happened.
    public var event: AuditEventType

    /// Prior state, for transitions. `nil` for point events.
    public var from: String?

    /// New state, for transitions. `nil` for point events.
    public var to: String?

    /// Event-specific payload. Keys are serialized in sorted order.
    public var detail: [String: AuditValue]

    /// Creates a record. `sequence` is filled in by the writer.
    public init(
        stream: AuditStream,
        timestamp: Date,
        sequence: Int = 0,
        actor: AuditActor,
        event: AuditEventType,
        from: String? = nil,
        to: String? = nil,
        detail: [String: AuditValue] = [:]
    ) {
        self.stream = stream
        self.timestamp = timestamp
        self.sequence = sequence
        self.actor = actor
        self.event = event
        self.from = from
        self.to = to
        self.detail = detail
    }
}
