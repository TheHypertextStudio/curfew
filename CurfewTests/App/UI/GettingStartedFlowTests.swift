@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct GettingStartedFlowTests {
    @Test("Setup opens on a welcome, then asks one thing per screen")
    func stepsInOrder() {
        #expect(FirstRunStep.order == [
            .welcome, .schedule, .permissions, .optional, .ready, .extras
        ])
        // Saved progress keys off these raw values; the first four never move.
        #expect(FirstRunStep.schedule.rawValue == 0)
        #expect(FirstRunStep.permissions.rawValue == 1)
        #expect(FirstRunStep.ready.rawValue == 2)
        #expect(FirstRunStep.extras.rawValue == 3)
    }

    @Test("Step headings use the launch copy")
    func headings() {
        #expect(FirstRunStep.welcome.title == "Curfew ends your work day.")
        #expect(FirstRunStep.schedule.title == "When should your day end?")
        #expect(FirstRunStep.permissions.title == "Let Curfew hold the lock.")
        #expect(FirstRunStep.optional.title == "Two more. Both optional.")
        #expect(FirstRunStep.ready.title == "You're set.")
        #expect(FirstRunStep.extras.title == "Curfew on your other devices")
    }

    @Test("A fresh setup starts on the welcome and its button opens the question")
    func welcomeBegins() {
        var flow = FirstRunFlow()
        #expect(flow.currentStep == .welcome)
        #expect(flow.canAdvance)

        flow.begin()

        #expect(flow.currentStep == .schedule)
        #expect(flow.scheduleChoice == nil)
        #expect(!flow.canAdvance)
    }

    @Test("Choosing a schedule is the explicit choice and moves on in one press")
    func choosingScheduleAdvances() {
        var flow = FirstRunFlow()
        flow.begin()

        flow.chooseSchedule(.weeklySchedule)

        #expect(flow.scheduleChoice == .weeklySchedule)
        #expect(flow.currentStep == .permissions)
    }

    @Test("No schedule yet is an explicit choice too")
    func noScheduleYetIsExplicit() {
        var flow = FirstRunFlow()
        flow.begin()
        flow.chooseSchedule(.remoteControlsOnly)
        #expect(flow.scheduleChoice == .remoteControlsOnly)
        #expect(flow.currentStep == .permissions)
    }

    @Test("The permission screen cannot continue without real Accessibility access")
    func permissionsGate() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)
        #expect(!flow.canAdvance)

        flow.advance()
        #expect(flow.currentStep == .permissions)

        _ = flow.updateAccessibilityGranted(true)
        #expect(flow.canAdvance)
        _ = flow.updateAccessibilityGranted(false)
        #expect(!flow.canAdvance)
    }

    @Test("A fresh grant moves setup on by itself, once")
    func grantWhileWaitingContinues() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)

        let firstGrant = flow.updateAccessibilityGranted(true)
        #expect(firstGrant)
        let repeatGrant = flow.updateAccessibilityGranted(true)
        #expect(!repeatGrant)
    }

    @Test("Access that was already granted does not skip the permission screen by itself")
    func existingGrantDoesNotAutoContinue() {
        var flow = FirstRunFlow()
        let existingGrant = flow.updateAccessibilityGranted(true)
        #expect(!existingGrant)
        flow.chooseSchedule(.weeklySchedule)
        #expect(flow.currentStep == .permissions)
        #expect(flow.canAdvance)
    }

    @Test("Committing setup offers the optional asks, then says it is set")
    func commitMovesToOptional() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)
        #expect(flow.canGoBack)
        _ = flow.updateAccessibilityGranted(true)

        flow.markCommitted(offersOptional: true)

        #expect(flow.isCommitted)
        #expect(flow.currentStep == .optional)
        #expect(!flow.canGoBack)
        flow.retreat()
        #expect(flow.currentStep == .optional)
        flow.advance()
        #expect(flow.currentStep == .ready)
        flow.advance()
        #expect(flow.currentStep == .extras)
        #expect(flow.isLastStep)
    }

    @Test("With nothing optional left to ask, committing goes straight to the summary")
    func commitSkipsOptionalWhenNothingIsOffered() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)
        _ = flow.updateAccessibilityGranted(true)

        flow.markCommitted(offersOptional: false)

        #expect(flow.currentStep == .ready)
    }

    @Test("Back from the permission screen returns to the question and keeps the choice open")
    func backFromPermissions() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)
        flow.retreat()
        #expect(flow.currentStep == .schedule)
    }

    @Test("Progress round-trips so setup reopens at the step reached")
    func progressRoundTrip() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.remoteControlsOnly)

        let resumed = FirstRunFlow.resuming(flow.progress)

        #expect(resumed.currentStep == .permissions)
        #expect(resumed.scheduleChoice == .remoteControlsOnly)
        #expect(!resumed.isCommitted)
    }

    @Test("Someone who left on the question comes back to it, not to the welcome")
    func resumingOnTheQuestion() {
        var flow = FirstRunFlow()
        flow.begin()
        #expect(FirstRunFlow.resuming(flow.progress).currentStep == .schedule)
        #expect(FirstRunFlow.resuming(FirstRunFlow().progress).currentStep == .welcome)
    }

    @Test("Resuming never lands past the permission screen without a committed setup")
    func resumingCannotSkipCommit() {
        for step in [FirstRunStep.optional, .ready, .extras] {
            let resumed = FirstRunFlow.resuming(
                InitialSetupProgress(step: step.rawValue, usesWeeklySchedule: true)
            )
            #expect(resumed.currentStep == .permissions)
        }
        let unchosen = FirstRunFlow.resuming(InitialSetupProgress(step: 1, usesWeeklySchedule: nil))
        #expect(unchosen.currentStep == .schedule)
    }

    @Test("Reopening a finished setup shows the summary, or the permission when access was lost")
    func returningUser() {
        let healthy = FirstRunFlow.returningUser(isAccessibilityGranted: true)
        #expect(healthy.currentStep == .ready)
        #expect(healthy.isCommitted)
        #expect(healthy.isReview)

        var lost = FirstRunFlow.returningUser(isAccessibilityGranted: false)
        #expect(lost.currentStep == .permissions)
        let regranted = lost.updateAccessibilityGranted(true)
        #expect(regranted)
        lost.markCommitted(offersOptional: true)
        #expect(lost.currentStep == .ready)
    }
}

