import EventKit
import Foundation
import UserNotifications

/// The "a meeting is about to collide with curfew" prompt.
///
/// Lifted out of `CurfewAppModel+Lifecycle.swift` unchanged — same behaviour,
/// same call site, one tick-loop line — because it is a self-contained,
/// Pro-gated calendar feature rather than part of the enforcement core, and
/// the lifecycle file had reached its file-length budget.
@MainActor
extension CurfewAppModel {
    /// Fires one notification per event when a calendar event starts
    /// within 60 min of the curfew gate during working/warning phases.
    /// No-ops when calendar is off, Pro isn't unlocked, no event is
    /// in the window, or we've already prompted for this event today.
    func checkCalendarCurfewOverlap() {
        guard featureFlags.calendarEnabled, licenseGate.isProUnlocked else { return }
        guard state.phase == .working || state.phase == .warning else { return }

        let todayRule = settings.schedule.rule(for: Weekday(from: currentTime))
        guard !todayRule.isDayOff else { return }

        guard let event = calendarMonitor.eventNearingCurfew(
            scheduleEndMinutes: todayRule.lockMinutes,
            now: currentTime
        ) else { return }

        let eventID = event.eventIdentifier ?? event.title ?? ""
        guard eventID != curfewOverlapPromptFiredForEventID else { return }
        curfewOverlapPromptFiredForEventID = eventID

        let content = UNMutableNotificationContent()
        content.title = "Meeting near curfew"
        let title = event.title ?? "A meeting"
        let startText = event.startDate.map {
            $0.formatted(date: .omitted, time: .shortened)
        } ?? "soon"
        content.body = "\(title) starts at \(startText). "
            + "Request an extension before curfew fires."
        content.categoryIdentifier = "CALENDAR_OVERLAP"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "curfew.calendar-overlap.\(eventID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
