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
    func connect(
        deviceID: UUID,
        onWakeStatus: @escaping (AccountWakeStatusUpdate) -> Void,
        onRemoteOverride: @escaping (AccountRemoteOverride) -> Void,
        onRemoteCommandResult: @escaping (RemoteCommandResult) -> Void,
        onFailure: @escaping (String) -> Void
    )
    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID)
    func disconnect()
}

@MainActor
final class NoOpAccountSyncTransport: AccountSyncTransporting {
    func connect(
        deviceID _: UUID,
        onWakeStatus _: @escaping (AccountWakeStatusUpdate) -> Void,
        onRemoteOverride _: @escaping (AccountRemoteOverride) -> Void,
        onRemoteCommandResult _: @escaping (RemoteCommandResult) -> Void,
        onFailure _: @escaping (String) -> Void
    ) {}
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
    var onRemoteOverrideReceived: ((AccountRemoteOverride) -> Void)?
    var onRemoteCommandResultReceived: ((RemoteCommandResult) -> Void)?

    private let transport: any AccountSyncTransporting

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
            onWakeStatus: { [weak self] in self?.receiveAuthenticatedWakeStatus($0) },
            onRemoteOverride: { [weak self] in self?.receiveAuthenticatedRemoteOverride($0) },
            onRemoteCommandResult: { [weak self] in self?.receiveRemoteCommandResult($0) },
            onFailure: { [weak self] in self?.reject($0) }
        )
    }

    func stop() {
        if isActive {
            transport.disconnect()
        }
        isActive = false
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
        syncStatus = .pendingEncryption
    }

    func receiveAuthenticatedWakeStatus(_ update: AccountWakeStatusUpdate) {
        guard isActive else { return }
        onWakeStatusReceived?(update)
    }

    func receiveAuthenticatedRemoteOverride(_ override: AccountRemoteOverride) {
        guard isActive else { return }
        onRemoteOverrideReceived?(override)
    }

    func receiveRemoteCommandResult(_ result: RemoteCommandResult) {
        guard isActive else { return }
        onRemoteCommandResultReceived?(result)
    }

    func markSynchronized(at date: Date) {
        guard isActive else { return }
        syncStatus = .synchronized(date)
    }

    func reject(_ reason: String) {
        guard isActive else { return }
        syncStatus = .rejected(reason)
    }
}
