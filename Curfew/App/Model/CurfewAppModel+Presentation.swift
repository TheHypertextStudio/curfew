import CurfewKit
import Foundation

/// View-facing surface of `CurfewAppModel`.
///
/// Everything in this extension is a derivation of the model's stored state —
/// no side effects, no I/O. UI layers read these computed properties instead
/// of inspecting `state.phase`/`state.minutesRemaining` directly, so the
/// formatting rules (status copy, `H:MM` padding, schedule-window arrows)
/// live in one place and stay consistent across menu bar, main window,
/// lockout overlay, and widgets.
@MainActor
extension CurfewAppModel {
    /// The words this surface speaks. One value, so a voice pack can swap it.
    var voice: TodayVoice {
        .standard
    }

    /// The override that is holding the lock open right now, if any.
    var activeOverrideUntil: Date? {
        (accountReleaseOverrideUntil() ?? overrideUntil).flatMap { $0 > currentTime ? $0 : nil }
    }

    /// The next moment the Mac locks, as the person should read it: the
    /// schedule's curfew (with any extension), or the moment an override that
    /// re-locks tonight ends. `nil` outside a working window and whenever the
    /// only known curfew is already in the past, so no surface names a past time.
    var upcomingCurfew: Date? {
        guard state.phase == .working || state.phase == .warning else { return nil }
        if let release = activeOverrideUntil, let lock = state.lockDate,
           let unlock = state.unlockDate, release > lock, release < unlock {
            return release
        }
        guard let lock = state.lockDate, lock > currentTime else { return nil }
        return lock
    }

    /// The end of an override that does not re-lock tonight, while it lasts.
    var overrideReleaseEnd: Date? {
        guard upcomingCurfew == nil, state.phase == .working || state.phase == .warning else {
            return nil
        }
        return activeOverrideUntil
    }

    /// Menu bar status: the curfew, the minutes left, or the unlock.
    var menuBarHeaderLine: String {
        guard isEnforcementRunning else { return voice.menuCurfewOff }
        if settings.hasCompletedInitialSetup,
           !automaticScheduleEnabled, state.phase != .locked {
            return "Automatic schedule off"
        }
        return statusLine
    }

    /// The menu bar item's spoken name: the app, then the time left.
    var menuBarAccessibilityLabel: String {
        let name = "Curfew\(CurfewFlavor.current.displaySuffix)"
        if isEnforcementRunning, let curfew = upcomingCurfew {
            let left = TodayVoice.spokenDuration(curfew.timeIntervalSince(currentTime))
            return "\(name), \(left) left"
        }
        return "\(name), \(menuBarHeaderLine)"
    }

    /// The drawn menu bar icon's state: lower as curfew nears, on the line in
    /// the last half hour, no sun while locked.
    var menuBarGlyphState: HorizonMenuBarGlyph.State {
        HorizonMenuBarGlyph.State.resolve(
            isLocked: state.phase == .locked,
            isSunrise: reflectionState.isDaybreakPresented,
            minutesToCurfew: isEnforcementRunning
                ? upcomingCurfew.map { $0.timeIntervalSince(currentTime) / 60 } : nil
        )
    }

    /// SF Symbol shown in place of the drawn icon while enforcement is
    /// degraded, so a silently broken lock cannot look like business as usual.
    var menuBarSymbolName: String {
        if presentedEnforcementHealth != .active {
            return presentedEnforcementHealth.menuBarBadgeSymbol ?? "exclamationmark.triangle.fill"
        }
        return symbolName(for: state.phase)
    }

    /// One-line description of the current phase for the menu bar and the
    /// snapshot.
    var statusLine: String {
        if settings.hasCompletedInitialSetup,
           !automaticScheduleEnabled, state.phase != .locked {
            return "Remote controls only"
        }
        return statusLine(for: state.phase)
    }

    /// `H:MM` string of minutes remaining, or `"—"` when not applicable.
    var timeRemainingText: String {
        timeRemainingText(for: state.minutesRemaining)
    }

    /// Denormalised read-model consumed by every UI surface. Assembled once
    /// per tick from the model's stored state.
    var snapshot: EnforcementSnapshot {
        EnforcementSnapshot(
            phase: state.phase,
            symbolName: symbolName(for: state.phase),
            statusLine: statusLine,
            timeRemainingText: timeRemainingText(for: state.minutesRemaining),
            scheduleWindowText: scheduleWindowText,
            scheduleSummarySentence: scheduleSummarySentence,
            pendingScheduleDescription: pendingScheduleDescription,
            canRequestExtension: state.canRequestExtension,
            extensionRequestTitle: extensionRequestTitle,
            extensionsRemaining: extensionsRemaining
        )
    }

