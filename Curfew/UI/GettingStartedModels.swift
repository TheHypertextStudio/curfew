import CurfewKit
import Foundation

/// Every line first-run setup shows, in one place, so the launch words
/// ("curfew", "this Mac", "the Curfew helper") stay consistent and testable.
enum GettingStartedCopy {
    /// Window title. Sentence case, like every other line in setup.
    static let windowTitle = "Set up Curfew"

    static let wordmark = "Curfew"
    static let welcomeTitle = "Curfew ends your work day."
    static let welcomeLine = "At the time you pick, this Mac locks until morning."
    /// The three captions the welcome plays over one day, in order.
    static let introCaptions = [
        "You work.", "At curfew, this Mac locks.", "In the morning it opens again."
    ]
    static let begin = "Set my curfew"
    static let skipIntro = "Skip intro"
    static let watchAgain = "Watch again"

    static let scheduleTitle = "When should your day end?"
    static let morningTitle = "When does this Mac open again?"
    static let curfewLabel = "Curfew time"
    static let unlockLabel = "Unlock time"
    static let daysLabel = "Days that lock"
    static let change = "Change"
    static let changeHint = "Sets when this Mac opens again and which days lock."
    static let pickADay = "Pick at least one day."
    static let earlier = "Earlier"
    static let later = "Later"
    static let useSchedule = "Use this schedule"
    /// The small link that keeps the explicit "no automatic schedule" choice.
    static let noScheduleYet = "No schedule yet"
    static let noScheduleYetHint = "Nothing locks on a schedule. You can set a curfew later."

    static let notificationsTitle = "Notifications"
    static let notificationsReason = "So you hear about curfew 30, 15, 5 and 1 minute ahead."
    static let helperTitle = "Curfew helper"
    static let helperReason = "So the lock holds even if Curfew is quit."
    static let accessibilityTitle = "Accessibility"
    static let accessibilityReason = "So the lock holds when shortcuts try to get past it."
    /// The one line under the permission screen's heading.
    static let accessibilityLine = "It needs Accessibility, so shortcuts can't get past it."
    static let waitingForAccess = "Waiting for System Settings"
    static let allowed = "Allowed"
    /// The two optional asks, as the rows that offer them.
    static let notificationsAsk = "Warnings before curfew"
    static let helperAsk = "Keep the lock if Curfew is quit"
    static let openSystemSettings = "Open System Settings"
    static let dragInstruction = "Drag Curfew into the list"

    /// Said once, plainly, when this build has a helper and it is not installed.
    static let helperAbsentNote =
        "Without the Curfew helper, force quitting Curfew ends the lock early."

    static let previewLock = "Preview the lock"
    static let endPreview = "End preview"

    static let extrasTitle = "Curfew on your other devices"
    static let plusOffer =
        "Curfew Plus is a single payment. It syncs your schedule and lets your phone "
            + "lock this Mac. Sign in with Apple, Google or a passkey."
    static let getPlus = "Get Curfew Plus"
    static let signIn = "Sign in"

    static let immediateLockTitle = "This Mac locks right away"
    static let immediateLockMessage =
        "It's already curfew, so finishing setup locks this Mac now."
    static let immediateLockConfirm = "Finish and lock"
    static let immediateLockCancel = "Change the times"

    static func optionalTitle(count: Int) -> String {
        count == 1 ? "One more. It's optional." : "Two more. Both optional."
    }

