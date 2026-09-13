import Combine
import Foundation

enum AccountSyncStatus: Equatable {
    case accountFree
    case connecting
    case synchronized(Date)
    case pendingEncryption
    case offline
    case rejected(String)
}

/// Transport boundary for the account coordinator. The production WebSocket
/// adapter can be attached without teaching the app model about routing or
/// sending decrypted settings across a process boundary.
@MainActor
protocol AccountSyncTransporting: AnyObject {
    func connect(deviceID: UUID, callbacks: AccountSyncTransportCallbacks)
    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID)
    func disconnect()
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

    var onWakeStatusReceived: ((AccountWakeStatusUpdate) -> Void)?
    var onRemoteOverrideReceived: ((AccountRemoteOverride?) -> Void)?
    var onRemoteCommandResultReceived: ((RemoteCommandResult) -> Void)?

    private let transport: any AccountSyncTransporting
    private var hasPendingEncryptedChanges = false

    init(
        transport: (any AccountSyncTransporting)? = nil
    ) {
        self.transport = transport ?? NativeAccountSyncTransport()
    }

    func start(enrollment: AccountDeviceEnrollment) {
        guard !isActive else { return }
        isActive = true
        syncStatus = .connecting
        transport.connect(
            deviceID: enrollment.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { [weak self] in self?.markSynchronized(at: $0) },
                onOffline: { [weak self] in self?.markOffline() },
                onWakeStatus: { [weak self] in self?.receiveAuthenticatedWakeStatus($0) },
                onRemoteOverride: { [weak self] in self?.receiveAuthenticatedRemoteOverride($0) },
                onRemoteCommandResult: { [weak self] in self?.receiveRemoteCommandResult($0) },
                onFailure: { [weak self] in self?.reject($0) }
            )
        )
    }

    func stop() {
        if isActive {
            transport.disconnect()
        }
        isActive = false
        hasPendingEncryptedChanges = false
        syncStatus = .accountFree
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
    }

    func markOffline() {
        guard isActive else { return }
        syncStatus = .offline
    }

    func reject(_ reason: String) {
        guard isActive else { return }
        syncStatus = .rejected(reason)
    }
}
