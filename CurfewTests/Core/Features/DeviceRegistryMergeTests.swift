@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Covers the pure cross-device merge `DeviceRegistry` runs when remote
/// `Device` / `DeviceActivity` records arrive from another Mac. The merge
/// is a static function with value-typed inputs so it exercises without a
/// `CKContainer` or any CloudKit round trip.
struct DeviceRegistryMergeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func remote(
        id: String,
        name: String,
        lastSeen: Date,
        isActive: Bool = true,
        removed: Bool = false
    ) -> RemoteDeviceRecord {
        RemoteDeviceRecord(
            deviceID: id,
            deviceName: name,
            lastSeen: lastSeen,
            isActive: isActive,
            removed: removed
        )
    }

    @Test("Local device is always present and flagged as the local row")
    func localDeviceAlwaysPresent() {
        let merged = DeviceRegistry.mergeDevices(
            localID: "local",
            localName: "My Mac",
            localActive: true,
            remotes: [],
            now: now
        )
        #expect(merged.count == 1)
        #expect(merged[0].id == "local")
        #expect(merged[0].deviceName == "My Mac")
        #expect(merged[0].isActiveLocal)
    }

    @Test("A recent remote device is folded into the active list")
    func recentRemoteAppears() {
        let merged = DeviceRegistry.mergeDevices(
            localID: "local",
            localName: "My Mac",
            localActive: true,
            remotes: [remote(id: "studio", name: "Studio Mac", lastSeen: now)],
            now: now
        )
        let ids = merged.map(\.id)
        #expect(ids.contains("local"))
        #expect(ids.contains("studio"))
        let studio = merged.first { $0.id == "studio" }
        #expect(studio?.deviceName == "Studio Mac")
        // A remote row is never the local active row.
        #expect(studio?.isActiveLocal == false)
    }

    @Test("A remote device past the active threshold is dropped")
    func staleRemoteDropped() {
        let stale = now.addingTimeInterval(-(DeviceRegistry.activeThresholdSeconds + 60))
        let merged = DeviceRegistry.mergeDevices(
            localID: "local",
            localName: "My Mac",
            localActive: true,
            remotes: [remote(id: "studio", name: "Studio Mac", lastSeen: stale)],
            now: now
        )
        #expect(merged.map(\.id) == ["local"])
    }

    @Test("A soft-deleted remote device is excluded even when recent")
    func removedRemoteExcluded() {
        let merged = DeviceRegistry.mergeDevices(
            localID: "local",
            localName: "My Mac",
            localActive: true,
            remotes: [
                remote(id: "studio", name: "Studio Mac", lastSeen: now, removed: true)
            ],
            now: now
        )
        #expect(merged.map(\.id) == ["local"])
    }

    @Test("A remote record duplicating the local device does not double-list it")
    func remoteEchoOfLocalDeduped() {
        let merged = DeviceRegistry.mergeDevices(
            localID: "local",
            localName: "My Mac",
            localActive: true,
            remotes: [remote(id: "local", name: "My Mac (echo)", lastSeen: now)],
            now: now
        )
        #expect(merged.map(\.id) == ["local"])
        // The locally-sourced name and active flag win over the echo.
        #expect(merged[0].deviceName == "My Mac")
        #expect(merged[0].isActiveLocal)
    }

    @Test("Merged devices are ordered local-first then by most recent heartbeat")
    func orderingLocalFirstThenRecent() {
        let older = now.addingTimeInterval(-30)
        let newer = now.addingTimeInterval(-5)
        let merged = DeviceRegistry.mergeDevices(
            localID: "local",
            localName: "My Mac",
            localActive: true,
            remotes: [
                remote(id: "a", name: "A", lastSeen: older),
                remote(id: "b", name: "B", lastSeen: newer)
            ],
            now: now
        )
        #expect(merged.map(\.id) == ["local", "b", "a"])
    }

    @Test("Remote device carries its own active flag through the merge")
    func remoteActiveFlagPreserved() {
        let merged = DeviceRegistry.mergeDevices(
            localID: "local",
            localName: "My Mac",
            localActive: true,
            remotes: [
                remote(id: "studio", name: "Studio Mac", lastSeen: now, isActive: false)
            ],
            now: now
        )
        let studio = merged.first { $0.id == "studio" }
        #expect(studio != nil)
        // isActiveLocal is reserved for the local row; remote rows are
        // never "active local" regardless of their own active flag.
        #expect(studio?.isActiveLocal == false)
    }
}
