import CurfewKit
#if DEBUG
    import AppKit
    @testable import Curfew
    import SwiftUI
    import XCTest

    /// Settings, Schedule, the questions editor and the widget in both
    /// appearances, for reviewing the copy and Settings sweep by eye.
    extension DestinationSnapshotTests {
        func testRenderSettingsPanesInBothAppearances() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            for section in SettingsSection.allCases {
                for (appearance, suffix) in [
                    (NSAppearance.Name.aqua, "light"),
                    (.darkAqua, "dark")
                ] {
                    try renderHosted(
                        SettingsView(initialSection: section).environment(model),
                        named: "sweep-settings-\(section.id)-\(suffix)",
                        width: 900, height: 680, appearance: appearance, to: directory
                    )
                }
            }
        }

        func testRenderScheduleAndQuestionsEditor() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                try renderHosted(
                    ScheduleView().environment(model),
                    named: "sweep-schedule-\(suffix)",
                    width: 960, height: 1180, appearance: appearance, to: directory
                )
                try renderHosted(
                    ReflectionPromptsView().environment(model)
                        .background(CurfewTheme.canvas),
                    named: "sweep-questions-\(suffix)",
                    width: 960, height: 1500, appearance: appearance, to: directory
                )
            }
        }

        func testRenderWidgetSizes() throws {
            let directory = try Self.snapshotsDirectory()
            let now = Date()
            let states: [(String, CurfewWidgetPresentation)] = [
                ("working", .init(
                    phase: "working", minutesRemaining: 150,
                    lockDate: now.addingTimeInterval(150 * 60), unlockDate: nil
                )),
                ("warning", .init(
                    phase: "warning", minutesRemaining: 12,
                    lockDate: now.addingTimeInterval(12 * 60), unlockDate: nil
                )),
                ("locked", .init(
                    phase: "locked", minutesRemaining: 0,
                    lockDate: nil, unlockDate: now.addingTimeInterval(9 * 3600)
                )),
                ("day-off", .init(
                    phase: "day_off", minutesRemaining: 0, lockDate: nil, unlockDate: nil
                ))
            ]
            for (name, presentation) in states {
                for (appearance, suffix) in [
                    (NSAppearance.Name.aqua, "light"),
                    (.darkAqua, "dark")
                ] {
                    try renderHosted(
                        widgetTile(CurfewWidgetFace(presentation: presentation, size: .small)),
                        named: "sweep-widget-small-\(name)-\(suffix)",
                        width: 202, height: 202, appearance: appearance, to: directory
                    )
                    try renderHosted(
                        widgetTile(CurfewWidgetFace(presentation: presentation, size: .medium)),
                        named: "sweep-widget-medium-\(name)-\(suffix)",
                        width: 396, height: 202, appearance: appearance, to: directory
                    )
                }
            }
        }

        /// A stand-in for the desktop widget container: system material on a
        /// neutral wallpaper, with the system's inner padding.
        private func widgetTile(_ face: some View) -> some View {
            face
                .padding(16)
                .background(
                    .fill.tertiary,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .background(
                    Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .padding(16)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
#endif
