#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewAtmosphere
    import CurfewKit
    import SwiftUI
    import XCTest

    /// Today and the menu bar popover for review against the prototype's
    /// `#hero` frame: the afternoon, the last half hour, noon (the brightest
    /// sky behind the text), off, no one thing yet, a long one thing, the main
    /// window with the sky behind the sidebar, and the popover in both
    /// appearances. Output: `build/screenshots/curfew-today-*.png`.
    /// Hosted captures go blank once system glass is in the hierarchy, so
    /// Today and the popover render through `ImageRenderer`, which draws the
    /// scene and an approximation of the glass. The window capture, which needs
    /// AppKit for the sidebar, shows the off state, where no hold control is
    /// present.
    /// One Today capture: its name, sky, content and one thing.
    private struct TodayCapture {
        var name: String
        var frame: HorizonFrame
        var presentation: TodayPresentation
        var oneThing: TodayOneThing?

        init(
            name: String, frame: HorizonFrame, _ presentation: TodayPresentation,
            _ oneThing: TodayOneThing?
        ) {
            self.name = name
            self.frame = frame
            self.presentation = presentation
            self.oneThing = oneThing
        }
    }

    extension DestinationSnapshotTests {
        private static let curfewCalendar = Calendar.current

        private static func at(_ hour: Int, _ minute: Int, nextDay: Bool = false) -> Date {
            let base = curfewCalendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!
            let day = nextDay ? curfewCalendar.date(byAdding: .day, value: 1, to: base)! : base
            return curfewCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        private static func frame(_ hour: Int, _ minute: Int) -> HorizonFrame {
            HorizonMoment(
                now: at(hour, minute), dayStart: at(7, 0), curfew: at(18, 0),
                nextUnlock: at(7, 0, nextDay: true)
            ).frame
        }

        private static func counting(
            minutes: Int, stage: WarningStage = .none, canExtend: Bool = false
        ) -> TodayPresentation {
            TodayPresentation.resolve(TodaySituation(
                setupComplete: true, enforcing: true,
                phase: stage == .none ? .working : .warning, warningStage: stage,
                minutesRemaining: minutes, upcomingCurfew: at(18, 0),
                unlockDate: at(7, 0, nextDay: true), overrideEnds: nil,
                canRequestExtension: canExtend, extensionsRemaining: 2, canCallItADay: true
            ))
        }

        private static let shipIt = TodayOneThing(text: "Ship the billing migration", isDone: false)

        func testRenderTodayStates() throws {
            let directory = try Self.snapshotsDirectory()
            let size = CGSize(width: 832, height: 720)
            let states: [TodayCapture] = [
                TodayCapture(
                    name: "afternoon", frame: Self.frame(15, 30), Self.counting(minutes: 150),
                    Self.shipIt
                ),
                TodayCapture(
                    name: "last-half-hour", frame: Self.frame(17, 48),
                    Self.counting(minutes: 12, stage: .fifteenMinutes, canExtend: true), Self.shipIt
                ),
                TodayCapture(
                    name: "noon", frame: Self.frame(12, 30), Self.counting(minutes: 330),
                    Self.shipIt
                ),
                TodayCapture(
                    name: "long-one-thing", frame: Self.frame(15, 30), Self.counting(minutes: 150),
                    TodayOneThing(
                        text: "Finish the billing migration, write up the retry test results "
                            + "and hand the rollout plan to support",
                        isDone: false
                    )
                ),
                TodayCapture(
                    name: "done", frame: Self.frame(16, 10), Self.counting(minutes: 110),
                    TodayOneThing(text: "Ship the billing migration", isDone: true)
                ),
                TodayCapture(
                    name: "off", frame: Self.frame(15, 30),
                    TodayPresentation.resolve(TodaySituation(
                        setupComplete: true, enforcing: false, phase: .working,
                        warningStage: .none, minutesRemaining: 150, upcomingCurfew: Self.at(18, 0),
                        unlockDate: nil, overrideEnds: nil, canRequestExtension: false,
                        extensionsRemaining: 2, canCallItADay: false
                    )),
                    Self.shipIt
                )
            ]
            for state in states {
                try render(
                    TodaySundownView(
                        horizon: state.frame, presentation: state.presentation,
                        oneThing: state.oneThing
                    )
                    .transaction { $0.disablesAnimations = true },
                    named: "today-\(state.name)", width: size.width, height: size.height,
                    to: directory
                )
            }
        }

        /// The two hardest skies behind the text: mid-morning, when the sun
        /// passes closest to the countdown, and the last minutes, when the
        /// glow sits on the horizon behind the actions.
        func testRenderTodayNearTheSun() throws {
            let directory = try Self.snapshotsDirectory()
            let states = [
                TodayCapture(
                    name: "morning", frame: Self.frame(9, 30), Self.counting(minutes: 510),
                    Self.shipIt
                ),
                TodayCapture(
                    name: "dusk", frame: Self.frame(17, 58),
                    Self.counting(minutes: 2, stage: .oneMinute, canExtend: true), Self.shipIt
                )
            ]
            for state in states {
                try render(
                    TodaySundownView(
                        horizon: state.frame, presentation: state.presentation,
                        oneThing: state.oneThing
                    )
                    .transaction { $0.disablesAnimations = true },
                    named: "today-\(state.name)", width: 832, height: 720, to: directory
                )
            }
        }

        /// The "What is today for?" field is an AppKit control, which only a
        /// hosted capture draws; a day off has no hold control to blank it.
        func testRenderTodayAskingForTheOneThing() throws {
            let directory = try Self.snapshotsDirectory()
            let dayOff = TodayPresentation.resolve(TodaySituation(
                setupComplete: true, enforcing: true, phase: .dayOff, warningStage: .none,
                minutesRemaining: .max, upcomingCurfew: nil, unlockDate: nil, overrideEnds: nil,
                canRequestExtension: false, extensionsRemaining: 2, canCallItADay: false
            ))
            try renderHosted(
                TodaySundownView(horizon: Self.frame(10, 30), presentation: dayOff, oneThing: nil)
                    .transaction { $0.disablesAnimations = true },
                named: "today-no-one-thing", width: 832, height: 720, settlingTime: 0.3,
                to: directory
            )
        }

        /// The popover's small sky through the day: the sun passes closest to
        /// its text mid-morning and mid-afternoon.
        func testRenderTodayPopoverThroughTheDay() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            model.started = true
            model.reflectionState.recorder = InMemoryReflectionRecording()
            model.saveTodaysOneThing("Ship the billing migration")
            for (hour, minute) in [(8, 45), (10, 15), (12, 30), (15, 45)] {
                model.currentTime = Self.at(hour, minute)
                let remaining = (18 - hour) * 60 - minute
                model.state = CurfewEvaluation(
                    phase: .working, warningStage: .none, minutesRemaining: remaining,
                    canRequestExtension: false, lockDate: Self.at(18, 0),
                    unlockDate: Self.at(7, 0, nextDay: true)
                )
                try render(
                    ContentView().environment(model)
                        .transaction { $0.disablesAnimations = true },
                    named: String(format: "today-popover-%02d%02d", hour, minute), width: 340,
                    to: directory
                )
            }
        }

        func testRenderTodayWindowAndPopover() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            model.currentTime = Self.at(15, 30)
            model.state = CurfewEvaluation(
                phase: .working, warningStage: .none, minutesRemaining: 150,
                canRequestExtension: false, lockDate: Self.at(18, 0),
                unlockDate: Self.at(7, 0, nextDay: true)
            )
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                try renderHosted(
                    MainWindowView().environment(model)
                        .transaction { $0.disablesAnimations = true },
                    named: "today-window-off-\(suffix)", width: 1080, height: 720,
                    settlingTime: 0.4, appearance: appearance, to: directory
                )
            }
            model.started = true
            model.reflectionState.recorder = InMemoryReflectionRecording()
            model.saveTodaysOneThing("Ship the billing migration")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                try render(
                    ContentView().environment(model)
                        .transaction { $0.disablesAnimations = true },
                    named: "today-popover-\(suffix)", width: 340,
                    appearance: appearance, to: directory
                )
            }

            model.currentTime = Self.at(17, 48)
            model.state = CurfewEvaluation(
                phase: .warning, warningStage: .fifteenMinutes, minutesRemaining: 12,
                canRequestExtension: true, lockDate: Self.at(18, 0),
                unlockDate: Self.at(7, 0, nextDay: true)
            )
            try render(
                ContentView().environment(model)
                    .transaction { $0.disablesAnimations = true },
                named: "today-popover-last-half-hour", width: 340, to: directory
            )
        }
    }
#endif
