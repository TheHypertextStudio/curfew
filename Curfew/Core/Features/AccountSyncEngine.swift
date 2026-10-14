import Combine
import CurfewKit
import Foundation

/// Transport boundary for the account coordinator. The production WebSocket
/// adapter can be attached without teaching the app model about routing or
/// sending decrypted settings across a process boundary.
@MainActor
protocol AccountSyncTransporting: AnyObject {
    func connect(deviceID: UUID, callbacks: AccountSyncTransportCallbacks)
    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID)
    func disconnect()
    func disconnectAndWaitForPendingOperations() async
}

extension AccountSyncTransporting {
    func disconnectAndWaitForPendingOperations() async {
        disconnect()
    }
}

struct AccountSyncTransportCallbacks {
    let onSynchronized: (Date) -> Void
    let onOffline: () -> Void
    let onWakeStatus: (AccountWakeStatusUpdate) -> Void
    let onRemoteOverride: (AccountRemoteOverride?) -> Void
    let onRemoteCommandResult: (RemoteCommandResult) -> Void
    let onFailure: (String) -> Void
}

@MainActor
final class NoOpAccountSyncTransport: AccountSyncTransporting {
    func connect(deviceID _: UUID, callbacks _: AccountSyncTransportCallbacks) {}
    func publishDeviceStatus(_: DeviceStatusReport, deviceID _: UUID) {}
    func disconnect() {}
}

/// Owns Curfew Account sync lifecycle and authenticated inbound domain events.
/// Generated-wire decoding happens in CurfewProtocolBridge; E2EE record
/// sealing happens before an outbound transport is allowed to send anything.
@MainActor
final class AccountSyncEngine: ObservableObject {
    @Published private(set) var syncStatus: AccountSyncStatus = .accountFree
    private(set) var isActive = false
    private(set) var isMaintenancePaused = false

    var onWakeStatusReceived: ((AccountWakeStatusUpdate) -> Void)?
    var onSynchronizedReceived: ((Date) -> Void)?
    var onRemoteOverrideReceived: ((AccountRemoteOverride?) -> Void)?
    var onRemoteCommandResultReceived: ((RemoteCommandResult) -> Void)?

    private let transport: any AccountSyncTransporting
    private var hasPendingEncryptedChanges = false
    private var lifecycleGeneration = 0
    private var requiresAuthentication = false

    init(transport: any AccountSyncTransporting) {
        self.transport = transport
    }

    func reconnectAfterAuthentication(enrollment: AccountDeviceEnrollment) async {
        guard !isMaintenancePaused else { return }
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        isActive = false
        if !requiresAuthentication {
            syncStatus = .connecting
        }
        await transport.disconnectAndWaitForPendingOperations()
        guard generation == lifecycleGeneration, !isMaintenancePaused else { return }
        requiresAuthentication = false
        start(enrollment: enrollment)
    }

    func start(enrollment: AccountDeviceEnrollment) {
        guard !isActive, !isMaintenancePaused, !requiresAuthentication else { return }
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        isActive = true
        syncStatus = .connecting
        transport.connect(
            deviceID: enrollment.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { [weak self] date in
                    guard let self, lifecycleGeneration == generation else { return }
                    markSynchronized(at: date)
                },
                onOffline: { [weak self] in
                    guard let self, lifecycleGeneration == generation else { return }
                    markOffline()
                },
                onWakeStatus: { [weak self] status in
                    guard let self, lifecycleGeneration == generation else { return }
                    receiveAuthenticatedWakeStatus(status)
                },
                onRemoteOverride: { [weak self] override in
                    guard let self, lifecycleGeneration == generation else { return }
                    receiveAuthenticatedRemoteOverride(override)
                },
                onRemoteCommandResult: { [weak self] result in
                    guard let self, lifecycleGeneration == generation else { return }
                    receiveRemoteCommandResult(result)
                },
                onFailure: { [weak self] reason in
                    guard let self, lifecycleGeneration == generation else { return }
                    reject(reason)
                }
            )
        )
    }

    func stop() {
        lifecycleGeneration += 1
        if isActive {
            transport.disconnect()
        }
        isActive = false
        hasPendingEncryptedChanges = false
        requiresAuthentication = false
        syncStatus = .accountFree
    }

    func pauseForMaintenance() async {
        lifecycleGeneration += 1
        isMaintenancePaused = true
        isActive = false
        if !requiresAuthentication {
            syncStatus = .offline
        }
        await transport.disconnectAndWaitForPendingOperations()
    }

    func resumeAfterMaintenance(enrollment: AccountDeviceEnrollment?) {
        isMaintenancePaused = false
        if let enrollment {
            start(enrollment: enrollment)
        }
    }

    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID) {
        guard isActive else { return }
        transport.publishDeviceStatus(report, deviceID: deviceID)
    }

    /// Marks a local mutation as waiting for the E2EE writer. No plaintext
    /// settings value is accepted by this API.
    func noteLocalSettingsChanged() {
        guard isActive else { return }
        hasPendingEncryptedChanges = true
        syncStatus = .pendingEncryption
    }

    func receiveAuthenticatedWakeStatus(_ update: AccountWakeStatusUpdate) {
        guard isActive else { return }
        onWakeStatusReceived?(update)
    }

    func receiveAuthenticatedRemoteOverride(_ override: AccountRemoteOverride?) {
        guard isActive else { return }
        onRemoteOverrideReceived?(override)
    }

    func receiveRemoteCommandResult(_ result: RemoteCommandResult) {
        guard isActive else { return }
        onRemoteCommandResultReceived?(result)
    }

    func markSynchronized(at date: Date) {
        guard isActive else { return }
        syncStatus = hasPendingEncryptedChanges ? .pendingEncryption : .synchronized(date)
        onSynchronizedReceived?(date)
    }

    func markOffline() {
        guard isActive else { return }
        syncStatus = .offline
    }

    func reject(_ reason: String) {
        guard isActive else { return }
        lifecycleGeneration += 1
        isActive = false
        requiresAuthentication = true
        syncStatus = .rejected(reason)
        transport.disconnect()
    }
}
