import SwiftUI

/// Devices panel extensions on `SettingsView`. Surfaces
/// `DeviceRegistry.activeDevices` and the soft-delete affordance.
extension SettingsView {
    /// Lists every Mac currently syncing. Replaces the v0.1 "just the
    /// local Mac" placeholder in Settings → Devices; when cloud sync is
    /// off the panel still renders (with just the local row) so users
    /// know the feature exists before they enable Pro.
    ///
    /// Remove-device is a soft-delete — writes `removed: true` on the
    /// corresponding `Device` record rather than deleting it, so a
    /// re-launching Mac can re-register cleanly without a create/delete
    /// race.
    var devicesListPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Devices",
                subtitle: "Macs syncing this schedule via iCloud."
            )

            if model.deviceRegistry.activeDevices.isEmpty {
                Text(
                    "No devices registered yet. Enable iCloud sync " +
                        "in Settings → Devices → iCloud Sync."
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.deviceRegistry.activeDevices) { device in
                        deviceRow(device)
                        if device.id != model.deviceRegistry.activeDevices.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: DeviceSummary) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(device.isActiveLocal ? CurfewTheme.accent : CurfewTheme.mutedInk)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceName)
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.ink)

                Text(lastSeenLabel(for: device.lastSeen))
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            Spacer()

            if device.id == DeviceRegistry.localDeviceID() {
                Text("This Mac")
                    .font(CurfewTypography.label(11))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        CurfewTheme.surfaceMuted,
                        in: Capsule()
                    )
            }
        }
    }

    /// Relative last-seen text. "Now" while active, minute-granularity
    /// otherwise — seconds would churn the row every second.
    private func lastSeenLabel(for date: Date) -> String {
        let secondsAgo = Date().timeIntervalSince(date)
        if secondsAgo < 90 {
            return "Active now"
        }
        let minutesAgo = Int(secondsAgo / 60)
        if minutesAgo < 60 {
            return "Last seen \(minutesAgo) min ago"
        }
        let hoursAgo = minutesAgo / 60
        return "Last seen \(hoursAgo) h ago"
    }
}