struct SetupOptionalAskTests {
    @Test("The optional screen offers notifications, then the Curfew helper")
    func order() {
        #expect(SetupOptionalAsk.offered(
            notifications: .notAsked, helper: .notInstalled, showsHelper: true
        ) == [.notifications, .helper])
        #expect(GettingStartedCopy.optionalTitle(count: 2) == "Two more. Both optional.")
    }

    @Test("Anything already answered is not asked again")
    func answeredAsksAreLeftOut() {
        #expect(SetupOptionalAsk.offered(
            notifications: .allowed, helper: .notInstalled, showsHelper: true
        ) == [.helper])
        #expect(SetupOptionalAsk.offered(
            notifications: .off, helper: .installed, showsHelper: true
        ).isEmpty)
        #expect(SetupOptionalAsk.offered(
            notifications: .notAsked, helper: .notInstalled, showsHelper: false
        ) == [.notifications])
        #expect(GettingStartedCopy.optionalTitle(count: 1) == "One more. It's optional.")
    }

    @Test("A helper that failed or waits for approval is still offered")
    func unfinishedHelperIsOffered() {
        for status in [SetupHelperStatus.failed, .needsApproval, .installing] {
            #expect(SetupOptionalAsk.offered(
                notifications: .allowed, helper: status, showsHelper: true
            ) == [.helper])
        }
    }
}

struct SetupScheduleStepTests {
    private let draft = SetupScheduleDraft(
        lockMinutes: 18 * 60, unlockMinutes: 7 * 60, workingDays: [.monday]
    )

    @Test("The round buttons move a time by a quarter hour")
    func steps() {
        #expect(draft.adjusting(.curfew, by: 15).lockMinutes == 18 * 60 + 15)
        #expect(draft.adjusting(.unlock, by: -15).unlockMinutes == 6 * 60 + 45)
    }

    @Test("A time wraps past midnight")
    func wraps() {
        let late = SetupScheduleDraft(
            lockMinutes: 23 * 60 + 50, unlockMinutes: 7 * 60, workingDays: [.monday]
        )
        #expect(late.adjusting(.curfew, by: 15).lockMinutes == 5)
    }

    @Test("The day stays between one hour and twenty")
    func dayLengthIsBounded() {
        let short = SetupScheduleDraft(
            lockMinutes: 8 * 60, unlockMinutes: 7 * 60, workingDays: [.monday]
        )
        #expect(short.adjusting(.curfew, by: -15) == short)
        #expect(short.adjusting(.unlock, by: 15) == short)
        let long = SetupScheduleDraft(
            lockMinutes: 3 * 60, unlockMinutes: 7 * 60, workingDays: [.monday]
        )
        #expect(long.adjusting(.curfew, by: 15) == long)
    }
}

