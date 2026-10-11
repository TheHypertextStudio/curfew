import Foundation

/// Shared copy deck used by every surface that produces user-facing text —
/// app UI, `curfew-ctl` CLI output, `curfew-mcp` tool descriptions,
/// onboarding. Anywhere we want the same sentence in two places, the
/// canonical version lives here.
///
/// This exists for three reasons:
///   1. Drift between surfaces is a bug factory. The CLI and the app
///      previously said "locked" / "locked out" / "curfew active" in
///      three slightly different ways.
///   2. Localization. When strings are scattered across `Text("…")`
///      literals, translators see dozens of near-duplicates; when they
///      live in a deck, the translator sees each phrase once.
///   3. A11y copy and screen-reader copy share text with visual copy
///      most of the time; keeping a single source prevents divergence.
///
/// Convention: nouns and short labels are stored as `static let`; any
/// string that takes a parameter is a `static func` returning `String`
/// so the callsite reads left-to-right.
public enum CopyDeck {
    // MARK: - Phase labels

    /// Plain-text phase name rendered in the menu bar, widget, CLI, and
    /// MCP `curfew_status` output. Matches the tokens in
    /// `CurfewKit.phaseName(_:)` so structured output stays stable.
    public enum Phase {
        /// `.working` — user inside permitted hours, no overlay active.
        public static let working = "Working"
        /// `.warning` — approaching lock time; dim overlay is shown.
        public static let warning = "Warning"
        /// `.locked` — full-screen lockout is active.
        public static let locked = "Locked"
        /// `.dayOff` — today has no enforcement window (weekend / holiday).
        public static let dayOff = "Day off"
    }

    // MARK: - Warning-stage labels

    /// Short labels for the warning ladder (T-30, T-15, …, T-0). Used in
    /// notifications, menu bar tooltips, and the CLI `status` output.
    public enum Warning {
        /// T-30 — thirty minutes until lockout; snooze offered.
        public static let thirty = "30 minutes until lockout"
        /// T-15 — fifteen minutes until lockout; snooze offered.
        public static let fifteen = "15 minutes until lockout"
        /// T-5 — five minutes until lockout; floating timer appears.
        public static let five = "5 minutes until lockout"
        /// T-2 — two minutes until lockout; final audible warning.
        public static let two = "2 minutes until lockout"
        /// T-1 — one minute until lockout; save-now prompt.
        public static let one = "1 minute until lockout"
        /// T-0 — lockout firing; overlay is being presented.
        public static let zero = "Lockout starting now"
    }

    // MARK: - Override flow

    /// The prompt shown in the "Need to get back in?" entry on the
    /// lockout screen and in the `curfew-ctl override` error path when a
    /// reason is missing.
    public static let overrideEntryPrompt = "Need to get back in?"

    /// Human-readable description of why overrides have friction — used
    /// verbatim in the onboarding flow and referenced by the MCP tool
    /// description so AI assistants echo the same framing.
    public static let overrideFrictionRationale =
        "Overrides exist but cost something deliberate — typing a reason, " +
        "a cooldown, and a hold-to-confirm — so the easy path is finishing tomorrow."

    // MARK: - Onboarding

    /// Mirrors `GettingStartedCopy` which is the in-app source but lives
    /// in the UI target. CLI and MCP descriptions pull from here so the
    /// same commitment-framing appears everywhere.
    public enum Onboarding {
        /// Primary heading on the first-launch Getting Started window.
        public static let welcomeTitle = "Welcome to Curfew"
        /// One-sentence framing below the welcome title — the
        /// "you already made this decision when clear-headed" argument.
        public static let welcomeSubtitle =
            "Set your schedule while you're thinking clearly, " +
            "then let Curfew enforce it later."
    }

    // MARK: - Schedule summary

    /// Locale-independent short format for a lock-at / unlock-at pair.
    /// Used in the CLI's `schedule show` output and the MCP `schedule`
    /// tool. The app UI uses `DateFormatter` for locale-aware display.
    public static func scheduleWindow(lockHHMM: String, unlockHHMM: String) -> String {
        "\(lockHHMM) → \(unlockHHMM)"
    }

    // MARK: - Retrospective

    /// One-sentence summary for the "This Week" view and its
    /// `curfew_get_weekly_summary` MCP counterpart.
    public static func weekSummary(
        daysHeld: Int,
        extensionsUsed: Int,
        overridesUsed: Int
    ) -> String {
        "\(daysHeld)/7 days held, \(extensionsUsed) extensions, \(overridesUsed) overrides this week."
    }
}
