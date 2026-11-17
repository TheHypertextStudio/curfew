@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct GettingStartedFlowTests {
    @Test("Setup is three steps plus one optional closing step")
    func stepsAreThreePlusOptional() {
        #expect(FirstRunStep.allCases == [.schedule, .permissions, .ready, .extras])
        #expect(FirstRunStep.schedule.progressLabel == "Step 1 of 3")
        #expect(FirstRunStep.permissions.progressLabel == "Step 2 of 3")
        #expect(FirstRunStep.ready.progressLabel == "Step 3 of 3")
        #expect(FirstRunStep.extras.progressLabel == "Optional")
    }

    @Test("Step headings use the launch copy")
    func headings() {
        #expect(FirstRunStep.schedule.title == "When should this Mac close for the night?")
        #expect(FirstRunStep.permissions.title == "Let Curfew hold the lock.")
        #expect(FirstRunStep.ready.title == "You're set.")
        #expect(FirstRunStep.extras.title == "Curfew on your other devices")
    }

    @Test("Choosing a schedule is the explicit choice and moves on in one press")
    func choosingScheduleAdvances() {
        var flow = FirstRunFlow()
        #expect(!flow.canAdvance)
        #expect(flow.scheduleChoice == nil)

        flow.chooseSchedule(.weeklySchedule)

        #expect(flow.scheduleChoice == .weeklySchedule)
        #expect(flow.currentStep == .permissions)
    }

    @Test("No schedule yet is an explicit choice too")
    func noScheduleYetIsExplicit() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.remoteControlsOnly)
        #expect(flow.scheduleChoice == .remoteControlsOnly)
        #expect(flow.currentStep == .permissions)
    }

    @Test("Step 2 cannot continue without real Accessibility access")
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

    @Test("A fresh grant advances by itself, once, when both optional rows are resolved")
    func grantWhileWaitingContinues() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)
        flow.updateOptionalPermissions(resolved: true)

        let firstGrant = flow.updateAccessibilityGranted(true)
        #expect(firstGrant)
        let repeatGrant = flow.updateAccessibilityGranted(true)
        #expect(!repeatGrant)
    }

    @Test("A fresh grant holds on step 2 while an optional row is unresolved")
    func grantHoldsForOptionalRows() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)

        let grant = flow.updateAccessibilityGranted(true)

        #expect(!grant)
        #expect(flow.currentStep == .permissions)
        #expect(flow.canAdvance)
    }

    @Test("Access that was already granted does not skip step 2 by itself")
    func existingGrantDoesNotAutoContinue() {
        var flow = FirstRunFlow()
        let existingGrant = flow.updateAccessibilityGranted(true)
        #expect(!existingGrant)
        flow.chooseSchedule(.weeklySchedule)
        #expect(flow.currentStep == .permissions)
        #expect(flow.canAdvance)
    }

    @Test("Committing setup moves to step 3 and back is no longer offered")
    func commitMovesToReady() {
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)
        #expect(flow.canGoBack)
        _ = flow.updateAccessibilityGranted(true)

        flow.markCommitted()

        #expect(flow.isCommitted)
        #expect(flow.currentStep == .ready)
        #expect(!flow.canGoBack)
        flow.retreat()
        #expect(flow.currentStep == .ready)
        flow.advance()
        #expect(flow.currentStep == .extras)
        #expect(flow.isLastStep)
    }

    @Test("Back from step 2 returns to the schedule and keeps the choice open")
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

    @Test("Resuming never lands past step 2 without a committed setup")
    func resumingCannotSkipCommit() {
        let resumed = FirstRunFlow.resuming(InitialSetupProgress(step: 3, usesWeeklySchedule: true))
        #expect(resumed.currentStep == .permissions)

        let unchosen = FirstRunFlow.resuming(InitialSetupProgress(step: 1, usesWeeklySchedule: nil))
        #expect(unchosen.currentStep == .schedule)
    }

    @Test("Reopening a finished setup shows the summary, or step 2 when access was lost")
    func returningUser() {
        let healthy = FirstRunFlow.returningUser(isAccessibilityGranted: true)
        #expect(healthy.currentStep == .ready)
        #expect(healthy.isCommitted)
        #expect(healthy.isReview)

        var lost = FirstRunFlow.returningUser(isAccessibilityGranted: false)
        #expect(lost.currentStep == .permissions)
        let regranted = lost.updateAccessibilityGranted(true)
        #expect(regranted)
        lost.markCommitted()
        #expect(lost.currentStep == .ready)
    }
}

struct GettingStartedCopyTests {
    @Test("Step 2 puts the one required grant first and marks the rest optional")
    func permissionsOrder() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Curfew/UI/GettingStartedSteps.swift"),
            encoding: .utf8
        )
        let step = try #require(source.range(of: "struct GettingStartedPermissionsStep"))
        let body = source[step.upperBound...]
        let access = try #require(body.range(of: "GettingStartedCopy.accessibilityTitle"))
        let alerts = try #require(body.range(of: "GettingStartedCopy.notificationsTitle"))
        let helper = try #require(body.range(of: "GettingStartedCopy.helperTitle"))
        #expect(access.lowerBound < alerts.lowerBound)
        #expect(alerts.lowerBound < helper.lowerBound)
        #expect(body.components(separatedBy: "isOptional: true").count - 1 == 2)
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
        let lines = [
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
