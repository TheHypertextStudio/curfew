@testable import Curfew
@testable import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct PrivilegedHelperManagerTests {
    @Test("An enabled helper is ready only while its daemon heartbeat is fresh")
    func daemonReadinessRequiresFreshHeartbeat() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-helper-heartbeat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let heartbeat = root.appendingPathComponent(".daemon-alive")
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .enabled),
            loginItemService: StubAppService(status: .notRegistered),
            daemonHeartbeatURL: heartbeat,
            now: { now }
        )
        manager.refreshStatus()
        #expect(!manager.isDaemonResponding)

        try Data("alive".utf8).write(to: heartbeat)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-15)],
            ofItemAtPath: heartbeat.path
        )
        #expect(manager.isDaemonResponding)

        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-90)],
            ofItemAtPath: heartbeat.path
        )
        #expect(!manager.isDaemonResponding)
    }

    @Test("Studio Dev does not claim remote-lock readiness while personal Curfew owns enforcement")
    func studioRemoteReadinessRespectsHigherPriorityOwner() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-studio-owner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let heartbeat = root.appendingPathComponent(".daemon-alive")
        try Data("alive".utf8).write(to: heartbeat)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-15)],
            ofItemAtPath: heartbeat.path
        )
        let personalOwner = EnforcementOwner(
            flavor: CurfewFlavor.production.rawValue,
            bundleIdentifier: SharedPaths.defaultsSuiteName(for: .production),
            displayName: "Curfew",
            processIdentifier: 42,
            acquiredAt: now
        )
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .enabled),
            loginItemService: StubAppService(status: .notRegistered),
            daemonHeartbeatURL: heartbeat,
            now: { now },
            flavor: .studioDevelopment,
            liveEnforcementOwner: { personalOwner }
        )
        manager.refreshStatus()

        #expect(manager.isDaemonResponding)
        #expect(!manager.isRemoteLockEnforcementAvailable)
    }

    @Test("refreshStatus mirrors daemon and login item statuses")
    func refreshStatusMirrorsServices() {
        let daemon = StubAppService(status: .requiresApproval)
        let loginItem = StubAppService(status: .enabled)
        let manager = PrivilegedHelperManager(
            daemonService: daemon,
            loginItemService: loginItem
        )

        manager.refreshStatus()

        #expect(manager.daemonStatus == SMAppService.Status.requiresApproval)
        #expect(manager.loginItemStatus == SMAppService.Status.enabled)
    }

    @Test("installDaemon registers the daemon service and clears prior error state")
    func installDaemonRegisters() {
        let daemon = StubAppService(status: .notRegistered, registerResult: .success(.enabled))
        let manager = PrivilegedHelperManager(
            daemonService: daemon,
            loginItemService: StubAppService(status: .notRegistered)
        )

        manager.installDaemon()

        #expect(daemon.registerCallCount == 1)
        #expect(manager.daemonStatus == SMAppService.Status.enabled)
        #expect(manager.lastError == nil)
    }

    @Test("installDaemon surfaces service errors")
    func installDaemonStoresError() {
        let daemon = StubAppService(
            status: .notRegistered,
            registerResult: .failure(StubServiceError.registerFailed)
        )
        let manager = PrivilegedHelperManager(
            daemonService: daemon,
            loginItemService: StubAppService(status: .notRegistered)
        )

        manager.installDaemon()

        #expect(manager.daemonStatus == SMAppService.Status.notRegistered)
        #expect(manager.lastError == StubServiceError.registerFailed.localizedDescription)
        #expect(manager.connectionState == .registrationFailed)
    }

    @Test("daemon status reconciliation exposes the authoritative active record")
    func daemonStatusReconciliation() async {
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: Date(),
            scheduledUnlockAt: Date().addingTimeInterval(600),
            kind: .scheduledTime
        )
        let rpc = StubDaemonRPC(statusResult: .success(PrivilegedDaemonStatus(
            activeRecord: record,
            lastHeartbeatAt: Date(),
            shutdownIssued: false
        )))
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .enabled),
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: rpc
        )

        let status = await manager.reconcileDaemonStatus()

        #expect(status?.activeRecord == record)
        #expect(manager.connectionState == .ready)
    }

    @Test("unavailable daemon RPC is surfaced as enforcement health")
    func unavailableDaemonRPCIsSurfaced() async {
        let rpc = StubDaemonRPC(statusResult: .failure(PrivilegedDaemonRPCError.unavailable))
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .enabled),
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: rpc
        )

        _ = await manager.reconcileDaemonStatus()

        #expect(manager.connectionState == .unavailable)
        #expect(manager.enforcementAvailability == .unavailable)
        #expect(manager.lastError == PrivilegedDaemonRPCError.unavailable.localizedDescription)
    }

    @Test("connection states map to enforcement availability")
    func connectionStatesMapToEnforcementAvailability() {
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .notRegistered),
            loginItemService: StubAppService(status: .notRegistered)
        )

        #expect(manager.enforcementAvailability == .unavailable)
        manager.seedConnectionStateForTesting(.unauthorized)
        #expect(manager.enforcementAvailability == .unauthorized)
        manager.seedConnectionStateForTesting(.stale)
        #expect(manager.enforcementAvailability == .stale)
        manager.seedConnectionStateForTesting(.registrationFailed)
        #expect(manager.enforcementAvailability == .registrationFailed)
        manager.seedConnectionStateForTesting(.ready)
        #expect(manager.enforcementAvailability == .ready)
    }

    @Test("uninstall does not unregister the daemon during an active lockout")
    func uninstallRejectedDuringActiveLockout() async {
        let daemon = StubAppService(status: .enabled)
        let rpc = StubDaemonRPC(
            statusResult: .success(PrivilegedDaemonStatus(
                activeRecord: nil,
                lastHeartbeatAt: nil,
                shutdownIssued: false
            )),
            prepareResult: .failure(PrivilegedDaemonRPCError.activeLockout)
        )
        let manager = PrivilegedHelperManager(
            daemonService: daemon,
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: rpc
        )

        await manager.uninstallDaemon()

        #expect(daemon.unregisterCallCount == 0)
        #expect(manager.lastError == PrivilegedDaemonRPCError.activeLockout.localizedDescription)
    }

    @Test("registerLoginItem and unregisterLoginItem use the login item service")
    func loginItemRegistrationFlows() {
        let loginItem = StubAppService(status: .notRegistered, registerResult: .success(.enabled))
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .notRegistered),
            loginItemService: loginItem
        )

        manager.registerLoginItem()
        #expect(loginItem.registerCallCount == 1)
        #expect(manager.loginItemStatus == SMAppService.Status.enabled)

        loginItem.status = .enabled
        loginItem.unregisterResult = .success(.notRegistered)
        manager.unregisterLoginItem()
        #expect(loginItem.unregisterCallCount == 1)
        #expect(manager.loginItemStatus == SMAppService.Status.notRegistered)
    }

    @Test("A failed wake completion is not acknowledged")
    func failedWakeCompletionRequiresRetry() async {
        let rpc = StubDaemonRPC(
            statusResult: .success(PrivilegedDaemonStatus(
                activeRecord: nil,
                lastHeartbeatAt: nil,
                shutdownIssued: false
            )),
            completionResult: .failure(PrivilegedDaemonRPCError.stale)
        )
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .enabled),
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: rpc
        )
        let acknowledged: Bool = await manager.completeLockout(
            lockoutID: UUID(),
            reason: .accountWakeRelease
        )
        #expect(!acknowledged)
        #expect(manager.connectionState == .stale)
    }

    @Test("Studio uninstall unregisters both services and reports any failure")
    func studioUninstallRegistrationCleanup() {
        let daemon = StubAppService(
            status: .enabled,
            unregisterResult: .failure(StubServiceError.unregisterFailed)
        )
        let loginItem = StubAppService(status: .enabled)
        let manager = PrivilegedHelperManager(daemonService: daemon, loginItemService: loginItem)

        let failures = manager.unregisterForUninstall()

        #expect(daemon.unregisterCallCount == 1)
        #expect(loginItem.unregisterCallCount == 1)
        #expect(failures.count == 1)
        #expect(failures[0].contains("daemon"))
        #expect(manager.daemonStatus == .enabled)
        #expect(manager.loginItemStatus == .notRegistered)
    }
}

