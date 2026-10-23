import AppKit
import CurfewKit
import SwiftUI

extension SettingsView {
    var aboutPanel: some View {
        Group {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Curfew").font(.title2.bold())
                        Text(Self.versionString).foregroundStyle(CurfewTheme.mutedInk)
                    }
                }
                Text("Schedule when Curfew blocks access to your Mac.")
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            licensePanel
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