    /// The days that lock, in words: "Weekdays", "Every day", a run such as
    /// "Monday to Thursday", or the days listed.
    static func dayPhrase(_ days: Set<Weekday>, calendar: Calendar = .current) -> String {
        let week: [Weekday] = [
            .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
        ]
        let positions = week.indices.filter { days.contains(week[$0]) }
        let names = positions.map { calendar.weekdaySymbols[week[$0].rawValue - 1] }
        guard let first = names.first, let last = names.last else { return "No days" }
        if positions.count == week.count {
            return "Every day"
        }
        if positions == Array(0 ... 4) {
            return "Weekdays"
        }
        if names.count == 1 {
            return first
        }
        let isRun = zip(positions, positions.dropFirst()).allSatisfy { $1 == $0 + 1 }
        if isRun, names.count > 2 {
            return "\(first) to \(last)"
        }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// What the question screen assumes unless it is changed: the days that
    /// lock and when this Mac opens again.
    static func defaultsLine(
        days: Set<Weekday>, unlockMinutes: Int, calendar: Calendar = .current
    ) -> String {
        let unlock = calendar.startOfDay(for: Date())
            .addingTimeInterval(TimeInterval(unlockMinutes * 60))
        let time = unlock.formatted(date: .omitted, time: .shortened)
        return "\(dayPhrase(days, calendar: calendar)). Opens at \(time)."
    }

    /// Step 3's statement of when this Mac next locks. Times come from the
    /// locale formatter; never a hard-coded 24-hour string.
    static func readyLine(curfew: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let curfew else {
            return "Nothing locks on a schedule. Set a curfew any time in Schedule."
        }
        let time = curfew.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(curfew, inSameDayAs: now) {
            let hour = calendar.component(.hour, from: curfew)
            return hour >= 17 ? "Curfew locks tonight at \(time)." : "Curfew locks today at \(time)."
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(curfew, inSameDayAs: tomorrow) {
            return "Curfew locks tomorrow at \(time)."
        }
        return "Curfew locks \(curfew.formatted(.dateTime.weekday(.wide))) at \(time)."
    }
}

/// One screen of first-run setup: a welcome, the question, the one required
/// permission, the optional asks, the summary, and one optional closing offer.
///
/// `Int`-backed because persisted progress keys off `rawValue`. The first four
/// raw values are already saved on some Macs, so they never move; new screens
/// take new values and ``order`` says where they sit.
enum FirstRunStep: Int, CaseIterable, Identifiable {
    /// When should your day end?
    case schedule
    /// Accessibility, the one required grant.
    case permissions
    /// Setup is committed; states tonight's curfew and offers a preview.
    case ready
    /// Optional: sync sign-in and the lifetime licence.
    case extras
    /// Says what Curfew is before asking anything.
    case welcome
    /// Notifications and the Curfew helper, both optional.
    case optional

    /// The screens in the order a person meets them.
    static let order: [FirstRunStep] = [
        .welcome, .schedule, .permissions, .optional, .ready, .extras
    ]

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .welcome: GettingStartedCopy.welcomeTitle
        case .schedule: GettingStartedCopy.scheduleTitle
        case .permissions: "Let Curfew hold the lock."
        case .optional: GettingStartedCopy.optionalTitle(count: 2)
        case .ready: "You're set."
        case .extras: GettingStartedCopy.extrasTitle
        }
    }
}

/// One of the asks setup makes after the required grant. Each can be left
/// alone: pressing Continue is the skip.
enum SetupOptionalAsk: Equatable {
    case notifications
    case helper

    /// The asks still worth making, notifications first. One already answered
    /// is not asked again, and builds without the Curfew helper never offer it.
    static func offered(
        notifications: SetupPermissionStatus, helper: SetupHelperStatus, showsHelper: Bool
    ) -> [SetupOptionalAsk] {
        var asks: [SetupOptionalAsk] = []
        if notifications == .notAsked {
            asks.append(.notifications)
        }
        if showsHelper, helper != .installed {
            asks.append(.helper)
        }
        return asks
    }
}

/// An explicit choice about automatic lockouts, distinct from editing the
/// proposed schedule and from authorizing remote fixed-duration controls.
enum AutomaticScheduleChoice: Equatable {
    case weeklySchedule
    case remoteControlsOnly
}

/// Persisted cursor so setup reopens on the step the person reached.
struct InitialSetupProgress: Codable, Equatable {
    var step: Int
    var usesWeeklySchedule: Bool?
}