private final class StubDaemonRPC: PrivilegedDaemonRPCControlling, @unchecked Sendable {
    let statusResult: Result<PrivilegedDaemonStatus, Error>
    let prepareResult: Result<Void, Error>
    let completionResult: Result<Void, Error>

    init(
        statusResult: Result<PrivilegedDaemonStatus, Error>,
        prepareResult: Result<Void, Error> = .success(()),
        completionResult: Result<Void, Error> = .success(())
    ) {
        self.statusResult = statusResult
        self.prepareResult = prepareResult
        self.completionResult = completionResult
    }

    func armLockout(_: LockoutDeadlineRecord) async throws {}
    func heartbeat(lockoutID _: UUID) async throws {}
    func completeLockout(lockoutID _: UUID, reason _: PrivilegedCompletionReason) async throws {
        try completionResult.get()
    }

    func status() async throws -> PrivilegedDaemonStatus {
        try statusResult.get()
    }

    func prepareForUninstall() async throws {
        try prepareResult.get()
    }
}

private final class StubAppService: AppServiceControlling {
    var status: SMAppService.Status
    var registerResult: Result<SMAppService.Status, Error>
    var unregisterResult: Result<SMAppService.Status, Error>
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(
        status: SMAppService.Status,
        registerResult: Result<SMAppService.Status, Error> = .success(.enabled),
        unregisterResult: Result<SMAppService.Status, Error> = .success(.notRegistered)
    ) {
        self.status = status
        self.registerResult = registerResult
        self.unregisterResult = unregisterResult
    }

