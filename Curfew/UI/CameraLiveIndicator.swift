import SwiftUI

/// In-app "the camera is on right now" indicator.
///
/// macOS shows its own green light next to the lens, and that light is the
/// authoritative one — it is drawn by the system and Curfew cannot suppress
/// it. This indicator exists because that light says only *some* app is using
/// the camera, and a user who has granted Curfew camera access deserves to be
/// told, inside Curfew, which app and why.
///
/// Renders nothing when the camera is off, so its presence on screen is itself
/// the signal. Two variants, matching ``EnforcementHealthBanner``: a full panel
/// for Settings and a single row for the fixed-width menu-bar popover.
struct CameraLiveIndicator: View {
    /// Whether a capture session is live.
    let isLive: Bool

    /// Invoked when the user taps "Turn Off". Wired to
    /// `model.disablePresenceDetection()`, which stops the camera immediately
    /// rather than at the next tick.
    let onTurnOff: () -> Void

    /// SF Symbol used by every camera-live surface.
    static let symbol = "video.fill"

    /// Headline shown while the camera is live.
    static let title = "Camera on"

    /// Body copy. States the two facts a user most wants confirmed at the
    /// moment they notice the green light.
    static let detail = "Curfew is checking whether you're at your Mac. "
        + "Frames are analysed on this Mac and never saved or sent anywhere."

    /// Full panel, or nothing when the camera is off.
    var body: some View {
        if isLive {
            CurfewPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Label(Self.title, systemImage: Self.symbol)
                        .font(CurfewTypography.bodyEmphasis(14))
                        .foregroundStyle(CurfewTheme.warning)

                    Text(Self.detail)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Turn Off Presence Detection", action: onTurnOff)
                        .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Self.title). \(Self.detail)")
        }
    }
}

/// Compact camera-live row for the menu-bar popover.
///
/// The popover is the surface a user reaches for when they notice the green
/// light and want to know who turned it on, so the answer has to be here and
/// not two clicks into Settings.
struct CompactCameraLiveIndicator: View {
    /// Whether a capture session is live.
    let isLive: Bool

    /// Tapping opens Settings, where the switch lives.
    let onOpenSettings: () -> Void

    /// Single row, or nothing when the camera is off.
    var body: some View {
        if isLive {
            CurfewPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Label(CameraLiveIndicator.title, systemImage: CameraLiveIndicator.symbol)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Presence Settings", action: onOpenSettings)
                        .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(CameraLiveIndicator.title). \(CameraLiveIndicator.detail)")
        }
    }
}
