import Foundation
import UserNotifications

/// Pure data bundle describing a single warning notification. Separated from
/// `UNMutableNotificationContent` so the payload can be constructed and
/// asserted in tests without a `UNUserNotificationCenter`.
struct WarningNotificationPayload: Equatable {
    /// Short title displayed in the notification banner.
    let title: String
    /// Body copy shown beneath the title.
    let body: String
    /// `UNNotificationCategory` identifier controlling available actions.
    let categoryIdentifier: String
    /// Whether the system should play the default alert sound.
    let playsSound: Bool
}

/// Defines a `UNNotificationCategory` by its identifier and action list.
/// Registered once at startup; referenced by `categoryIdentifier` in payloads.
struct WarningNotificationCategoryDefinition: Equatable {
    /// Opaque category identifier referenced from payloads.
    let identifier: String
    /// Ordered list of action identifiers attached to this category. Each
    /// identifier is resolved to a `UNNotificationAction` at registration time.
    let actionIdentifiers: [String]
}

/// Delivers `UNUserNotification` banners for each ``WarningStage`` transition
/// and routes the snooze action back to the app model.
///
/// One notification fires per stage per calendar day — the manager tracks
/// `lastDeliveredStage` and `deliveredDayToken` so a stage that has already
/// fired today is never re-delivered even if the tick loop re-evaluates it.
/// Day rollover resets both sentinels.
///
/// The `NSObject` + `UNUserNotificationCenterDelegate` pattern is required
/// by `UNUserNotificationCenter` for the delegate callback.
@MainActor
final class WarningNotificationManager: NSObject {
    /// Category for non-snooze warnings (T-5, T-2, T-1, lockout).
    static let warningCategoryIdentifier = "CURFEW_WARNING"

    /// Category for warnings that offer a snooze action (T-30, T-15).
    static let warningSnoozeCategoryIdentifier = "CURFEW_WARNING_SNOOZE"

    /// Action identifier for the "Snooze 1 min" button on snooze-category
    /// notifications. Matched in `userNotificationCenter(_:didReceive:)`.
    static let snoozeActionIdentifier = "SNOOZE_ONE_MIN"

    private let center: UNUserNotificationCenter
    private var lastDeliveredStage: WarningStage = .none
    private var deliveredDayToken: String = ""

    /// Called on `@MainActor` when the user taps the snooze action. The model
    /// wires this to `requestNotificationSnooze()`.
    var onSnoozeRequested: (() -> Void)?

