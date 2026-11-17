import CurfewKit
import Foundation

/// Every line first-run setup shows, in one place, so the launch words
/// ("curfew", "this Mac", "the Curfew helper") stay consistent and testable.
enum GettingStartedCopy {
    /// Window title. Sentence case, like every other line in setup.
    static let windowTitle = "Set up Curfew"

    static let curfewLabel = "Curfew"
    static let unlockLabel = "Unlocks"
    static let curfewReason = "This Mac locks for the night."
    static let unlockReason = "This Mac opens again in the morning."
    static let daysLabel = "Days that lock"
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

/// One screen of first-run setup: three steps and one optional closing step.
///
/// `Int`-backed because persisted progress keys off `rawValue`. Keep the case
/// order stable.
enum FirstRunStep: Int, CaseIterable, Identifiable {
    /// When should this Mac close for the night?
    case schedule
    /// Accessibility (required), notifications and the Curfew helper.
    case permissions
    /// Setup is committed; states tonight's curfew and offers a preview.
    case ready
    /// Optional: sync sign-in and the lifetime licence.
    case extras

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .schedule: "When should this Mac close for the night?"
        case .permissions: "Let Curfew hold the lock."
        case .ready: "You're set."
        case .extras: GettingStartedCopy.extrasTitle
        }
    }

    var progressLabel: String {
        switch self {
        case .schedule: "Step 1 of 3"
        case .permissions: "Step 2 of 3"
        case .ready: "Step 3 of 3"
        case .extras: "Optional"
        }
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
/// step 2 is a hard gate on *real* Accessibility trust; setup is committed
/// (enforcement armed) only by the model, after which `markCommitted` moves
/// the cursor to step 3 and going back is no longer offered.
struct FirstRunFlow: Equatable {
    private(set) var currentStep: FirstRunStep = .schedule
    /// Opening the editor is not consent. A choice is required before setup
    /// leaves step 1 or arms enforcement.
    private(set) var scheduleChoice: AutomaticScheduleChoice?
    /// Live Accessibility trust, synced by the view from the model.
    private(set) var isAccessibilityGranted = false
    /// Whether setup has been completed and enforcement armed.
    private(set) var isCommitted = false
    /// Reopened after setup was already completed.
    private(set) var isReview = false
    /// Whether both optional rows on step 2 (notifications and the Curfew
    /// helper) are allowed, installed or explicitly skipped.
    private(set) var optionalsResolved = false

    var canAdvance: Bool {
        switch currentStep {
        case .schedule: scheduleChoice != nil
        case .permissions: isAccessibilityGranted
        case .ready: true
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

    /// The explicit schedule choice. Both the primary button and the small
    /// "no schedule yet" link call this, and both move on in the same press.
    mutating func chooseSchedule(_ choice: AutomaticScheduleChoice) {
        scheduleChoice = choice
        if currentStep == .schedule {
            currentStep = .permissions
        }
    }

    /// Syncs live trust. Returns `true` exactly when a fresh grant arrives
    /// while step 2 is waiting for it and both optional rows are already
    /// resolved, which is the only time setup advances by itself. Otherwise
    /// setup holds on step 2 with Continue enabled, so the optional rows are
    /// still offered. Revoked trust re-closes the gate.
    @discardableResult
    mutating func updateAccessibilityGranted(_ granted: Bool) -> Bool {
        let wasGranted = isAccessibilityGranted
        isAccessibilityGranted = granted
        return granted && !wasGranted && currentStep == .permissions && optionalsResolved
    }

    /// Records whether notifications and the Curfew helper are each allowed,
    /// installed or explicitly skipped.
    mutating func updateOptionalPermissions(resolved: Bool) {
        optionalsResolved = resolved
    }

    /// Called once the model has completed setup (or, for a returning
    /// person, once access is back).
    mutating func markCommitted() {
        isCommitted = true
        if currentStep == .permissions || currentStep == .schedule {
            currentStep = .ready
        }
    }

    /// Step 3 to the optional closing step. Steps 1 and 2 move on only
    /// through `chooseSchedule` and the model's commit.
    mutating func advance() {
        guard currentStep == .ready, !isReview else { return }
        currentStep = .extras
    }

    mutating func retreat() {
        guard canGoBack else { return }
        currentStep = .schedule
    }

    /// Restores saved progress. Without a committed setup, the furthest a
    /// person can land is step 2, and only with a recorded schedule choice.
    static func resuming(_ progress: InitialSetupProgress) -> FirstRunFlow {
        var flow = FirstRunFlow()
        guard let weekly = progress.usesWeeklySchedule,
              progress.step >= FirstRunStep.permissions.rawValue else { return flow }
        flow.chooseSchedule(weekly ? .weeklySchedule : .remoteControlsOnly)
        return flow
    }

    /// Setup reopened after it was completed: the summary, or step 2 when
    /// Accessibility has since been lost.
    static func returningUser(isAccessibilityGranted: Bool) -> FirstRunFlow {
        var flow = FirstRunFlow()
        flow.isReview = true
        flow.optionalsResolved = true
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
