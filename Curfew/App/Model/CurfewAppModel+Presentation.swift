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
    /// SF Symbol name representing the current phase. Surfaces in the menu
    /// bar.
    ///
    /// When enforcement is degraded (Accessibility revoked or the keyboard
    /// shield's tap is down) the phase glyph is replaced by the warning badge
    /// so a silently broken lockout cannot look like business as usual.
    var menuBarSymbolName: String {
        if enforcementHealth != .active {
            return enforcementHealth.menuBarBadgeSymbol ?? "exclamationmark.triangle.fill"
        }
        return symbolName(for: state.phase)
    }

    /// One-line description of the current phase for the status bar and
    /// popover header.
    var statusLine: String {
        statusLine(for: state.phase)
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
            statusLine: statusLine(for: state.phase),
            timeRemainingText: timeRemainingText(for: state.minutesRemaining),
            scheduleWindowText: scheduleWindowText,
            scheduleSummarySentence: scheduleSummarySentence,
            pendingScheduleDescription: pendingScheduleDescription,
            canRequestExtension: state.canRequestExtension,
            extensionRequestTitle: extensionRequestTitle,
            extensionsRemaining: extensionsRemaining
        )
    }

    /// Full button label for the extension hold button, e.g.
    /// `"Hold 2s for +15m extension"`.
    var extensionRequestTitle: String {
        let holdSeconds = Int(Self.extensionConfirmationHoldSeconds)
        let minutes = settings.extensionDurationMinutes
        return "Hold \(holdSeconds)s for +\(minutes)m extension"
    }

    /// The schedule the user is currently editing. Returns the pending
    /// proposed schedule when a change is in flight, otherwise the active one.
    var editableSchedule: WeeklySchedule {
        settings.pendingScheduleChange?.proposedSchedule ?? settings.schedule
    }

    /// One-sentence summary of any queued schedule change, shown above
    /// the menu-bar popover and the overview pane. `nil` when no change
    /// is pending.
    var pendingScheduleDescription: String? {
        guard let pending = settings.pendingScheduleChange else {
            return nil
        }
        let timestamp = pending.effectiveAt.formatted(date: .abbreviated, time: .shortened)
        switch pending.classification {
        case .weaker:
            return "A less strict schedule is queued for \(timestamp)."
        case .stricter:
            return "A stricter schedule is queued for \(timestamp)."
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

    /// One-line status copy for `phase`, used in the menu bar tooltip and
    /// the snapshot's `statusLine`.
    func statusLine(for phase: EnforcementPhase) -> String {
        switch phase {
        case .working:
            "Working window active"
        case .warning:
            "Wrap up time"
        case .locked:
            "Curfew lockout active"
        case .dayOff:
            "Day off"
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
