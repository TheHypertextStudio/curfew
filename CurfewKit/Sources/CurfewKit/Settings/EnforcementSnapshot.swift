import Foundation

/// Denormalised read-model that every Curfew UI surface (menu bar popover,
/// primary window, lockout overlay, widget) consumes instead of reaching into
/// `CurfewAppModel` directly.
///
/// The indirection exists so view code never has to replicate the
/// "phase + formatting + remaining budget" logic — if two surfaces disagreed
/// about what to show during a warning, debugging would be miserable. The
/// model computes a single snapshot per tick and every surface reads from it.
///
/// Snapshots are `Equatable` so view diffing and assertions stay cheap. They
/// are intentionally pure data: no behaviour, no callbacks, no references.
public struct EnforcementSnapshot: Equatable {
    /// Drives high-level UI affordances (menu bar colour, lockout visibility).
    public var phase: EnforcementPhase

    /// SF Symbol name for the current phase, used in the menu bar icon and
    /// the status popover header (e.g. `"checkmark.circle"` when working,
    /// `"lock.fill"` when locked).
    public var symbolName: String

    /// One-line human-readable description of the current phase, e.g.
    /// "Curfew lockout active" or "Wrap up time".
    public var statusLine: String

    /// Formatted `H:MM` string of minutes remaining before lock, or `"—"` when
    /// not applicable (day off, already locked).
    public var timeRemainingText: String

    /// Today's schedule window formatted as `18:00 -> 08:00` or equivalent.
    /// Shown in the popover header and Settings schedule preview.
    public var scheduleWindowText: String

    /// Natural-language sentence describing tomorrow's window, used in the
    /// "what's next" footer of the primary window.
    public var scheduleSummarySentence: String

    /// Optional sentence explaining that a pending schedule change will take
    /// effect at some future date (anti-bypass cooldown surface).
    public var pendingScheduleDescription: String?

    /// Whether the "Hold for extension" button should be enabled right now.
    /// Only true during T-30 and T-15 warning stages with budget remaining.
    public var canRequestExtension: Bool

    /// Full button title including hold duration and minutes gained, e.g.
    /// "Hold 2s for +15m extension".
    public var extensionRequestTitle: String

    /// Remaining weekly extension count (post any already-consumed today).
    public var extensionsRemaining: Int

    /// Memberwise initialiser. Public so the app target — which now links
    /// CurfewKit as a library rather than compiling its sources directly —
    /// can build snapshots for each tick.
    public init(
        phase: EnforcementPhase,
        symbolName: String,
        statusLine: String,
        timeRemainingText: String,
        scheduleWindowText: String,
        scheduleSummarySentence: String,
        pendingScheduleDescription: String?,
        canRequestExtension: Bool,
        extensionRequestTitle: String,
        extensionsRemaining: Int
    ) {
        self.phase = phase
        self.symbolName = symbolName
        self.statusLine = statusLine
        self.timeRemainingText = timeRemainingText
        self.scheduleWindowText = scheduleWindowText
        self.scheduleSummarySentence = scheduleSummarySentence
        self.pendingScheduleDescription = pendingScheduleDescription
        self.canRequestExtension = canRequestExtension
        self.extensionRequestTitle = extensionRequestTitle
        self.extensionsRemaining = extensionsRemaining
    }
}
