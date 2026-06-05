#if DEBUG
    import Foundation

    /// Which surface / enforcement state the demo fixture should present.
    ///
    /// Selected at launch via the `CURFEW_DEMO_SCENARIO` environment variable
    /// (see ``CurfewApp``). Raw values are the stable tokens shared with the
    /// capture harness — `MarketingCaptureTests` and `scripts/capture-*.sh`
    /// pass these exact strings, so renaming a case is a wire-format change.
    ///
    /// Demo mode is compiled only into Debug builds: Release builds neither
    /// ship the fixture nor expose the launch flag, so a notarised app can
    /// never be driven into a seeded, shutdown-disabled state.
    enum DemoScenario: String, CaseIterable {
        /// Main window, Overview pane — status + This Week rollup.
        case overview
        /// Main window, Configuration pane (embedded settings).
        case configuration
        /// Standalone tabbed Settings window.
        case settings
        /// First-run onboarding window.
        case gettingStarted = "getting-started"
        /// Overview pane, used to frame the This Week rollup.
        case thisWeek = "this-week"
        /// Menu bar popover (driven by the capture harness clicking the item).
        case menuBar = "menu-bar"
        /// Pre-lockout warning phase — dim overlay + floating countdown.
        case warning
        /// Full-screen lockout overlay.
        case lockout
        /// Walkthrough scenario used by the video harness.
        case reel

        /// The main-window sidebar section this scenario should open on, or
        /// `nil` when the scenario doesn't pin a section.
        var initialSection: MainWorkspaceSection? {
            switch self {
            case .configuration:
                .configuration
            case .gettingStarted:
                .onboarding
            case .overview, .thisWeek, .menuBar, .warning, .lockout, .reel, .settings:
                .overview
            }
        }

        /// Whether this scenario renders one of the enforcement overlays
        /// (warning dim / lockout) rather than a normal window.
        var showsOverlay: Bool {
            switch self {
            case .warning, .lockout, .reel:
                true
            case .overview, .configuration, .settings, .gettingStarted, .thisWeek, .menuBar:
                false
            }
        }
    }

    /// Pure builders for the curated state a demo launch is seeded with.
    ///
    /// Everything here is a value-typed factory with no I/O so the seeding
    /// logic can be unit-tested directly (see `DemoFixtureTests`). The model
    /// glue that wires these into ephemeral stores lives in
    /// `CurfewAppModel+Demo.swift`.
    enum DemoFixture {
        /// Believable override justification shown in the seeded activity log.
        static let overrideReason =
            "Finishing the launch retrospective deck — investors review it first thing tomorrow."

        /// Encouragement line shown on the demo lockout overlay. Fixed (rather
        /// than rotated) so captures are reproducible.
        static let lockoutMessage = "Great work today. Tomorrow is another day."

        /// Curated settings for a demo launch: a clean 9-to-5 schedule with
        /// onboarding marked complete, auto-shutdown off (defence-in-depth
        /// against the capture machine powering off), and MCP disabled so the
        /// demo process never binds the control sockets.
        static func demoSettings() -> CurfewSettings {
            var settings = CurfewSettings.default
            settings.hasCompletedInitialSetup = true
            settings.autoShutdownEnabled = false
            settings.mcpEnabled = false
            settings.mcpHTTPEnabled = false
            return settings
        }

        /// A week of attractive-but-plausible activity: a three-day lockout
        /// streak, two extensions, and one override. Timestamped relative to
        /// `now` so the events land in the current calendar week that
        /// `CurfewAppModel.thisWeekRollup()` aggregates.
        static func seededActivityEvents(
            now: Date,
            calendar: Calendar = .current
        ) -> [ActivityEvent] {
            let startOfToday = calendar.startOfDay(for: now)
            var events: [ActivityEvent] = []

            // Three consecutive lockout days ending today → streak of 3.
            for dayOffset in [-2, -1, 0] {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                      let lockoutAt = calendar.date(byAdding: .hour, value: 18, to: day)
                else { continue }
                events.append(ActivityEvent(
                    timestamp: lockoutAt,
                    gateKind: GateKind.curfew,
                    kind: .sessionEnded,
                    minutesValue: nil,
                    note: nil
                ))
                events.append(ActivityEvent(
                    timestamp: lockoutAt.addingTimeInterval(60),
                    gateKind: GateKind.curfew,
                    kind: .lockoutStarted,
                    minutesValue: nil,
                    note: nil
                ))
            }

            // Two extensions (15 min each) on two of those days.
            for dayOffset in [-2, 0] {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                      let grantedAt = calendar.date(byAdding: .hour, value: 17, to: day)
                else { continue }
                events.append(ActivityEvent(
                    timestamp: grantedAt,
                    gateKind: GateKind.curfew,
                    kind: .extensionGranted,
                    minutesValue: 15,
                    note: nil
                ))
            }

            // One override yesterday with a believable justification.
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
               let grantedAt = calendar.date(byAdding: .hour, value: 19, to: yesterday) {
                events.append(ActivityEvent(
                    timestamp: grantedAt,
                    gateKind: GateKind.curfew,
                    kind: .overrideGranted,
                    minutesValue: 30,
                    note: overrideReason
                ))
            }

            return events
        }

        /// The "now" presented for a scenario. Pinned to a flattering wall
        /// time on today's date so the lockout clock reads like a real
        /// evening and the Overview countdown looks mid-workday, regardless
        /// of when the capture actually runs.
        static func referenceTime(
            for scenario: DemoScenario,
            now: Date,
            calendar: Calendar = .current
        ) -> Date {
            let (hour, minute): (Int, Int)
            switch scenario {
            case .lockout, .reel:
                (hour, minute) = (22, 47)
            case .warning:
                (hour, minute) = (17, 58)
            case .overview, .configuration, .settings, .gettingStarted, .thisWeek, .menuBar:
                (hour, minute) = (14, 30)
            }
            return dateToday(at: hour, minute: minute, now: now, calendar: calendar) ?? now
        }

        /// The synthetic enforcement evaluation backing a scenario. Demo mode
        /// sets `CurfewAppModel.state` to this directly and never arms the
        /// tick loop, so the engine never overwrites it (and auto-shutdown,
        /// which only advances inside the tick, can never fire).
        static func evaluation(
            for scenario: DemoScenario,
            now: Date,
            calendar: Calendar = .current
        ) -> CurfewEvaluation {
            let unlock = dateTomorrow(at: 7, minute: 0, now: now, calendar: calendar)
                ?? now.addingTimeInterval(8 * 3600)

            switch scenario {
            case .lockout, .reel:
                let lock = dateToday(at: 22, minute: 0, now: now, calendar: calendar)
                    ?? now.addingTimeInterval(-3600)
                return .locked(lockDate: lock, unlockDate: unlock)

            case .warning:
                let lock = dateToday(at: 18, minute: 0, now: now, calendar: calendar)
                    ?? now.addingTimeInterval(120)
                let minutesRemaining = max(1, Int(ceil(lock.timeIntervalSince(now) / 60)))
                return CurfewEvaluation(
                    phase: .warning,
                    warningStage: .twoMinutes,
                    minutesRemaining: min(minutesRemaining, 2),
                    canRequestExtension: false,
                    lockDate: lock,
                    unlockDate: unlock
                )

            case .overview, .configuration, .settings, .gettingStarted, .thisWeek, .menuBar:
                let lock = dateToday(at: 18, minute: 0, now: now, calendar: calendar)
                    ?? now.addingTimeInterval(3 * 3600)
                let minutesRemaining = max(1, Int(ceil(lock.timeIntervalSince(now) / 60)))
                return CurfewEvaluation(
                    phase: .working,
                    warningStage: .none,
                    minutesRemaining: minutesRemaining,
                    canRequestExtension: false,
                    lockDate: lock,
                    unlockDate: unlock
                )
            }
        }

        private static func dateToday(
            at hour: Int,
            minute: Int,
            now: Date,
            calendar: Calendar
        ) -> Date? {
            calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: now
            )
        }

        private static func dateTomorrow(
            at hour: Int,
            minute: Int,
            now: Date,
            calendar: Calendar
        ) -> Date? {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
                return nil
            }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
        }
    }
#endif