    /// The label of the control that asks for more time.
    var extensionRequestTitle: String {
        voice.moreTime
    }

    /// Everything Today and the menu bar popover show, resolved from the
    /// model in one place.
    var todayPresentation: TodayPresentation {
        TodayPresentation.resolve(TodaySituation(
            setupComplete: settings.hasCompletedInitialSetup,
            enforcing: isEnforcementRunning,
            phase: state.phase,
            warningStage: state.warningStage,
            minutesRemaining: state.minutesRemaining,
            upcomingCurfew: upcomingCurfew,
            unlockDate: state.unlockDate,
            overrideEnds: overrideReleaseEnd,
            canRequestExtension: state.canRequestExtension,
            extensionsRemaining: extensionsRemaining,
            canCallItADay: canCallItADay
        ), voice: voice)
    }

    /// The schedule the user is currently editing. Returns the pending
    /// proposed schedule when a change is in flight, otherwise the active one.
    var editableSchedule: WeeklySchedule {
        settings.pendingScheduleChange?.proposedSchedule ?? settings.schedule
    }

    /// Only this schedule is evaluated for automatic lockout. The configured
    /// rules remain available for editing while local consent is off.
    var effectiveSchedule: WeeklySchedule {
        automaticScheduleEnabled ? settings.schedule : .allDaysOff
    }

    /// Warn before a lock that would start now or during the arming tick.
    var scheduleWouldLockNow: Bool {
        scheduleMayLockOnArming(at: Date())
    }

    /// Leave one minute of margin for the first tick to cross a lock boundary
    /// after consent is persisted. An imminent lock requires the same explicit
    /// acknowledgement as an already-active schedule window.
    func scheduleMayLockOnArming(at now: Date) -> Bool {
        scheduleWouldLock(at: now) || scheduleWouldLock(at: now.addingTimeInterval(60))
    }

    /// Evaluates the saved schedule at an exact instant, independent of the
    /// currently inactive automatic-schedule consent.
    func scheduleWouldLock(at now: Date) -> Bool {
        enforcementEngine.evaluate(
            at: now,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: extensionMinutesGrantedToday + snoozeMinutesGrantedToday,
            overrideUntil: accountReleaseOverrideUntil() ?? overrideUntil,
            warningIntervals: settings.warningIntervals,
            workedMinutesToday: workedMinutesToday(at: now)
        ).phase == .locked
    }

    /// One-sentence summary of any queued schedule change, shown above
    /// the menu-bar popover and the overview pane. `nil` when no change
    /// is pending.
    var pendingScheduleDescription: String? {
        guard let pending = settings.pendingScheduleChange else {
            return nil
        }
        let day = pending.effectiveAt.formatted(.dateTime.month(.abbreviated).day())
        switch pending.classification {
        case .weaker:
            return voice.laterCurfew(startingOn: day)
        case .stricter:
            return voice.earlierCurfew(startingOn: day)
        case .noChange:
            return nil
        }
    }

    /// Natural-language sentence describing tomorrow's enforcement window.
    var scheduleSummarySentence: String {
        editableSchedule.summarySentence(forNextDayFrom: currentTime)
    }

    /// Today's lock → unlock window formatted as `"18:00 -> 08:00"`, or a
    /// no-enforcement message on a day off.
    var scheduleWindowText: String {
        guard let lockDate = state.lockDate, let unlockDate = state.unlockDate else {
            return "No enforcement window is active today."
        }
        let lockText = lockDate.formatted(date: .omitted, time: .shortened)
        let unlockText = unlockDate.formatted(date: .omitted, time: .shortened)
        return "\(lockText) -> \(unlockText)"
    }

    /// `true` when both override gates pass: the reason is long enough and the
    /// weekly budget is non-zero.
    var canConfirmOverride: Bool {
        OverrideRequestPolicy.canConfirm(
            reason: overrideReasonDraft,
            overridesRemaining: overridesRemaining,
            requestedAt: overrideRequestedAt,
            now: currentTime
        )
    }

    var overrideCooldownRemaining: TimeInterval {
        OverrideRequestPolicy.cooldownRemaining(
            requestedAt: overrideRequestedAt,
            now: currentTime
        )
    }

    /// SF Symbol name for `phase`. Used in the menu bar icon and snapshot.
    func symbolName(for phase: EnforcementPhase) -> String {
        switch phase {
        case .working:
            "clock.badge.checkmark"
        case .warning:
            "exclamationmark.triangle"
        case .locked:
            "lock.fill"
        case .dayOff:
            "moon.zzz"
        }
    }