struct GettingStartedCopyTests {
    @Test("The welcome says what Curfew is in one sentence and three captions")
    func welcome() {
        #expect(GettingStartedCopy.welcomeLine
            == "At the time you pick, this Mac locks until morning.")
        #expect(GettingStartedCopy.introCaptions == [
            "You work.", "At curfew, this Mac locks.", "In the morning it opens again."
        ])
        #expect(GettingStartedCopy.begin == "Set my curfew")
    }

    @Test("The permission screen asks for Accessibility alone, with one line saying why")
    func permissionLine() {
        #expect(GettingStartedCopy.accessibilityLine
            == "It needs Accessibility, so shortcuts can't get past it.")
    }

    @Test("The days and unlock time are stated as defaults under the question")
    func defaultsLine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let seven = try #require(calendar.date(from: DateComponents(hour: 7)))
            .formatted(date: .omitted, time: .shortened)
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        #expect(GettingStartedCopy.defaultsLine(
            days: weekdays, unlockMinutes: 7 * 60, calendar: calendar
        ) == "Weekdays. Opens at \(seven).")
        #expect(GettingStartedCopy.dayPhrase(Set(Weekday.allCases), calendar: calendar)
            == "Every day")
        #expect(GettingStartedCopy.dayPhrase(
            [.monday, .tuesday, .wednesday, .thursday], calendar: calendar
        ) == "Monday to Thursday")
        #expect(GettingStartedCopy.dayPhrase(
            [.monday, .wednesday, .friday], calendar: calendar
        ) == "Monday, Wednesday and Friday")
        #expect(GettingStartedCopy.dayPhrase([.sunday], calendar: calendar) == "Sunday")
    }

    @Test("The closing step is one Curfew Plus offer with sign-in for existing owners")
    func closingOffer() {
        #expect(GettingStartedCopy.getPlus == "Get Curfew Plus")
        #expect(GettingStartedCopy.signIn == "Sign in")
        #expect(GettingStartedCopy.plusOffer.contains("single payment"))
        #expect(GettingStartedCopy.plusOffer.contains("lock this Mac"))
        #expect(GettingStartedCopy.plusOffer.contains("Apple, Google or a passkey"))
    }

    @Test("Step 3 states tonight's actual curfew time")
    func readyLineTonight() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 16, hour: 10
        )))
        let curfew = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 16, hour: 18
        )))
        let time = curfew.formatted(date: .omitted, time: .shortened)
        #expect(GettingStartedCopy.readyLine(curfew: curfew, now: now, calendar: calendar)
            == "Curfew locks tonight at \(time).")
    }

    @Test("Step 3 names the day when curfew is not tonight")
    func readyLineOtherDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 16, hour: 20
        )))
        let tomorrow = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 17, hour: 18
        )))
        let later = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 19, hour: 18
        )))
        let time = tomorrow.formatted(date: .omitted, time: .shortened)
        let weekday = later.formatted(.dateTime.weekday(.wide))
        #expect(GettingStartedCopy.readyLine(curfew: tomorrow, now: now, calendar: calendar)
            == "Curfew locks tomorrow at \(time).")
        #expect(GettingStartedCopy.readyLine(curfew: later, now: now, calendar: calendar)
            == "Curfew locks \(weekday) at \(time).")
        #expect(GettingStartedCopy.readyLine(curfew: nil, now: now, calendar: calendar)
            == "Nothing locks on a schedule. Set a curfew any time in Schedule.")
    }

    @Test("Setup copy follows the launch words")
    func wordsTable() {
        let lines = GettingStartedCopy.introCaptions + [
            GettingStartedCopy.welcomeTitle,
            GettingStartedCopy.welcomeLine,
            GettingStartedCopy.scheduleTitle,
            GettingStartedCopy.morningTitle,
            GettingStartedCopy.accessibilityLine,
            GettingStartedCopy.notificationsAsk,
            GettingStartedCopy.helperAsk,
            GettingStartedCopy.noScheduleYet,
            GettingStartedCopy.accessibilityReason,
            GettingStartedCopy.notificationsReason,
            GettingStartedCopy.helperReason,
            GettingStartedCopy.helperAbsentNote,
            GettingStartedCopy.dragInstruction,
            GettingStartedCopy.immediateLockTitle,
            GettingStartedCopy.immediateLockMessage
        ]
        for line in lines {
            let lowered = line.lowercased()
            for banned in [
                "lockout",
                "daemon",
                "background protection",
                "computer",
                "device",
                "!"
            ] {
                #expect(!lowered.contains(banned), "\(line) uses \(banned)")
            }
            #expect(!line.contains(" — "), "\(line) uses a dash as punctuation")
        }
        #expect(GettingStartedCopy.helperReason.contains("Curfew helper") ||
            GettingStartedCopy.helperTitle == "Curfew helper")
        #expect(GettingStartedCopy.helperAbsentNote.contains("the Curfew helper"))
        #expect(GettingStartedCopy.immediateLockTitle == "This Mac locks right away")
    }
}
