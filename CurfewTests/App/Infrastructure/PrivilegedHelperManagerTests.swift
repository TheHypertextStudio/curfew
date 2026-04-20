@testable import Curfew
import Foundation
import ServiceManagement
import Testing

@MainActor
struct PrivilegedHelperManagerTests {
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

    var errorDescription: String? {
        switch self {
        case .registerFailed:
            "The service failed to register."
        }
    }
}
