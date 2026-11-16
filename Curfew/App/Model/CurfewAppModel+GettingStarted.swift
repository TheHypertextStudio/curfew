import CurfewKit
import Foundation
import ServiceManagement

/// Step 1's editable schedule: one curfew, one unlock, and which days lock.
struct SetupScheduleDraft: Equatable {
    var lockMinutes: Int
    var unlockMinutes: Int
    var workingDays: Set<Weekday>

    /// Prefills from the current schedule: the first working day's times
    /// (Monday first), and every day that is not a day off.
    static func prefilled(from schedule: WeeklySchedule) -> SetupScheduleDraft {
        let order: [Weekday] = [
            .monday,
            .tuesday,
            .wednesday,
            .thursday,
            .friday,
            .saturday,
            .sunday
        ]
        let working = Set(order.filter { !schedule.rule(for: $0).isDayOff })
        let source = order.first(where: working.contains).map(schedule.rule(for:))
            ?? schedule.rule(for: .monday)
        return SetupScheduleDraft(
            lockMinutes: source.lockMinutes,
            unlockMinutes: source.unlockMinutes,
            workingDays: working
        )
    }

    /// The same times on every day, preserving nothing but the chosen days.
    func schedule(basedOn base: WeeklySchedule) -> WeeklySchedule {
        var next = base
        for day in Weekday.allCases {
            var rule = next.rule(for: day)
            rule.lockMinutes = lockMinutes
            rule.unlockMinutes = unlockMinutes
            rule.isDayOff = !workingDays.contains(day)
            next.rules[day] = rule
        }
        return next
    }
}

/// Keeps first-run progress so setup reopens where the person left it.
struct SetupProgressStore {
    static let key = "curfew.initialSetupProgress.v1"
    let defaults: UserDefaults

    func load() -> InitialSetupProgress? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(InitialSetupProgress.self, from: data)
    }

    func save(_ progress: InitialSetupProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// First-run setup support: health gating, the schedule step, tonight's
/// curfew, the preview's inputs, progress and completion.
@MainActor
extension CurfewAppModel {
    // MARK: Health

    /// Health warnings stay hidden until setup has completed: before then the
    /// person has not been asked for anything, so nothing is "wrong" yet.
    var showsHealthWarnings: Bool {
        settings.hasCompletedInitialSetup
    }

    /// The health every surface shows: the menu bar icon, the popover, Today
    /// and Settings. Enforcement itself keeps using `enforcementHealth`.
    var presentedEnforcementHealth: EnforcementHealth {
        showsHealthWarnings ? enforcementHealth : .active
    }

    /// One plain sentence about what is weaker without the Curfew helper, or
    /// `nil` when it is installed or this build has no helper.
    var helperAbsenceNote: String? {
        guard featureFlags.privilegedHelperEnabled,
              privilegedHelperManager.daemonStatus != .enabled else { return nil }
        return GettingStartedCopy.helperAbsentNote
    }

    /// Opens Privacy & Security, Accessibility, without the system prompt.
    /// The drag panel adds Curfew to the list instead.
    func openAccessibilityPaneForSetup() {
        guard !isDemoSession else { return }
        accessibilityAuthorization.openSettings()
    }

    /// Opens Login Items so the person can approve the Curfew helper.
    func openHelperApprovalSettings() {
        guard !isDemoSession, !RuntimeEnvironment.isUnitTestHost else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: Schedule step

    var setupScheduleDraft: SetupScheduleDraft {
        .prefilled(from: editableSchedule)
    }

    /// Writes step 1 through the ordinary schedule path. Before setup
    /// completes that path applies immediately and arms nothing.
    func applySetupSchedule(_ draft: SetupScheduleDraft) {
        queueScheduleUpdate(draft.schedule(basedOn: editableSchedule))
    }

    /// The next curfew after `now`, or `nil` when setup chose no schedule or
    /// every day is off.
    func nextCurfew(
        after now: Date,
        usesWeeklySchedule: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        guard usesWeeklySchedule else { return nil }
        return Self.nextCurfew(in: settings.schedule, after: now, calendar: calendar)?.lock
    }

    /// Inputs for the lock preview. Reads the schedule; writes nothing.
    func lockPreviewContent(
        now: Date,
        usesWeeklySchedule _: Bool,
        calendar: Calendar = .current
    ) -> LockPreviewContent {
        if let next = Self.nextCurfew(in: settings.schedule, after: now, calendar: calendar) {
            return LockPreviewContent(curfew: next.lock, unlock: next.unlock)
        }
        return LockPreviewContent(curfew: now, unlock: now.addingTimeInterval(13 * 3600))
    }

    nonisolated static func nextCurfew(
        in schedule: WeeklySchedule,
        after now: Date,
        calendar: Calendar
    ) -> (lock: Date, unlock: Date)? {
        let today = calendar.startOfDay(for: now)
        for offset in 0 ... 7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
            else { continue }
            let rule = schedule.rule(for: weekday)
            guard !rule.isDayOff,
                  let lock = calendar.date(
                      bySettingHour: rule.lockMinutes / 60,
                      minute: rule.lockMinutes % 60,
                      second: 0,
                      of: day
                  ),
                  lock > now,
                  let unlockDay = calendar.date(
                      byAdding: .day,
                      value: rule.unlockMinutes <= rule.lockMinutes ? 1 : 0,
                      to: day
                  ),
                  let unlock = calendar.date(
                      bySettingHour: rule.unlockMinutes / 60,
                      minute: rule.unlockMinutes % 60,
                      second: 0,
                      of: unlockDay
                  )
            else { continue }
            return (lock, unlock)
        }
        return nil
    }

    // MARK: Progress and completion

    var setupProgressStore: SetupProgressStore {
        SetupProgressStore(defaults: settingsStore.storageDefaults)
    }

    /// The flow setup should show now: the summary once completed, otherwise
    /// the saved step.
    func loadSetupFlow() -> FirstRunFlow {
        if settings.hasCompletedInitialSetup {
            return .returningUser(isAccessibilityGranted: isAccessibilityTrusted)
        }
        return setupProgressStore.load().map(FirstRunFlow.resuming) ?? FirstRunFlow()
    }

    func saveSetupProgress(_ flow: FirstRunFlow) {
        guard !settings.hasCompletedInitialSetup else { return }
        setupProgressStore.save(flow.progress)
    }

    /// Completes setup with the flow's explicit schedule choice. A returning
    /// person's setup is already complete, so there is nothing to arm.
    @discardableResult
    func commitSetup(
        _ flow: FirstRunFlow,
        confirmedImmediateLock: Bool = false,
        at now: Date = Date()
    ) -> ScheduleActivationOutcome {
        if settings.hasCompletedInitialSetup {
            return .activated
        }
        guard let choice = flow.scheduleChoice else { return .unavailable }
        let outcome = completeInitialSetup(
            choice: choice,
            confirmedImmediateLock: confirmedImmediateLock,
            at: now
        )
        if outcome == .activated {
            setupProgressStore.clear()
        }
        return outcome
    }

    /// Closes setup and opens Today.
    func finishGettingStarted() {
        dismissGettingStarted()
        appRouter.openWindow(id: MainWorkspaceSection.windowID)
    }
}
