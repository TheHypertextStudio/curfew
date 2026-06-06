@testable import Curfew
import Foundation
import Testing

/// Exercises `DeviceRegistry` against an in-memory `DeviceRecordSyncing`
/// stub so the upsert / heartbeat / remote-fold wiring is verified without
/// a `CKContainer` or any real CloudKit traffic.
@MainActor
struct DeviceRegistryStoreTests {
    @Test("start() upserts a Device record for this Mac")
    func startUpsertsLocalDevice() async {
        let store = StubDeviceStore()
        let registry = DeviceRegistry(
            idleWatcher: IdleWatcher(source: ZeroIdleSource()),
            store: store,
            deviceID: "local",
            deviceName: "My Mac"
        )

        registry.start()
        // The upsert is fire-and-forget so start() never blocks on CloudKit;
        // await it here before asserting on the captured record.
        await registry.awaitPendingRegistrationForTesting()

        #expect(store.upsertedDevices.contains { $0.deviceID == "local" })
        let upserted = store.upsertedDevices.first { $0.deviceID == "local" }
        #expect(upserted?.deviceName == "My Mac")
        #expect(upserted?.removed == false)

        registry.stop()
    }

    @Test("start() folds a recent remote device into activeDevices")
    func startFoldsRemoteDevice() async {
        let store = StubDeviceStore()
        store.remotesToReturn = [
            RemoteDeviceRecord(
                deviceID: "studio",
                deviceName: "Studio Mac",
                lastSeen: Date(),
                isActive: true,
                removed: false
            )
        ]
        let registry = DeviceRegistry(
            idleWatcher: IdleWatcher(source: ZeroIdleSource()),
            store: store,
            deviceID: "local",
            deviceName: "My Mac"
        )

        registry.start()
        // The remote fetch is async; await the registry settling.
        await registry.refreshRemoteDevicesForTesting()

        let ids = registry.activeDevices.map(\.id)
        #expect(ids.contains("local"))
        #expect(ids.contains("studio"))

        registry.stop()
    }

    @Test("Without a store the registry still surfaces the local device")
    func noStoreStillSurfacesLocal() {
        let registry = DeviceRegistry(
            idleWatcher: IdleWatcher(source: ZeroIdleSource()),
            store: nil,
            deviceID: "local",
            deviceName: "My Mac"
        )
        registry.start()
        #expect(registry.activeDevices.map(\.id) == ["local"])
        registry.stop()
    }
}

/// In-memory `DeviceRecordSyncing` capturing upserts and returning a
/// scripted set of remote devices. No CloudKit.
private final class StubDeviceStore: DeviceRecordSyncing, @unchecked Sendable {
    var upsertedDevices: [RemoteDeviceRecord] = []
    var heartbeats: [RemoteDeviceRecord] = []
    var remotesToReturn: [RemoteDeviceRecord] = []

    func upsertDevice(_ record: RemoteDeviceRecord) async {
        upsertedDevices.append(record)
    }

    func writeHeartbeat(_ record: RemoteDeviceRecord) async {
        heartbeats.append(record)
    }

    func fetchRemoteDevices() async -> [RemoteDeviceRecord] {
        remotesToReturn
    }
}

/// Idle source that always reports zero seconds of idle — the user is
/// "active" for the duration of a test.
private final class ZeroIdleSource: IdleTimeSource {
    func secondsSinceLastInput() -> TimeInterval {
        0
    }
}
