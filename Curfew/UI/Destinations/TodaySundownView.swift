import SwiftUI

/// Presentational Today surface in the sundown language. Driven by plain
/// values + actions so it can be rendered live (via ``TodayView``) or in the
/// snapshot tier with demo defaults.
///
/// Today carries one thing: tonight's curfew window, and the control for it.
/// 1. **The window** — the countdown is the protagonist (full-bleed sky, not a
///    card); the lock time is its primary detail, the unlock time the quieter
///    other end of the same event.
/// 2. **The control** — whether Curfew is enforcing, plus the action. The
///    view's only accent, and a state dot that's muted when off.
struct TodaySundownView: View {
    var greeting = "Good afternoon"
    var timeRemaining = "3h 30m"
    var emptyNote = "No curfew scheduled today."
    var lockTime = "6:00 PM"
    var unlockTime = "7:00 AM"
    var statusLine = "Curfew is off"
    var statusDetail = "Your Mac won't lock tonight until you turn it on."
    var isEnforcing = false
    var showAccessibilityWarning = false
    var primaryActionLabel = "Turn On"
    var onPrimaryAction: () -> Void = {}
    var onResolveAccessibility: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sky
            decision
            accessibilityWarning
        }
        .padding(.bottom, 38)
        .background(Palette.canvas)
    }

    // MARK: - The window (full-bleed atmosphere, the protagonist)

    private var sky: some View {
        ZStack(alignment: .topLeading) {
            Palette.sky
            sunGlow
            vignette
            bottomFade
            skyContent
        }
        .frame(height: 452)
    }

    private var skyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.warmWhite.opacity(0.95))

            if timeRemaining.isEmpty {
                Text(emptyNote)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Palette.warmWhite.opacity(0.92))
                    .frame(maxWidth: 460, alignment: .leading)
                    .padding(.top, 16)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(timeRemaining)
                    .font(SundownType.display(108))
                    .foregroundStyle(Palette.warmWhite)
                    .shadow(color: .black.opacity(0.18), radius: 22, y: 8)

                HStack(spacing: 5) {
                    Text("until your Mac locks at")
                        .foregroundStyle(Palette.warmWhite.opacity(0.72))
                    Text(lockTime)
                        .font(SundownType.strong(16))
                        .foregroundStyle(Palette.warmWhite)
                }
                .font(SundownType.body(16))
                .padding(.top, 10)

                Text("Unlocks \(unlockTime)")
                    .font(SundownType.body(14))
                    .foregroundStyle(Palette.warmWhite.opacity(0.55))
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 34)
        .padding(.bottom, 84)
    }

    /// The just-set sun: a soft warm bloom low on the horizon.
    private var sunGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Palette.glow.opacity(0.45), Palette.glow.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 240
                )
            )
            .frame(width: 480, height: 480)
            .offset(x: 150, y: 168)
            .blur(radius: 18)
    }

    private var vignette: some View {
        RadialGradient(
            colors: [.clear, .black.opacity(0.2)],
            center: .center,
            startRadius: 220,
            endRadius: 560
        )
        .blendMode(.multiply)
    }

    /// Softens the sky's bottom edge into the page canvas so there's no hard
    /// seam where the sky meets the surface below.
    private var bottomFade: some View {
        LinearGradient(
            colors: [.clear, Palette.canvas],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 150)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - The control (system state + the only accent/action)

    private var decision: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Circle()
                    .fill(isEnforcing ? Palette.ember : Palette.ink.opacity(0.25))
                    .frame(width: 9, height: 9)
                Text(statusLine)
                    .font(SundownType.title(19))
                    .foregroundStyle(Palette.ink)
            }

            if !statusDetail.isEmpty {
                Text(statusDetail)
                    .font(SundownType.body(15))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }

            if !isEnforcing {
                Button(action: onPrimaryAction) {
                    Text(primaryActionLabel)
                        .font(SundownType.title(15))
                        .foregroundStyle(Palette.warmWhite)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Palette.ember, in: .capsule)
                }
                .buttonStyle(.plain)
                .shadow(color: Palette.ember.opacity(0.3), radius: 10, y: 4)
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 30)
    }

    @ViewBuilder
    private var accessibilityWarning: some View {
        if showAccessibilityWarning {
            HStack(spacing: 11) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.warning)
                Text("Allow Accessibility so Curfew can block bypass keys during lockout.")
                    .font(SundownType.body(14))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 12)
                Button("Open Settings", action: onResolveAccessibility)
                    .buttonStyle(.plain)
                    .font(SundownType.title(14))
                    .foregroundStyle(Palette.ember)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Palette.warning.opacity(0.13), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 40)
            .padding(.top, 22)
        }
    }

    /// Warm sundown palette, scoped to this view.
    private enum Palette {
        static let canvas = Color(red: 0.96, green: 0.94, blue: 0.90)
        static let warmWhite = Color(red: 0.99, green: 0.97, blue: 0.94)
        static let ink = Color(red: 0.19, green: 0.16, blue: 0.14)
        static let ember = Color(red: 0.85, green: 0.45, blue: 0.23)
        static let warning = Color(red: 0.80, green: 0.52, blue: 0.20)
        static let glow = Color(red: 1.0, green: 0.85, blue: 0.62)

        /// Dusk → horizon → page. The final stop melts into the canvas so the
        /// hero has no hard "card" edge; it dissolves into the surface below.
        static let sky = LinearGradient(
            stops: [
                .init(color: Color(red: 0.24, green: 0.25, blue: 0.34), location: 0.0),
                .init(color: Color(red: 0.44, green: 0.40, blue: 0.46), location: 0.45),
                .init(color: Color(red: 0.70, green: 0.58, blue: 0.52), location: 0.80),
                .init(color: Color(red: 0.88, green: 0.79, blue: 0.66), location: 0.93),
                .init(color: Color(red: 0.96, green: 0.94, blue: 0.90), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
