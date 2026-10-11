import AppKit
import CurfewKit
import SwiftUI

/// The About tab — app identity, Curfew Pro licensing, and the Getting Started
/// re-entry. Pulls Pro out of the old "Advanced" catch-all and gives licensing
/// the conventional macOS home (About) rather than burying it.
extension SettingsView {
    /// Composed About tab: who the app is, the Pro license, and a way back into
    /// onboarding.
    var aboutPanel: some View {
        VStack(spacing: CurfewSpacing.section) {
            appInfoPanel
            licensePanel
            setupPanel
        }
    }

    /// App icon, name, version/build, and a one-line description.
    private var appInfoPanel: some View {
        CurfewPanel {
            HStack(spacing: CurfewSpacing.large) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: CurfewSpacing.xSmall) {
                    Text("Curfew")
                        .font(CurfewTypography.title(22))
                        .foregroundStyle(CurfewTheme.ink)
                    Text(Self.versionString)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }

                Spacer(minLength: 0)
            }

            Text("A sundown for your Mac — deliberate limits on late-night work, "
                + "set while you're thinking clearly.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Version X (build Y)" from the bundle's Info.plist, with em-dash
    /// fallbacks so a stripped bundle still renders cleanly.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
