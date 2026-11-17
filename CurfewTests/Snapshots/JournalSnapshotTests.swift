#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewKit
    import SwiftUI
    import XCTest

    /// The Journal in each range and appearance, plus its states, rendered in
    /// a titled window so the toolbar's range control is in the picture.
    /// Written to `build/screenshots/curfew-journal-*.png`.
    extension DestinationSnapshotTests {
        func testRenderJournalRanges() throws {
            let model = Self.demoModel()
            let calendar = Calendar.current
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: model.currentTime)
            let now = model.currentTime
            let latest = model.journalDayRecords(in: now.addingTimeInterval(-14 * 86400) ... now)
                .last { $0.ending != nil }?.day
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                try renderJournal(
                    JournalView(range: .week, anchor: latest), model: model,
                    named: "journal-week-\(suffix)", height: 1900, appearance: appearance
                )
                try renderJournal(
                    JournalView(range: .month, anchor: lastMonth), model: model,
                    named: "journal-month-\(suffix)", height: 2000, appearance: appearance
                )
                try renderJournal(
                    JournalView(range: .year), model: model,
                    named: "journal-year-\(suffix)", height: 2050, appearance: appearance
                )
            }
        }

        func testRenderJournalStates() throws {
            let model = Self.demoModel()
            let now = model.currentTime
            let records = model.journalDayRecords(in: now.addingTimeInterval(-14 * 86400) ... now)
            let latest = try XCTUnwrap(records.last { $0.ending != nil })
            let early = records.last { ($0.stopOffsetMinutes ?? 0) < 0 } ?? latest
            try renderJournal(
                JournalView(range: .week, anchor: latest.day, expanded: [latest.day]),
                model: model, named: "journal-week-expanded-light", height: 2150,
                appearance: .aqua
            )
            try renderJournal(
                JournalView(range: .week, anchor: early.day, initiallyActive: early.day),
                model: model, named: "journal-week-hover-light", height: 900,
                appearance: .aqua
            )

            let empty = try CurfewAppModel(
                settingsStore: CurfewSettingsStore(
                    defaults: XCTUnwrap(UserDefaults(suiteName: "JournalSnapshot-\(UUID())"))
                ),
                appRouter: AppRouterSpy(),
                activityRecorder: NullActivityRecording(),
                lockoutDeadlineStore: .ephemeralForTesting()
            )
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                try renderJournal(
                    JournalView(), model: empty, named: "journal-empty-\(suffix)", height: 640,
                    appearance: appearance
                )
            }
            try renderJournalPage(
                Self.edgeCaseScreen(kind: .longSingleDay, model: model),
                named: "journal-single-day-light", height: 1900
            )
            try renderJournalPage(
                Self.edgeCaseScreen(kind: .beforeStopTimes, model: model),
                named: "journal-before-stop-times-light", height: 1500
            )
        }

        private enum EdgeCase {
            case longSingleDay
            case beforeStopTimes
        }

        /// A single day with very long words, or a week recorded before stop
        /// times existed.
        private static func edgeCaseScreen(kind: EdgeCase, model: CurfewAppModel)
            -> JournalScreen {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: model.currentTime)
            let period = JournalPeriod.containing(today, range: .week, calendar: calendar)
            var records: [JournalDayRecord] = []
            switch kind {
            case .longSingleDay:
                let monday = calendar.firstWeekday == 1 ? 1 : 0
                let day = calendar.date(byAdding: .day, value: monday, to: period.interval.start)
                    ?? period.interval.start
                let curfew = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
                records = [JournalDayRecord(
                    day: day,
                    ending: DayEnding(cause: .lock, stoppedAt: curfew, scheduledCurfew: curfew),
                    overrideMinutes: 45,
                    overrideReasons: [
                        "The quarterly reconciliation export from the finance system failed "
                            + "halfway through and the auditors need the corrected ledger, with "
                            + "every adjustment annotated, in their inbox before they start at "
                            + "eight tomorrow morning."
                    ],
                    oneThing: "Finish the internationalisation review for the onboarding, "
                        + "billing and account recovery flows, including every right-to-left "
                        + "layout and the pluralisation rules for Polish and Arabic",
                    oneThingDone: false,
                    readiness: JournalRating(value: 3, scale: 5)
                )]
            case .beforeStopTimes:
                records = (0 ..< 5).compactMap { offset in
                    guard let day = calendar.date(
                        byAdding: .day,
                        value: offset - 7 + (calendar.firstWeekday == 1 ? 1 : 0),
                        to: period.interval.start
                    ) else { return nil }
                    return JournalDayRecord(
                        day: day,
                        oneThing: JournalSampleDataNames.things[offset],
                        readiness: JournalRating(value: 3 + offset % 3, scale: 5)
                    )
                }
            }
            let target = kind == .beforeStopTimes
                ? period.previous(calendar: calendar) : period
            return JournalScreen(
                records: records,
                period: target,
                today: kind == .beforeStopTimes ? today : model.currentTime,
                workingWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                format: JournalFormat(calendar: calendar)
            )
        }

        /// Renders the Journal inside a titled window with its toolbar.
        private func renderJournal(
            _ view: JournalView,
            model: CurfewAppModel,
            named name: String,
            height: CGFloat,
            appearance: NSAppearance.Name
        ) throws {
            let root = NavigationStack {
                view.environment(model)
            }
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            .tint(CurfewTheme.accent)
            try capture(
                root,
                named: name,
                width: 880,
                height: height,
                appearance: appearance
            )
        }

        private func renderJournalPage(
            _ screen: JournalScreen,
            named name: String,
            height: CGFloat
        ) throws {
            let page = ScrollView {
                JournalPage(
                    screen: screen,
                    format: JournalFormat(),
                    expanded: .constant(Set(screen.rows.map(\.day))),
                    showsAll: .constant(false)
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .background(JournalStyle.page)
            .environment(\.colorScheme, .light)
            try capture(
                page,
                named: name,
                width: 880,
                height: height,
                appearance: .aqua
            )
        }

        private func capture(
            _ view: some View,
            named name: String,
            width: CGFloat,
            height: CGFloat,
            appearance: NSAppearance.Name
        ) throws {
            let directory = try Self.screenshotsDirectory()
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: appearance)
            window.title = "Journal"
            let host = NSHostingView(rootView: view)
            host.sceneBridgingOptions = [.toolbars, .title]
            window.contentView = host
            window.setContentSize(frame.size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let target = host.superview ?? host
            target.layoutSubtreeIfNeeded()
            target.displayIfNeeded()
            let bitmap = try XCTUnwrap(target.bitmapImageRepForCachingDisplay(in: target.bounds))
            target.cacheDisplay(in: target.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("curfew-\(name).png"))
        }

        /// `<repo>/build/screenshots`, where `just snapshot` collects images.
        static func screenshotsDirectory() throws -> URL {
            let directory = try snapshotsDirectory()
                .deletingLastPathComponent()
                .appendingPathComponent("screenshots", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        }
    }

    /// Names for the edge-case renders, kept apart from the sample generator.
    private enum JournalSampleDataNames {
        static let things = [
            "Ship the billing migration", "Finish the onboarding spec", "Review the Q4 roadmap",
            "Fix the flaky sync test", "Write the launch post"
        ]
    }
#endif
