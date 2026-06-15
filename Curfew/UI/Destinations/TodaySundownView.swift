import SwiftUI

/// Presentational Today surface in the sundown language. Driven by plain
/// values + actions so it can be rendered live (via ``TodayView``) or in the
/// snapshot tier with demo defaults.
///
/// Today carries one thing: tonight's curfew window, and the control for it.
/// 1. **The window** — the countdown is the protagonist over the living
///    ``SundownSky``, which deepens as the lock time nears; the lock time is its
///    primary detail, the unlock time the quieter other end of the same event.
/// 2. **The control** — whether Curfew is enforcing, plus the action. The
///    view's only accent, and a state dot that's muted when off.
struct TodaySundownView: View {
    /// The atmosphere to render behind the hero — the same moment the whole app
    /// shares this tick. Defaults to dusk for previews / the snapshot tier.
    var moment: SkyMoment = .dusk
    var greeting = "Good afternoon"
    var timeRemaining = "3h 30m"
    var emptyNote = "No curfew scheduled today."
    var lockTime = "6:00 PM"
    var unlockTime = "7:00 AM"
    var statusLine = "Curfew is off"
    var statusDetail = "Your Mac won't lock tonight until you turn it on."
    var isEnforcing = false
    var showAccessibilityWarning = false
    /// Trailing consecutive nights held. Shows a streak badge when ≥ 2.
    var streak: Int = 0
    var primaryActionLabel = "Turn On"
    var onPrimaryAction: () -> Void = {}
    /// Tapping the empty-state note (no window scheduled) navigates to Schedule.
    var onEmptyNoteAction: () -> Void = {}
    var onResolveAccessibility: () -> Void = {}

    /// Briefly true after `showAccessibilityWarning` flips false, to show a
    /// success confirmation before clearing the banner entirely.
    @State private var justGrantedAccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sky
            decision
            accessibilityWarning
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, CurfewSpacing.xLarge)
        .background(SundownPalette.paper)
        .onChange(of: showAccessibilityWarning) { oldValue, newValue in
            guard oldValue && !newValue else { return }
            withAnimation { justGrantedAccess = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.4)) { justGrantedAccess = false }
            }
        }
    }

    // MARK: - The window (full-bleed living sky, the protagonist)

    /// The hero. The living ``SundownSky`` bleeds edge-to-edge — including up
    /// under the title bar via `ignoresSafeArea` — so the dusk reaches the very
    /// top of the window with the traffic lights floating over it. The text
    /// stays inside the safe area so the greeting clears the controls. The hero
    /// grows to fill all available height so the countdown floats in a large
    /// field and the control below docks at the bottom with no dead band.
    private var sky: some View {
        ZStack(alignment: .topLeading) {
            SundownSky(moment: moment)
                .overlay(alignment: .bottom) { bottomFade }
                .ignoresSafeArea(.container, edges: .top)
            skyContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 380)
    }

    private var skyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SundownPalette.warmWhite.opacity(0.95))

            if timeRemaining.isEmpty {
                Button(action: onEmptyNoteAction) {
                    Text(emptyNote)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(SundownPalette.warmWhite.opacity(0.92))
                        .frame(maxWidth: 460, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(timeRemaining)
                    .font(SundownType.display(108))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.5), value: timeRemaining)
                    .foregroundStyle(SundownPalette.warmWhite)
                    .shadow(color: .black.opacity(0.18), radius: 22, y: 8)

                HStack(spacing: 5) {
                    Text("until your Mac locks at")
                        .foregroundStyle(SundownPalette.warmWhite.opacity(0.72))
                    Text(lockTime)
                        .font(SundownType.strong(16))
                        .foregroundStyle(SundownPalette.warmWhite)
                }
                .font(SundownType.body(16))
                .padding(.top, 10)

                Text("Unlocks \(unlockTime)")
                    .font(SundownType.body(14))
                    .foregroundStyle(SundownPalette.warmWhite.opacity(0.55))
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 40)
        .padding(.top, 34)
        .padding(.bottom, 84)
    }

    /// Softens the sky's bottom edge into the page so there's no hard seam where
    /// the sky meets the surface below.
    private var bottomFade: some View {
        LinearGradient(
            colors: [.clear, SundownPalette.paper],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 150)
    }

    // MARK: - The control (system state + the only accent/action)

    private var decision: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                // The state dot ignites when Curfew is armed — a small ember
                // that kindles as you turn it on.
                Circle()
                    .fill(isEnforcing ? SundownPalette.ember : SundownPalette.ink.opacity(0.25))
                    .frame(width: 9, height: 9)
                    .shadow(color: SundownPalette.ember.opacity(isEnforcing ? 0.8 : 0), radius: 6)
                Text(statusLine)
                    .font(SundownType.title(19))
                    .foregroundStyle(SundownPalette.ink)
                    .contentTransition(.opacity)
            }

            if !statusDetail.isEmpty {
                Text(statusDetail)
                    .font(SundownType.body(15))
                    .foregroundStyle(SundownPalette.ink.opacity(0.6))
                    .contentTransition(.opacity)
            }

            if streak >= 2 {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(streak) nights in a row")
                        .font(SundownType.body(13))
                }
                .foregroundStyle(SundownPalette.ember)
                .padding(.top, 2)
                .transition(.opacity)
            }

            if !isEnforcing {
                Button(action: onPrimaryAction) {
                    Text(primaryActionLabel)
                        .font(SundownType.title(15))
                        .foregroundStyle(SundownPalette.warmWhite)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(SundownPalette.ember, in: .capsule)
                }
                .buttonStyle(.plain)
                .shadow(color: SundownPalette.ember.opacity(0.3), radius: 10, y: 4)
                .padding(.top, 3)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 30)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isEnforcing)
    }

    @ViewBuilder
    private var accessibilityWarning: some View {
        if justGrantedAccess {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Accessibility access granted.")
                    .font(SundownType.body(14))
                    .foregroundStyle(SundownPalette.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.green.opacity(0.12), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 40)
            .padding(.top, 22)
            .transition(.opacity)
        } else if showAccessibilityWarning {
            HStack(spacing: 11) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CurfewTheme.warning)
                Text("Curfew needs Accessibility access to enforce your schedule.")
                    .font(SundownType.body(14))
                    .foregroundStyle(SundownPalette.ink)
                Spacer(minLength: 12)
                Button("Grant Access", action: onResolveAccessibility)
                    .buttonStyle(.plain)
                    .font(SundownType.title(14))
                    .foregroundStyle(SundownPalette.ember)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(CurfewTheme.warning.opacity(0.13), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 40)
            .padding(.top, 22)
        }
    }
}
