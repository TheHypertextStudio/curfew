import CurfewKit
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
        SettingsGroup(
            "Macs",
            footer: model.deviceRegistry.activeDevices.isEmpty
                ? "No other Macs yet. Turn on iCloud sync in Account to add them."
                : nil
        ) {
            ForEach(model.deviceRegistry.activeDevices) { device in
                SettingsActionRow(
                    title: device.id == DeviceRegistry.localDeviceID()
                        ? "\(device.deviceName) (this Mac)" : device.deviceName,
                    detail: lastSeenLabel(for: device.lastSeen),
                    actionTitle: nil
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
