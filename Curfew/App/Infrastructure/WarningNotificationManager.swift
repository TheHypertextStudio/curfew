import CurfewKit
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

@MainActor
protocol WarningNotificationManaging: AnyObject {
    var onSnoozeRequested: (() -> Void)? { get set }
    /// The voice notifications speak in; the model keeps it current.
    var voice: VoicePack { get set }
    func requestPermissionIfNeeded()
    func update(
        stage: WarningStage,
        now: Date,
        alreadyFiredElsewhere: Set<String>
    )
    func deliverDistractionNudge()
}

@MainActor
final class NoOpWarningNotificationManager: WarningNotificationManaging {
    var onSnoozeRequested: (() -> Void)?
    var voice = VoicePack.standard

    func requestPermissionIfNeeded() {}

    func update(
        stage _: WarningStage,
        now _: Date,
        alreadyFiredElsewhere _: Set<String>
    ) {}

    func deliverDistractionNudge() {}
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
    /// Category for non-snooze warnings (T-5, T-2, T-1).
    static let warningCategoryIdentifier = "CURFEW_WARNING"

    /// Category for warnings that offer a snooze action (T-30, T-15).
    static let warningSnoozeCategoryIdentifier = "CURFEW_WARNING_SNOOZE"

    /// Action identifier for the "1 more minute" button on snooze-category
    /// notifications. Matched in `userNotificationCenter(_:didReceive:)`.
    static let snoozeActionIdentifier = "SNOOZE_ONE_MIN"

    /// Category for the presence-driven "you're here but not working" nudge.
    /// Separate from the curfew warnings so the user can mute one in System
    /// Settings → Notifications without losing the other — a nudge is advice,
    /// a T-5 warning is notice that the Mac is about to lock.
    static let distractionCategoryIdentifier = "CURFEW_DISTRACTION"

    private let center: UNUserNotificationCenter
    private var lastDeliveredStage: WarningStage = .none
    private var deliveredDayToken: String = ""

    /// Called on `@MainActor` when the user taps the snooze action. The model
    /// wires this to `requestNotificationSnooze()`.
    var onSnoozeRequested: (() -> Void)?

    /// The voice the banners speak in. The model sets it from the theme.
    var voice = VoicePack.standard

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

    func update(
        stage: WarningStage,
        now: Date,
        alreadyFiredElsewhere: Set<String>
    ) {
        update(
            stage: stage,
            now: now,
            calendar: .current,
            alreadyFiredElsewhere: alreadyFiredElsewhere
        )
    }

    /// Delivers the presence-driven distraction nudge.
    ///
    /// Cadence and eligibility are `DistractionWarningPolicy`'s job, not this
    /// manager's — by the time this is called the decision has been made. The
    /// per-stage dedup above deliberately does not apply: a distraction can
    /// recur many times in a day, and the repeat window is what bounds it.
    ///
    /// The copy states the observation before the ask. Curfew knows the user
    /// is at the machine and has not touched it, which is a claim it should
    /// make out loud — a nudge that just said "get back to work" would leave
    /// the user guessing how the app decided that.
    func deliverDistractionNudge() {
        let payload = Self.distractionPayload(voice: voice)
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.categoryIdentifier = payload.categoryIdentifier
        if payload.playsSound {
            content.sound = .default
        }
        center.add(UNNotificationRequest(
            identifier: "curfew.distraction.\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }

    /// Copy for the distraction nudge. `static` so a test can assert the
    /// wording without a live notification centre.
    ///
    /// Silent by design: the user is sitting right there, so a sound would be
    /// a jolt where a banner is a glance. The curfew warnings escalate to
    /// sound because they precede the Mac locking; this one does not.
    static func distractionPayload(voice: VoicePack = .standard) -> WarningNotificationPayload {
        WarningNotificationPayload(
            title: voice.presenceTitle,
            body: voice.presenceBody,
            categoryIdentifier: distractionCategoryIdentifier,
            playsSound: false
        )
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

    /// The notification for an approaching curfew: titled by the time left,
    /// with the stage line as its body; never the app's name as the title.
    /// The lock itself replaces a T-0 banner.
    static func payload(
        for stage: WarningStage, voice: VoicePack = .standard
    ) -> WarningNotificationPayload? {
        let minutes: Int
        let category: String
        switch stage {
        case .thirtyMinutes: (minutes, category) = (30, warningSnoozeCategoryIdentifier)
        case .fifteenMinutes: (minutes, category) = (15, warningSnoozeCategoryIdentifier)
        case .fiveMinutes: (minutes, category) = (5, warningCategoryIdentifier)
        case .twoMinutes: (minutes, category) = (2, warningCategoryIdentifier)
        case .oneMinute: (minutes, category) = (1, warningCategoryIdentifier)
        case .lockout, .none: return nil
        }
        guard let line = voice.stageLine(stage) else { return nil }
        return WarningNotificationPayload(
            title: voice.warningTitle(minutes: minutes),
            body: line,
            categoryIdentifier: category,
            // The last five minutes sound; the early warnings are a glance.
            playsSound: minutes <= 5
        )
    }

    /// The quick action on the early warnings: one more minute before curfew.
    static let snoozeActionTitle = VoicePack.standard.moreTime(minutes: 1)

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
            ),
            WarningNotificationCategoryDefinition(
                identifier: distractionCategoryIdentifier,
                actionIdentifiers: []
            )
        ]
    }

    private func notificationContent(for stage: WarningStage) -> UNMutableNotificationContent? {
        guard let payload = Self.payload(for: stage, voice: voice) else {
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
                            title: Self.snoozeActionTitle,
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

extension WarningNotificationManager: WarningNotificationManaging {}

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