    func register() throws {
        registerCallCount += 1
        switch registerResult {
        case .success(let updatedStatus):
            status = updatedStatus
        case .failure(let error):
            throw error
        }
    }

    func unregister() throws {
        unregisterCallCount += 1
        switch unregisterResult {
        case .success(let updatedStatus):
            status = updatedStatus
        case .failure(let error):
            throw error
        }
    }
}

private enum StubServiceError: LocalizedError {
    case registerFailed
    case unregisterFailed

    var errorDescription: String? {
        switch self {
        case .registerFailed:
            "The service failed to register."
        case .unregisterFailed:
            "The service failed to unregister."
        }
    }
}

extension PrivilegedHelperManagerTests {
    @Test("A fresh daemon file cannot make a rejected authenticated connection ready")
    func remoteReadinessRequiresAuthenticatedConnection() throws {
        let now = Date()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-helper-auth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let heartbeat = root.appendingPathComponent(".daemon-alive")
        try Data("alive".utf8).write(to: heartbeat)
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: heartbeat.path
        )
        let manager = PrivilegedHelperManager(
            daemonService: StubAppService(status: .enabled),
            loginItemService: StubAppService(status: .notRegistered),
            daemonHeartbeatURL: heartbeat,
            now: { now },
            flavor: .production,
            liveEnforcementOwner: { nil }
        )
        manager.refreshStatus()
        for state in [
            PrivilegedHelperManager.ConnectionState.unavailable,
            .unauthorized,
            .stale,
            .registrationFailed
        ] {
            manager.seedConnectionStateForTesting(state)
            #expect(!manager.isRemoteLockEnforcementAvailable)
        }
        manager.seedConnectionStateForTesting(.ready)
        #expect(manager.isRemoteLockEnforcementAvailable)
    }
}
