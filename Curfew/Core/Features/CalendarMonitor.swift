import AppKit
import Combine
import CurfewKit
import EventKit
import Foundation
import Observation

/// Surfaces today's calendar events so the lockout screen and This Week view
/// can show contextual scheduling information. Read-only — Curfew never
/// writes to the user's calendar.
///
/// This is a Plus feature gated by `FeatureFlags.calendarEnabled` +
/// `LicenseGate.isPlusUnlocked`. When either gate is closed the store is never
/// started and all published properties remain at their empty defaults.
@MainActor
@Observable
final class CalendarMonitor {
    /// Authorisation state for EventKit calendar access.
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    /// Today's non-all-day events from selected calendars, sorted by start time.
    private(set) var todayEvents: [EKEvent] = []

    /// Whether any event is currently in progress.
    private(set) var hasCurrentEvent: Bool = false

    /// The next upcoming (future) event today, if any.
    private(set) var nextEvent: EKEvent?

    #if DEBUG
        func seedDemoAuthorization(_ status: EKAuthorizationStatus) {
            authorizationStatus = status
        }
    #endif

    // MARK: - Private

    private let source: CalendarEventSource
    private let authorization: (@Sendable () -> EKAuthorizationStatus)?
    private var refreshTimer: Timer?
    private var activationObserver: AnyCancellable?
    private var permissionRequest: Task<Void, Never>?
    private var sessionID = UUID()
    private var isMonitoring = false

    /// `nonisolated` so `CurfewAppModel` can store the monitor as a
    /// non-optional default without round-tripping to `MainActor` during
    /// its own synchronous init. All mutation of published state happens
    /// on the main actor via the instance methods.
    nonisolated init(
        source: CalendarEventSource = SystemCalendarEventSource(),
        authorization: (@Sendable () -> EKAuthorizationStatus)? = nil
    ) {
        self.source = source
        self.authorization = authorization
    }

    // MARK: - Lifecycle

    /// Requests EventKit access (if not already granted) and performs an
    /// initial sync. Safe to call more than once — subsequent calls only
    /// re-sync if access is already granted.
    func requestAccessAndSync() {
        if !isMonitoring {
            isMonitoring = true
            sessionID = UUID()
            scheduleRefresh()
            activationObserver = NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            ).sink { [weak self] _ in
                self?.sync()
            }
        }
        sync()
        guard authorizationStatus == .notDetermined || authorizationStatus == .writeOnly,
              permissionRequest == nil else { return }

        let requestSession = sessionID
        permissionRequest = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await source.requestFullAccess()
            } catch {
                // Permission failures still require a live status refresh, but
                // must never resume a monitoring session that has stopped.
            }
            guard !Task.isCancelled, isMonitoring, sessionID == requestSession else { return }
            permissionRequest = nil
            sync()
        }
    }

    /// Stops polling and invalidates any pending permission reply. Cached
    /// meetings must not remain visible after the feature or license gate closes.
    func stop() {
        isMonitoring = false
        sessionID = UUID()
        permissionRequest?.cancel()
        permissionRequest = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        activationObserver = nil
        clearEvents()
    }

    // MARK: - Sync

    /// Pulls today's events from EventKit and refreshes the `todayEvents`,
    /// `hasCurrentEvent`, and `nextEvent` publishers. Called on initial
    /// authorisation and every 5 minutes from the refresh timer. All-day
    /// events are filtered out because they don't carry scheduling intent
    /// relevant to curfew.
    func sync() {
        authorizationStatus = authorization?() ?? source.authorizationStatus
        guard isMonitoring, authorizationStatus == .fullAccess else {
            clearEvents()
            return
        }
        let readSession = sessionID
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let events = source.events(from: startOfDay, to: endOfDay)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        // A provider can observe revocation while fetching. Discard the result
        // rather than publish meetings from an obsolete permission or session.
        authorizationStatus = authorization?() ?? source.authorizationStatus
        guard isMonitoring, sessionID == readSession, authorizationStatus == .fullAccess else {
            clearEvents()
            return
        }
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
        guard isMonitoring, source.authorizationStatus == .fullAccess else {
            authorizationStatus = authorization?() ?? source.authorizationStatus
            clearEvents()
            return nil
        }
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

    private func clearEvents() {
        todayEvents = []
        hasCurrentEvent = false
        nextEvent = nil
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
    }
}
