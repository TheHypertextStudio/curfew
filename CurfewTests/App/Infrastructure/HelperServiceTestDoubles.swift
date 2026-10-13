@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement

final class StubDaemonRPC: PrivilegedDaemonRPCControlling, @unchecked Sendable {
    private(set) var armCallCount = 0
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

    func armLockout(_: LockoutDeadlineRecord) async throws {
        armCallCount += 1
    }

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

final class StubAppService: AppServiceControlling {
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

enum StubServiceError: LocalizedError {
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
