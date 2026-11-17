import CurfewKit
#if DEBUG
    import AppKit
    @testable import Curfew
    import SwiftUI
    import XCTest

    /// Writes the Sunrise gate on the real rest screen, and the Sunrise
    /// settings pane, to `build/screenshots/curfew-sunrise-*.png`, for review
    /// against the prototype. Demo models only: nothing is armed, no wake is
    /// scheduled and no Shortcut runs.
    extension DestinationSnapshotTests {
        private static func sunriseCalendarDate(
            _ dayOffset: Int,
            _ hour: Int,
            _ minute: Int
        ) -> Date {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        /// A demo model four minutes after a 7:00 AM unlock, with the gate open.
        private func sunriseMorningModel(note: String?) -> CurfewAppModel {
            let model = Self.demoModel()
            let unlock = Self.sunriseCalendarDate(0, 7, 0)
            model.currentTime = unlock.addingTimeInterval(4 * 60)
            model.reflectionState.scheduledInterval = DateInterval(
                start: Self.sunriseCalendarDate(-1, 18, 0), end: unlock
            )
            model.state = CurfewEvaluation(
                phase: .working, warningStage: .none, minutesRemaining: 656,
                canRequestExtension: true, lockDate: Self.sunriseCalendarDate(0, 18, 0),
                unlockDate: nil
            )
            let reflections = MemoryReflections()
            if let note {
                reflections.record(Reflection(
                    timestamp: Self.sunriseCalendarDate(-1, 18, 2), gate: .evening,
                    answers: [ReflectionAnswer(
                        promptID: ReflectionDefaults.leftForNextTimePromptID,
                        promptTextSnapshot: "What would you like to continue next time?",
                        value: .text(note)
                    )]
                ))
            }
            model.reflectionState.recorder = reflections
            return model
        }

        private func openGate(_ model: CurfewAppModel) {
            model.prepareSunriseGate(pages: model.currentSunrisePages())
            model.reflectionState.isDaybreakPresented = true
        }

        private func renderRest(
            _ model: CurfewAppModel, named name: String,
            width: CGFloat = 1440, height: CGFloat = 900
        ) throws {
            let display = RestDisplayPresentation()
            display.isVisible = true
            try renderHosted(
                RestScreenView(model: model, display: display)
                    // Headless rasterisers draw no Liquid Glass; the Reduce
                    // Transparency fallback shows the buttons' real fill.
                    .environment(\._accessibilityReduceTransparency, true)
                    .transaction { $0.disablesAnimations = true },
                named: name, width: width, height: height, settlingTime: 0.6,
                appearance: .darkAqua, to: Self.snapshotsDirectory()
            )
        }

        func testRenderSunriseGate() throws {
            let withNote = sunriseMorningModel(
                note: "pick up the billing migration at the retry test."
            )
            openGate(withNote)
            XCTAssertEqual(withNote.restPresentation.layout, .morning)
            try renderRest(withNote, named: "sunrise-gate-note")
            // A 13-inch display and a large external display.
            try renderRest(withNote, named: "sunrise-gate-note-13in", width: 1280, height: 800)
            try renderRest(withNote, named: "sunrise-gate-note-large", width: 2560, height: 1440)

            withNote.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] =
                .text("Ship the billing migration")
            try renderRest(withNote, named: "sunrise-gate-answered")

            let plain = sunriseMorningModel(note: nil)
            openGate(plain)
            try renderRest(plain, named: "sunrise-gate")

            // Readiness is the second page; the one thing has been answered.
            plain.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] = .text("Ship it")
            plain.advanceSunrise()
            plain.reflectionState.morningDraft.values[JournalPromptIDs.readiness] =
                .rating(value: 4, scale: 5)
            try renderRest(plain, named: "sunrise-gate-readiness")

            let custom = sunriseMorningModel(note: nil)
            custom.addSunriseQuestion("Who do I owe a reply?")
            var steps = custom.sunriseSteps
            if let index = steps.firstIndex(where: {
                if case .question = $0.kind {
                    return true
                }
                return false
            }) {
                let question = steps.remove(at: index)
                steps.insert(question, at: 0)
            }
            custom.updateSunriseSteps(steps)
            openGate(custom)
            try renderRest(custom, named: "sunrise-gate-question")
        }

        func testRenderSunriseSettings() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            model.automaticScheduleEnabled = true
            model.settings.autoShutdownEnabled = false
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .darkAqua ? "-dark" : ""
                try renderHosted(
                    SettingsView(initialSection: .sunrise).environment(model),
                    named: "sunrise-settings-wake-off\(suffix)", width: 900, height: 900,
                    appearance: appearance, to: directory
                )
            }

            model.updateSunriseWake(enabled: true)
            model.setSunriseShortcut(SunriseShortcut(identifier: "A", name: "Plan my day"))
            model.sunriseRuntime.plan = SunriseWakePlanner(owner: "snapshot").presentationPlan(
                schedule: model.settings.schedule, appearance: model.restAppearance,
                at: model.currentTime, calendar: .current
            )
            model.sunriseStatus = .scheduled
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .darkAqua ? "-dark" : ""
                try renderHosted(
                    SettingsView(initialSection: .sunrise).environment(model),
                    named: "sunrise-settings-wake-on\(suffix)", width: 900, height: 900,
                    appearance: appearance, to: directory
                )
            }

            model.settings.autoShutdownEnabled = true
            model.sunriseStatus = .helperUnavailable
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .darkAqua ? "-dark" : ""
                try renderHosted(
                    SettingsView(initialSection: .sunrise).environment(model),
                    named: "sunrise-settings-blocked\(suffix)", width: 900, height: 900,
                    appearance: appearance, to: directory
                )
            }
        }
    }
#endif