    /// Creates a manager backed by `center`. Production uses the default
    /// `.current()` singleton; tests can inject a stub to capture add/remove
    /// calls without touching the user's notification permissions.
    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
        registerCategories()
    }

    /// Requests alert + sound + badge authorisation if not yet granted.
    /// Non-fatal: enforcement continues even if the user denies.
    func requestPermissionIfNeeded() {
        // Skip in a unit-test host: a test build is re-signed each run, so
        // requesting Notifications authorization re-prompts the developer on
        // every run. No test asserts this request; production requests normally.
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // Permission failures are non-fatal for enforcement.
        }
    }

    /// Delivers a notification for `stage` if it hasn't already fired today.
    /// Resets the day sentinel on calendar rollover. Called once per tick.
    ///
    /// - Parameter alreadyFiredElsewhere: Tokens for warning stages the
    ///   cross-device `LockoutState` record shows have already fired on
    ///   another Mac today. A stage present in this set is suppressed —
    ///   the least-surprising behaviour for a user opening a second Mac
    ///   mid-escalation ("don't re-send a T-30 alarm I already saw").
    ///   Empty set keeps the single-device path unchanged.
    func update(
        stage: WarningStage,
        now: Date,
        calendar: Calendar = .current,
        alreadyFiredElsewhere: Set<String> = []
    ) {
        let dayToken = Self.dayToken(for: now, calendar: calendar)

        if dayToken != deliveredDayToken {
            deliveredDayToken = dayToken
            lastDeliveredStage = .none
        }

        guard stage != lastDeliveredStage else {
            return
        }

        if let content = notificationContent(for: stage),
           !alreadyFiredElsewhere.contains(Self.token(for: stage)) {
            let request = UNNotificationRequest(
                identifier: "curfew.warning.\(stage)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
        lastDeliveredStage = stage
    }

    /// Stable string token for a `WarningStage`, shared by the
    /// `LockoutState` CloudKit record so publishers and consumers agree
    /// on the vocabulary without leaking the enum across module boundaries.
    static func token(for stage: WarningStage) -> String {
        switch stage {
        case .none: "none"
        case .thirtyMinutes: "T-30"
        case .fifteenMinutes: "T-15"
        case .fiveMinutes: "T-5"
        case .twoMinutes: "T-2"
        case .oneMinute: "T-1"
        case .lockout: "lockout"
        }
    }

    private static func dayToken(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    /// Returns the notification payload for `stage`, or `nil` for `.none`
    /// (no notification when outside the warning window). Exposed as `static`
    /// so tests can verify copy and sound policy without a live center.
    static func payload(for stage: WarningStage) -> WarningNotificationPayload? {
        switch stage {
        case .thirtyMinutes:
            WarningNotificationPayload(
                title: "Curfew",
                body: "30 minutes of work time left.",
                categoryIdentifier: warningSnoozeCategoryIdentifier,
                playsSound: false
            )
        case .fifteenMinutes:
            WarningNotificationPayload(
                title: "Curfew",
                body: "15 minutes left. Start wrapping up.",
                categoryIdentifier: warningSnoozeCategoryIdentifier,
                playsSound: false
            )
        case .fiveMinutes:
            WarningNotificationPayload(
                title: "Curfew",
                body: "5 minutes left. Save your work now.",
                categoryIdentifier: warningCategoryIdentifier,
                playsSound: true
            )
        case .twoMinutes:
            WarningNotificationPayload(
                title: "Curfew",
                body: "2 minutes remaining.",
                categoryIdentifier: warningCategoryIdentifier,
                playsSound: true
            )
        case .oneMinute:
            WarningNotificationPayload(
                title: "Curfew",
                body: "1 minute left. Final save.",
                categoryIdentifier: warningCategoryIdentifier,
                playsSound: true
            )
        case .lockout:
            WarningNotificationPayload(
                title: "Curfew Active",
                body: "Lockout has started. See you in the morning.",
                categoryIdentifier: warningCategoryIdentifier,
                playsSound: true
            )
        case .none:
            nil
        }
    }

    /// Returns the two category definitions used by this manager. Exposed as
    /// `static` so tests can verify category / action wiring without a live center.
    static func categoryDefinitions() -> [WarningNotificationCategoryDefinition] {
        [
            WarningNotificationCategoryDefinition(
                identifier: warningSnoozeCategoryIdentifier,
                actionIdentifiers: [snoozeActionIdentifier]
            ),
            WarningNotificationCategoryDefinition(
                identifier: warningCategoryIdentifier,
                actionIdentifiers: []
            )
        ]
    }

    private func notificationContent(for stage: WarningStage) -> UNMutableNotificationContent? {
        guard let payload = Self.payload(for: stage) else {
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.categoryIdentifier = payload.categoryIdentifier
        if payload.playsSound {
            content.sound = .default
        }
        return content
    }

    private func registerCategories() {
        let categories = Self.categoryDefinitions().map { definition in
            let actions = definition.actionIdentifiers
                .compactMap { identifier -> UNNotificationAction? in
                    if identifier == Self.snoozeActionIdentifier {
                        return UNNotificationAction(
                            identifier: Self.snoozeActionIdentifier,
                            title: "Snooze 1 min",
                            options: []
                        )
                    }
                    return nil
                }
            return UNNotificationCategory(
                identifier: definition.identifier,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
        }
        center.setNotificationCategories(Set(categories))
    }
}

/// Delegate conformance that routes notification responses (snooze
/// taps, tap-to-open) back into the app model on the main actor.
extension WarningNotificationManager: UNUserNotificationCenterDelegate {
    /// Routes the snooze action back to the app model on `@MainActor`.
    /// Other action identifiers (none today) are ignored. The completion
    /// handler is called unconditionally so the system retires the
    /// response — skipping it leaves the notification hanging in Notification
    /// Center forever.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if response.actionIdentifier == Self.snoozeActionIdentifier {
                onSnoozeRequested?()
            }
            completionHandler()
        }
    }
}
