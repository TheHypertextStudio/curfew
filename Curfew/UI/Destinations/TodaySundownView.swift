import CurfewKit
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
            // Extra window height collects here as calm canvas rather than a gap
            // between the countdown and the control.
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CurfewTheme.canvas)
        .onChange(of: showAccessibilityWarning) { oldValue, newValue in
            guard oldValue, !newValue else { return }
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
                .backgroundExtensionEffect()
                .overlay(alignment: .bottom) { bottomFade }
                .overlay { skyTextScrim }
                .ignoresSafeArea(.container, edges: .top)
            skyContent
        }
        // A fixed, composed hero — capped so the mesh and sun never stretch or
        // distort to fill an arbitrarily tall window. Extra height becomes calm
        // canvas below, not a stretched sky.
        .frame(maxWidth: .infinity)
        .frame(minHeight: 380, maxHeight: 520)
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
                        .foregroundStyle(SundownPalette.warmWhite.opacity(0.9))
                    Text(lockTime)
                        .font(SundownType.strong(16))
                        .foregroundStyle(SundownPalette.warmWhite)
                }
                .font(SundownType.body(16))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
                .padding(.top, 10)

                Text("Unlocks \(unlockTime)")
                    .font(SundownType.body(14))
                    .foregroundStyle(SundownPalette.warmWhite.opacity(0.78))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 40)
        .padding(.top, 34)
        // Sit the countdown near the hero's lower edge so it flows straight into
        // the control beneath — no floating gap between them.
        .padding(.bottom, 30)
    }

    /// A legibility scrim under the hero text. The mesh brightens toward the
    /// horizon, where the countdown sits, so light warmWhite text would wash out
    /// against the bright band without this. A soft top-to-bottom dark gradient
    /// darkens only the lower hero — strongest under the countdown — so the text
    /// always clears the sky at any time of day, while the bright crown above
    /// stays untouched.
    private var skyTextScrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.08), .black.opacity(0.32)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    /// Softens the sky's bottom edge into the page so there's no hard seam where
    /// the sky meets the surface below.
    private var bottomFade: some View {
        LinearGradient(
            colors: [.clear, CurfewTheme.canvas],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 150)
    }

    // MARK: - The control (system state + the only accent/action)

    private var decision: some View {
        VStack(alignment: .leading, spacing: 10) {
            // When armed, the countdown above already says Curfew is on — no
            // redundant status badge. Off / needs-setup gets a real invitation
            // to act: a heading, one concrete line, and the action.
            if !isEnforcing {
                Text(statusLine)
                    .font(SundownType.title(19))
                    .foregroundStyle(CurfewTheme.ink)
                    .contentTransition(.opacity)

                if !statusDetail.isEmpty {
                    Text(statusDetail)
                        .font(SundownType.body(15))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .contentTransition(.opacity)
                }

                Button(action: onPrimaryAction) {
                    Text(primaryActionLabel)
                }
                .buttonStyle(SundownCapsuleButtonStyle())
                .padding(.top, 4)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            // The earned streak is the one quiet, meaningful note worth keeping
            // while armed.
            if streak >= 2 {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(streak) nights in a row")
                        .font(SundownType.body(13))
                }
                .foregroundStyle(CurfewTheme.accent)
                .padding(.top, isEnforcing ? 0 : 2)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 14)
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
                    .foregroundStyle(CurfewTheme.ink)
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
                    .foregroundStyle(CurfewTheme.ink)
                Spacer(minLength: 12)
                Button("Grant Access", action: onResolveAccessibility)
                    .buttonStyle(.plain)
                    .font(SundownType.title(14))
                    .foregroundStyle(CurfewTheme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(CurfewTheme.warning.opacity(0.13), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 40)
            .padding(.top, 22)
        }
    }
}

/// The Today hero's primary call to action — an ember capsule that reads as
/// the one confident action over the sky. Distinct from the chrome's
/// `CurfewPrimaryButtonStyle` (a small rounded rect) because this button is the
/// emotional centre of the empty state; it carries a soft ember glow and a
/// springy press so turning Curfew on feels deliberate.
private struct SundownCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SundownType.title(15))
            .foregroundStyle(SundownPalette.warmWhite)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(CurfewTheme.accent, in: .capsule)
            .shadow(
                color: CurfewTheme.accent.opacity(configuration.isPressed ? 0.18 : 0.3),
                radius: 10,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
