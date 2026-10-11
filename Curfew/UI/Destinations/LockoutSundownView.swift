import CurfewKit
import SwiftUI

/// Presentational lockout overlay in the sundown language — the signature
/// full-screen moment. Nightfall: a deep dusk sky with the last embers glowing
/// low on the horizon, the current time as a calm clock, and the unlock time.
/// The override is a quiet affordance, deliberately understated.
///
/// Driven by plain values so it renders live (wired into the real lockout
/// window) or in the snapshot tier with demo defaults.
struct LockoutSundownView: View {
    var currentTime = "11:02 PM"
    var unlockTime = "7:00 AM"
    var message = ""
    var onOverride: () -> Void = {}

    var body: some View {
        ZStack {
            Palette.nightSky.ignoresSafeArea()
            emberGlow
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(currentTime)
                .font(.system(size: 112, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.warmWhite)
                .shadow(color: .black.opacity(0.3), radius: 30, y: 10)

            Text("Locked until \(unlockTime)")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.warmWhite.opacity(0.74))
                .padding(.top, 16)

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.warmWhite.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            Spacer()

            Button("Override", action: onOverride)
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.warmWhite.opacity(0.42))
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
    }

    /// The set sun's afterglow — a warm bloom low on the horizon.
    private var emberGlow: some View {
        RadialGradient(
            colors: [Palette.ember.opacity(0.5), .clear],
            center: .bottom,
            startRadius: 0,
            endRadius: 620
        )
        .ignoresSafeArea()
        .blendMode(.screen)
    }

    private enum Palette {
        static let warmWhite = SundownPalette.warmWhite
        static let ember = SundownPalette.emberBright
        static let nightSky = SundownPalette.nightSky
    }
}
