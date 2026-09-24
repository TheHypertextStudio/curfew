import AppKit
@testable import Curfew
import Foundation

@MainActor
struct PostBrowserFailingAccountOAuthEnrollment: AccountOAuthEnrolling {
    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        throw AccountOAuthEnrollmentError.browserCompletedConnectionFailed
    }

    func cancelSignIn() {}
}

final class EnrollmentRecoveryMemorySecretStore: AccountSecretStoring {
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        values.removeValue(forKey: account)
    }
}

@MainActor
struct SuccessfulAccountOAuthEnrollment: AccountOAuthEnrolling {
    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "access", refreshToken: "refresh"),
            state: "state",
            codeChallenge: "challenge"
        )
    }

    func cancelSignIn() {}
}

@MainActor
struct FailingAccountDeviceEnrollment: AccountDeviceEnrolling {
    private enum Failure: Error { case unavailable }

    func enroll(
        grant _: AccountOAuthGrant,
        deviceID _: UUID
    ) async throws -> NativeAccountEnrollmentState {
        throw Failure.unavailable
    }

    func restore(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> Curfew.AccountDeviceEnrollment {
        throw Failure.unavailable
    }

    func resumeRecoverySetup(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        throw Failure.unavailable
    }

    func resumeDeviceRegistration(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        throw Failure.unavailable
    }
}

@MainActor
final class CountingAccountOAuthEnrollment: AccountOAuthEnrolling {
    private(set) var signInCount = 0
    private let secretStore: (any AccountSecretStoring)?

    init(secretStore: (any AccountSecretStoring)? = nil) {
        self.secretStore = secretStore
    }

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        signInCount += 1
        try secretStore?.save(Data("refresh".utf8), for: "oauth-refresh-token")
        try secretStore?.save(Data("access".utf8), for: "oauth-access-token")
        return AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "access", refreshToken: "refresh"),
            state: "state",
            codeChallenge: "challenge"
        )
    }

    func cancelSignIn() {}
}

@MainActor
final class ResumableAccountDeviceEnrollment: AccountDeviceEnrolling {
    let enrollment = Curfew.AccountDeviceEnrollment(
        deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
        keyEpoch: 1,
        enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    private(set) var resumeCount = 0
    private(set) var acknowledgeCount = 0

    func enroll(
        grant _: AccountOAuthGrant,
        deviceID _: UUID
    ) async throws -> NativeAccountEnrollmentState {
        .finishRecoverySetup("recovery-key", enrollment)
    }

    func restore(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> Curfew.AccountDeviceEnrollment {
        enrollment
    }

    func resumeRecoverySetup(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        resumeCount += 1
        return .saveRecoveryKey("recovery-key", enrollment)
    }

    func resumeDeviceRegistration(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        .finishRecoverySetup("recovery-key", enrollment)
    }

    func acknowledgeSavedRecoveryKey(
        recoveryKey _: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        acknowledgeCount += 1
        return .ready(enrollment)
    }
}

@MainActor
final class FailingRecoveryAccountDeviceEnrollment: AccountDeviceEnrolling {
    private enum Failure: Error { case unavailable }
    let enrollment = Curfew.AccountDeviceEnrollment(
        deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
        keyEpoch: 1,
        enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    func enroll(grant _: AccountOAuthGrant, deviceID _: UUID) async throws
        -> NativeAccountEnrollmentState {
        .finishRecoverySetup("recovery-key", enrollment)
    }

    func resumeRecoverySetup(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        throw Failure.unavailable
    }

    func resumeDeviceRegistration(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        throw Failure.unavailable
    }

    func restore(recoveryKey _: String, enrollment _: AccountDeviceEnrollment) async throws
        -> AccountDeviceEnrollment {
        throw Failure.unavailable
    }
}

@MainActor
final class SlowRecoveryAccountDeviceEnrollment: AccountDeviceEnrolling {
    let enrollment = Curfew.AccountDeviceEnrollment(
        deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
        keyEpoch: 1,
        enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    private(set) var resumeCount = 0

    func enroll(grant _: AccountOAuthGrant, deviceID _: UUID) async throws
        -> NativeAccountEnrollmentState {
        .finishRecoverySetup("recovery-key", enrollment)
    }

    func resumeRecoverySetup(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        resumeCount += 1
        try await Task.sleep(for: .milliseconds(50))
        return .saveRecoveryKey("recovery-key", enrollment)
    }

    func resumeDeviceRegistration(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        .finishRecoverySetup("recovery-key", enrollment)
    }

    func restore(recoveryKey _: String, enrollment _: AccountDeviceEnrollment) async throws
        -> AccountDeviceEnrollment {
        enrollment
    }
}

@MainActor
final class RecoveryKeyAttemptDeviceEnrollment: AccountDeviceEnrolling {
    private enum Failure: Error { case wrongKey }

    let enrollment = Curfew.AccountDeviceEnrollment(
        deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
        keyEpoch: 1,
        enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    private(set) var restoreCount = 0

    func enroll(grant _: AccountOAuthGrant, deviceID _: UUID) async throws
        -> NativeAccountEnrollmentState {
        .enterRecoveryKey(enrollment)
    }

    func resumeRecoverySetup(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        .enterRecoveryKey(enrollment)
    }

    func resumeDeviceRegistration(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        .enterRecoveryKey(enrollment)
    }

    func restore(recoveryKey: String, enrollment: AccountDeviceEnrollment) async throws
        -> AccountDeviceEnrollment {
        restoreCount += 1
        guard recoveryKey == "correct-key" else { throw Failure.wrongKey }
        return enrollment
    }
}

@MainActor
final class RetryableInitialAccountDeviceEnrollment: AccountDeviceEnrolling {
    private enum Failure: Error { case unavailable }

    let enrollment = Curfew.AccountDeviceEnrollment(
        deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
        keyEpoch: 1,
        enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    private(set) var enrollCount = 0

    func enroll(grant _: AccountOAuthGrant, deviceID _: UUID) async throws
        -> NativeAccountEnrollmentState {
        enrollCount += 1
        guard enrollCount > 1 else { throw Failure.unavailable }
        return .saveRecoveryKey("recovery-key", enrollment)
    }

    func resumeRecoverySetup(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        .saveRecoveryKey("recovery-key", enrollment)
    }

    func resumeDeviceRegistration(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        .saveRecoveryKey("recovery-key", enrollment)
    }

    func restore(recoveryKey _: String, enrollment: AccountDeviceEnrollment) async throws
        -> AccountDeviceEnrollment {
        enrollment
    }
}

@MainActor
final class RejectedInitialAccountDeviceEnrollment: AccountDeviceEnrolling {
    private enum Failure: Error { case unavailable }

    let enrollment = Curfew.AccountDeviceEnrollment(
        deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
        keyEpoch: 1,
        enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    private var enrollCount = 0

    func enroll(grant _: AccountOAuthGrant, deviceID _: UUID) async throws
        -> NativeAccountEnrollmentState {
        enrollCount += 1
        switch enrollCount {
        case 1: throw Failure.unavailable
        case 2: throw AccountOAuthTokenRefreshError.rejected(400)
        default: return .saveRecoveryKey("recovery-key", enrollment)
        }
    }

    func resumeRecoverySetup(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        .saveRecoveryKey("recovery-key", enrollment)
    }

    func resumeDeviceRegistration(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        .saveRecoveryKey("recovery-key", enrollment)
    }

    func restore(recoveryKey _: String, enrollment: AccountDeviceEnrollment) async throws
        -> AccountDeviceEnrollment {
        enrollment
    }
}