/// Cursor through first-run setup.
///
/// A plain value type so the whole flow is unit tested without a run loop.
/// The schedule choice is always an explicit press (`chooseSchedule`), and
/// the permission screen is a hard gate on *real* Accessibility trust; setup
/// is committed (enforcement armed) only by the model, after which
/// `markCommitted` moves the cursor on and going back is no longer offered.
struct FirstRunFlow: Equatable {
    private(set) var currentStep: FirstRunStep = .welcome
    /// Opening the editor is not consent. A choice is required before setup
    /// leaves the question or arms enforcement.
    private(set) var scheduleChoice: AutomaticScheduleChoice?
    /// Live Accessibility trust, synced by the view from the model.
    private(set) var isAccessibilityGranted = false
    /// Whether setup has been completed and enforcement armed.
    private(set) var isCommitted = false
    /// Reopened after setup was already completed.
    private(set) var isReview = false

    var canAdvance: Bool {
        switch currentStep {
        case .welcome, .optional, .ready: true
        case .schedule: scheduleChoice != nil
        case .permissions: isAccessibilityGranted
        case .extras: false
        }
    }

    var canGoBack: Bool {
        currentStep == .permissions && !isCommitted && !isReview
    }

    var isLastStep: Bool {
        currentStep == .extras
    }

    var usesWeeklySchedule: Bool {
        scheduleChoice == .weeklySchedule
    }

    var progress: InitialSetupProgress {
        InitialSetupProgress(
            step: currentStep.rawValue,
            usesWeeklySchedule: scheduleChoice.map { $0 == .weeklySchedule }
        )
    }

    /// The welcome's button: on to the question. Nothing is chosen yet.
    mutating func begin() {
        guard currentStep == .welcome else { return }
        currentStep = .schedule
    }

    /// The explicit schedule choice. Both the primary button and the small
    /// "no schedule yet" link call this, and both move on in the same press.
    mutating func chooseSchedule(_ choice: AutomaticScheduleChoice) {
        scheduleChoice = choice
        if currentStep == .schedule || currentStep == .welcome {
            currentStep = .permissions
        }
    }

    /// Syncs live trust. Returns `true` exactly when a fresh grant arrives
    /// while the permission screen is waiting for it, which is the only time
    /// setup moves on by itself. Access that was already there waits for
    /// Continue. Revoked trust re-closes the gate.
    @discardableResult
    mutating func updateAccessibilityGranted(_ granted: Bool) -> Bool {
        let wasGranted = isAccessibilityGranted
        isAccessibilityGranted = granted
        return granted && !wasGranted && currentStep == .permissions
    }

    /// Called once the model has completed setup (or, for a returning
    /// person, once access is back). The optional asks come next when there
    /// is anything left to ask; a review goes straight to the summary.
    mutating func markCommitted(offersOptional: Bool = false) {
        isCommitted = true
        if currentStep == .permissions || currentStep == .schedule || currentStep == .welcome {
            currentStep = offersOptional && !isReview ? .optional : .ready
        }
    }

    /// The optional asks to the summary, and the summary to the closing
    /// offer. The earlier screens move on only through `begin`,
    /// `chooseSchedule` and the model's commit.
    mutating func advance() {
        switch currentStep {
        case .optional: currentStep = .ready
        case .ready where !isReview: currentStep = .extras
        default: break
        }
    }

    mutating func retreat() {
        guard canGoBack else { return }
        currentStep = .schedule
    }

    /// Restores saved progress. Without a committed setup, the furthest a
    /// person can land is the permission screen, and only with a recorded
    /// schedule choice. Someone who never left the welcome sees it again.
    static func resuming(_ progress: InitialSetupProgress) -> FirstRunFlow {
        var flow = FirstRunFlow()
        guard let step = FirstRunStep(rawValue: progress.step), step != .welcome else {
            return flow
        }
        flow.begin()
        guard let weekly = progress.usesWeeklySchedule, step != .schedule else { return flow }
        flow.chooseSchedule(weekly ? .weeklySchedule : .remoteControlsOnly)
        return flow
    }

    /// Setup reopened after it was completed: the summary, or the permission
    /// screen when Accessibility has since been lost.
    static func returningUser(isAccessibilityGranted: Bool) -> FirstRunFlow {
        var flow = FirstRunFlow()
        flow.isReview = true
        flow.scheduleChoice = .weeklySchedule
        if isAccessibilityGranted {
            flow.isAccessibilityGranted = true
            flow.isCommitted = true
            flow.currentStep = .ready
        } else {
            flow.currentStep = .permissions
        }
        return flow
    }
}
