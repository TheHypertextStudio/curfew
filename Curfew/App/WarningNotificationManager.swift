import Foundation
import UserNotifications

struct WarningNotificationPayload: Equatable {
    let title: String
    let body: String
    let categoryIdentifier: String
    let playsSound: Bool
}

struct WarningNotificationCategoryDefinition: Equatable {
    let identifier: String
    let actionIdentifiers: [String]
}

@MainActor
final class WarningNotificationManager: NSObject {
    static let warningCategoryIdentifier = "CURFEW_WARNING"
    static let warningSnoozeCategoryIdentifier = "CURFEW_WARNING_SNOOZE"
    static let snoozeActionIdentifier = "SNOOZE_ONE_MIN"

    private let center: UNUserNotificationCenter
    private var lastDeliveredStage: WarningStage = .none
    private var deliveredDayToken: String = ""
    var onSnoozeRequested: (() -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
        registerCategories()
    }

    func requestPermissionIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // Permission failures are non-fatal for enforcement.
        }
    }

    func update(stage: WarningStage, now: Date, calendar: Calendar = .current) {
        let dayToken = Self.dayToken(for: now, calendar: calendar)

        if dayToken != deliveredDayToken {
            deliveredDayToken = dayToken
            lastDeliveredStage = .none
        }

        guard stage != lastDeliveredStage else {
            return
        }

        if let content = notificationContent(for: stage) {
            let request = UNNotificationRequest(
                identifier: "curfew.warning.\(stage)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
        lastDeliveredStage = stage
    }

    private static func dayToken(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

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

extension WarningNotificationManager: UNUserNotificationCenterDelegate {
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
