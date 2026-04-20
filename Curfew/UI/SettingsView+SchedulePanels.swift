import SwiftUI

/// Schedule-related panels for the Settings window: preset picker, weekly
/// day-by-day editor, and the "change queued" notice for pending edits
/// still within their anti-bypass cooldown.
extension SettingsView {
    /// One-click preset selector (9-to-5 / Startup Hours / Half Day). Acts
    /// as the "start from a baseline" shortcut so users aren't forced to
    /// build a seven-day schedule from scratch.
    var presetsPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Presets",
                subtitle: "Start from a baseline and tweak day-by-day."
            )

            HStack(spacing: 10) {
                ForEach(SchedulePreset.allCases) { preset in
                    Button(preset.rawValue) {
                        model.applyPreset(preset)
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }
        }
    }

    /// Seven-row editor, one row per `Weekday`. Each row uses `DayRuleRow`
    /// to expose lock/unlock time pickers and a "day off" toggle. Summary
    /// sentence at the bottom pulls from the model so it reflects either
    /// the live schedule or a pending-but-not-effective change.
    var weeklySchedulePanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Weekly Schedule",
                subtitle: ScheduleSurfaceCopy.weeklyScheduleSubtitle
            )

            Text(ScheduleSurfaceCopy.weeklyScheduleExplanation)
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Weekday.allCases) { weekday in
                    DayRuleRow(weekday: weekday)
                    if weekday != Weekday.allCases.last {
                        Divider()
                    }
                }
            }

            Text(model.scheduleSummarySentence)
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    /// Warning banner shown when the user has queued a schedule change that
    /// will take effect later (weaker edits are held for 24h to prevent
    /// impulsive bypass; stricter edits may take effect next day).
    ///
    /// - Parameter message: copy describing the pending change, produced
    ///   by ``CurfewAppModel/pendingScheduleDescription``.
    func pendingChangePanel(message: String) -> some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Pending Change")
            Text(message)
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.warning)
        }
    }
}
