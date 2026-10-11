import Combine
import CurfewKit
import EventKit
import Foundation

/// Surfaces today's calendar events so the lockout screen and This Week view
/// can show contextual scheduling information. Read-only — Curfew never
/// writes to the user's calendar.
///
/// This is a Pro feature gated by `FeatureFlags.calendarEnabled` +
/// `LicenseGate.isProUnlocked`. When either gate is closed the store is never
/// started and all published properties remain at their empty defaults.
@MainActor
final class CalendarMonitor: ObservableObject {
    /// Authorisation state for EventKit calendar access.
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    /// Today's non-all-day events from selected calendars, sorted by start time.
    @Published private(set) var todayEvents: [EKEvent] = []

    /// Whether any event is currently in progress.
    @Published private(set) var hasCurrentEvent: Bool = false

    /// The next upcoming (future) event today, if any.
    @Published private(set) var nextEvent: EKEvent?

    // MARK: - Private

    private let store = EKEventStore()
    private var refreshTimer: Timer?

    /// `nonisolated` so `CurfewAppModel` can store the monitor as a
    /// non-optional default without round-tripping to `MainActor` during
    /// its own synchronous init. All mutation of published state happens
    /// on the main actor via the instance methods.
    nonisolated init() {}

    // MARK: - Lifecycle

    /// Requests EventKit access (if not already granted) and performs an
    /// initial sync. Safe to call more than once — subsequent calls only
    /// re-sync if access is already granted.
    func requestAccessAndSync() {
        let current = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = current

        switch current {
        case .fullAccess, .writeOnly:
            sync()
            scheduleRefresh()
        case .notDetermined:
            Task {
                do {
                    if #available(macOS 14.0, *) {
                        try await store.requestFullAccessToEvents()
                    } else {
                        try await store.requestAccess(to: .event)
                    }
                    await MainActor.run {
                        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                        sync()
                        scheduleRefresh()
                    }
                } catch {
                    await MainActor.run {
                        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                    }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    /// Cancels the 5-minute refresh timer. Called when the Pro gate closes
    /// (license deactivated or flag turned off) so an unlicensed install
    /// stops polling EventKit entirely.
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Sync

    /// Pulls today's events from EventKit and refreshes the `todayEvents`,
    /// `hasCurrentEvent`, and `nextEvent` publishers. Called on initial
    /// authorisation and every 5 minutes from the refresh timer. All-day
    /// events are filtered out because they don't carry scheduling intent
    /// relevant to curfew.
    func sync() {
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let predicate = store.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: nil
        )

        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        todayEvents = events

        hasCurrentEvent = events.contains { event in
            guard let start = event.startDate, let end = event.endDate else { return false }
            return start <= now && end > now
        }

        nextEvent = events.first { event in
            guard let start = event.startDate else { return false }
            return start > now
        }
    }

    // MARK: - Curfew-overlap detection

    /// Returns the first event whose start time falls within `windowMinutes`
    /// before the curfew end-of-day gate at `scheduleEndMinutes` from midnight.
    ///
    /// Used by the tick loop to offer a proactive extension prompt ("you have
    /// a meeting starting at 22:00 — curfew fires in 45 min, want to extend?")
    /// before the user hits a surprise lockout. Returns `nil` when:
    /// - no events are loaded,
    /// - no event starts within the overlap window,
    /// - the event has already started.
    func eventNearingCurfew(
        scheduleEndMinutes: Int,
        now: Date,
        windowMinutes: Int = 60
    ) -> EKEvent? {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: now)
        let curfewTime = midnight.addingTimeInterval(TimeInterval(scheduleEndMinutes * 60))
        let windowStart = curfewTime.addingTimeInterval(-TimeInterval(windowMinutes * 60))

        return todayEvents.first { event in
            guard let start = event.startDate else { return false }
            // Only future events — already-running meetings are surfaced
            // separately via `hasCurrentEvent`.
            return start > now && start >= windowStart && start < curfewTime
        }
    }

    // MARK: - Private

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
    }
}
