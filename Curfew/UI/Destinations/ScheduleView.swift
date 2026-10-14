import CurfewKit
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
    @Environment(CurfewAppModel.self) private var model

    /// Scrolling wrapper around ``ScheduleContent``.
    var body: some View {
        ScrollView {
            ScheduleContent()
                .environment(model)
        }
        .scrollIndicators(.hidden)
        // A calm, opaque adaptive canvas. Schedule is a utility surface — the
        // living sky belongs on Today, not stretched behind the editor where it
        // crushes legibility. The canvas extends under the title bar and the
        // scroller so nothing peeks through at the edges.
        .background(CurfewTheme.canvas.ignoresSafeArea())
    }
}

/// The scrollable column of ``ScheduleView`` — presets, the seven-day editor
/// (one ``DayRuleRow`` per weekday), and the pending-change notice for edits
/// still inside their anti-bypass cooldown.
struct ScheduleContent: View {
    /// Shared app model — schedule reads/writes round-trip through it so the
    /// anti-bypass policy engine stays the single mutation entry point.
    @Environment(CurfewAppModel.self) private var model
    @State private var showingEnableConfirmation = false
    @State private var showingImmediateLockConfirmation = false

    /// Padded column of schedule panels.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.settings.hasCompletedInitialSetup, !model.automaticScheduleEnabled {
                automaticScheduleOffPanel
            }
            presetsPanel
            // A queued schedule change (anti-bypass cooldown) is high-priority —
            // surface it directly under the presets, not buried beneath the
            // seven-day editor where the user has to scroll to find it. The
            // applied-confirmation is a model-owned transient (survives
            // navigation, single auto-dismiss), not local view state.
            if let pending = model.pendingScheduleDescription {
                pendingChangePanel(message: pending)
            } else if model.scheduleChangeJustApplied {
                appliedConfirmationPanel
            }
            weeklySchedulePanel
        }
        .padding(24)
        .frame(maxWidth: 900, alignment: .leading)
        .animation(.easeInOut, value: model.scheduleChangeJustApplied)
        .alert("Enable automatic weekly lockouts?", isPresented: $showingEnableConfirmation) {
            Button("Enable schedule") {
                if model.enableAutomaticSchedule() == .requiresImmediateLockConfirmation {
                    showingImmediateLockConfirmation = true
                }
            }
            Button("Keep automatic schedule off", role: .cancel) {}
        } message: {
            Text(model.settings.schedule.reviewLines.joined(separator: "\n") + "\n\n" +
                (model.scheduleWouldLockNow
                    ? "May lock now or within a minute. Existing lockouts remain active."
                    : "These weekly lockouts begin when enabled. Existing lockouts remain active."))
        }
    }

    private var automaticScheduleOffPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Automatic schedule off")
            Text(
                "Saved weekly times are inactive. Authorized remote locks can still apply."
            )
            .font(CurfewTypography.body(14))
            .foregroundStyle(CurfewTheme.mutedInk)
            if !model.hasExplicitAutomaticScheduleConsent {
                Text(
                    "This update left your saved weekly schedule off until you enable it."
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
            }
            if model.state.phase == .locked, let unlock = model.state.unlockDate {
                Text(
                    "An existing lockout remains active until \(unlock.formatted(date: .omitted, time: .shortened))."
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.warning)
            }
            ForEach(model.settings.schedule.reviewLines, id: \.self) { line in
                Text(line)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.ink)
            }
            if model.settings.pendingScheduleChange != nil {
                Text(
                    "A change is pending. Wait for it to apply before enabling weekly lockouts."
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.warning)
            }
            Button("Enable saved weekly schedule…") {
                showingEnableConfirmation = true
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .disabled(model.settings.pendingScheduleChange != nil)
        }
        .alert(
            "This Mac may lock within a minute",
            isPresented: $showingImmediateLockConfirmation
        ) {
            Button("Enable imminent lockout", role: .destructive) {
                model.enableAutomaticSchedule(confirmedImmediateLock: true)
            }
            Button("Keep automatic schedule off", role: .cancel) {}
        } message: {
            Text(
                model.settings.schedule.reviewLines.joined(separator: "\n") +
                    "\n\nMay lock this Mac now. Existing lockouts stay active."
            )
        }
    }

    /// One-click preset selector (9-to-5 / Startup Hours / Half Day). Acts
    /// as the "start from a baseline" shortcut so users aren't forced to
    /// build a seven-day schedule from scratch.
    private var presetsPanel: some View {
        CurfewPanel {
            Text("Presets")
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
    }

    /// Seven-row editor, one row per `Weekday`. Each row uses `DayRuleRow`
    /// to expose lock/unlock time pickers and a "day off" toggle. Summary
    /// sentence at the bottom pulls from the model so it reflects either
    /// the live schedule or a pending-but-not-effective change.
    private var weeklySchedulePanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Weekly schedule",
                subtitle: ScheduleSurfaceCopy.weeklyScheduleSubtitle
            )

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
            CurfewSectionTitle(title: "Scheduled change")
            Text(message)
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.warning)
        }
    }

    /// Brief confirmation shown when a pending change leaves the cooldown and
    /// takes effect, so the user knows their edit is now live.
    private var appliedConfirmationPanel: some View {
        CurfewPanel {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CurfewTheme.accent)
                Text("Schedule change applied.")
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.ink)
            }
        }
        .transition(.opacity)
    }
}