    /// One-line status copy for `phase` at the model's current dates, used in
    /// the menu bar and the snapshot's `statusLine`. Times use the locale.
    func statusLine(for phase: EnforcementPhase) -> String {
        switch phase {
        case .working:
            if let curfew = upcomingCurfew {
                return voice.curfewAt(TodayVoice.time(curfew))
            }
            if let release = overrideReleaseEnd {
                return voice.overrideUntil(TodayVoice.time(release))
            }
            return voice.menuNoCurfew
        case .warning:
            return voice.curfewIn(minutes: max(1, state.minutesRemaining))
        case .locked:
            return state.unlockDate.map { voice.lockedUntil(TodayVoice.time($0)) }
                ?? voice.menuLocked
        case .dayOff:
            return voice.menuNoCurfew
        }
    }

    /// Formats `minutesRemaining` as `H:MM`. Returns `"—"` for `Int.max`
    /// (day off or locked — no meaningful countdown).
    func timeRemainingText(for minutesRemaining: Int) -> String {
        if minutesRemaining == .max {
            return "—"
        }
        let minutes = max(0, minutesRemaining)
        let hoursComponent = minutes / 60
        let minuteComponent = minutes % 60
        return String(format: "%d:%02d", hoursComponent, minuteComponent)
    }

    /// Exports activity events within `range` as a CSV string.
    /// Delegates to `ActivityStore.exportCSV(in:)` via the recorder's backing store.
    /// Returns an empty header-only CSV string when the store is unavailable.
    func exportActivityCSV(in range: ClosedRange<Date>) -> String {
        (try? activityRecorder.exportCSV(
            in: range
        )) ?? "id,timestamp,gate_kind,kind,minutes_value,note"
    }

    /// Returns the rollup of this calendar week relative to `currentTime`.
    ///
    /// "This week" is anchored on the user's `Calendar.current.firstWeekday`
    /// rather than Curfew's own `resetWeekday` — the retrospective is a
    /// calendar view, not a budget view. The two happen to match for the
    /// default configuration (Monday) but will diverge if a user picks a
    /// different reset day.
    ///
    /// Memoised on `(weekStart, activityRecorder.mutationCount)` so the
    /// 1 Hz tick loop does not rerun the SQLite query every second while
    /// `ThisWeekView` is visible. Cache invalidates on week boundary
    /// crossings and on every activity write.
    func thisWeekRollup() -> WeeklyActivityRollup {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: currentTime)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(
            byAdding: .day,
            value: -daysBack,
            to: startOfDay
        ) ?? startOfDay
        let weekEnd = calendar.date(
            byAdding: .day,
            value: 7,
            to: weekStart
        ) ?? weekStart

        let key = ThisWeekCacheKey(
            weekStart: weekStart,
            mutationCount: activityRecorder.mutationCount
        )
        if let cached = cachedThisWeekRollup, cachedThisWeekKey == key {
            return cached
        }

        let events = activityRecorder.events(in: weekStart ... weekEnd)
        let rollup = ActivityRollups.weeklyRollup(
            events: events,
            weekStart: weekStart,
            calendar: calendar
        )
        cachedThisWeekKey = key
        cachedThisWeekRollup = rollup
        return rollup
    }

    /// Per-device override counts for the current calendar week. Drives
    /// the "device-attributed insights" surface in `ThisWeekView` and the
    /// `devices` field on the `curfew.get_weekly_summary` MCP response.
    ///
    /// Today every override is attributed to the local Mac because
    /// `OverrideEvent.deviceName` is stamped at grant time; once
    /// cross-device CloudKit delivery of override events lands, the same
    /// aggregation surfaces every Mac the user has overridden from in
    /// the past week.
    func overridesByDeviceThisWeek() -> [String: Int] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: currentTime)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(
            byAdding: .day,
            value: -daysBack,
            to: startOfDay
        ) ?? startOfDay
        let weekEnd = calendar.date(
            byAdding: .day,
            value: 7,
            to: weekStart
        ) ?? weekStart

        var counts: [String: Int] = [:]
        for event in overrideEvents
            where event.timestamp >= weekStart && event.timestamp < weekEnd {
            counts[event.deviceName, default: 0] += 1
        }
        return counts
    }
}

/// Cache key pair for ``CurfewAppModel/thisWeekRollup()`` — declared at
/// file scope (not nested) so it can be `Equatable` without pulling
/// `CurfewAppModel` into Swift's actor inference.
struct ThisWeekCacheKey: Equatable {
    /// Monday-aligned start of the rollup's coverage window.
    let weekStart: Date
    /// `ActivityRecorder.mutationCount` observed when the cache entry
    /// was built. A change invalidates the cache.
    let mutationCount: Int
}
