import SwiftUI

/// "Schedule" workspace destination — the weekly lock/unlock editor.
///
/// Promoted out of the Settings window into a first-class destination: the
/// schedule is the core creative act of the app (you decide your horizon
/// while you're thinking clearly), and first-run onboarding reuses this same
/// editor inline.
///
/// The scrollable body is split into ``ScheduleContent`` so the snapshot
/// capture tier can render it off-screen (`ImageRenderer` doesn't render
/// `ScrollView` content).
struct ScheduleView: View {
    /// Shared app model, forwarded to the content via the environment.
    @EnvironmentObject private var model: CurfewAppModel

    /// Scrolling wrapper around ``ScheduleContent``.
    var body: some View {
        ScrollView {
            ScheduleContent()
                .environmentObject(model)
        }
        .scrollIndicators(.hidden)
    }
}

/// The scrollable column of ``ScheduleView`` — presets, the seven-day editor
/// (one ``DayRuleRow`` per weekday), and the pending-change notice for edits
/// still inside their anti-bypass cooldown.
struct ScheduleContent: View {
    /// Shared app model — schedule reads/writes round-trip through it so the
    /// anti-bypass policy engine stays the single mutation entry point.
    @EnvironmentObject private var model: CurfewAppModel

    /// Padded column of schedule panels.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            presetsPanel
            weeklySchedulePanel
            if let pending = model.pendingScheduleDescription {
                pendingChangePanel(message: pending)
            }
        }
        .padding(24)
        .frame(maxWidth: 900, alignment: .leading)
    }

    /// One-click preset selector (9-to-5 / Startup Hours / Half Day). Acts
    /// as the "start from a baseline" shortcut so users aren't forced to
    /// build a seven-day schedule from scratch.
    private var presetsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start from a preset")
                .font(CurfewTypography.title(16))
                .foregroundStyle(CurfewTheme.ink)

            HStack(spacing: 10) {
                ForEach(SchedulePreset.allCases) { preset in
                    Button(preset.rawValue) {
                        model.applyPreset(preset)
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Seven-row editor, one row per `Weekday`. Each row uses `DayRuleRow`
    /// to expose lock/unlock time pickers and a "day off" toggle. Summary
    /// sentence at the bottom pulls from the model so it reflects either
    /// the live schedule or a pending-but-not-effective change.
    private var weeklySchedulePanel: some View {
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
    private func pendingChangePanel(message: String) -> some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Pending Change")
            Text(message)
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.warning)
        }
    }
}
