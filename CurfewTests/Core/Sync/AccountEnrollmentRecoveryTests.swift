import AppKit
@testable import Curfew
import Foundation
import Testing

struct AccountEnrollmentRecoveryTests {
    @MainActor
    @Test("A signed-in user sees a device connection failure, never a sign-in failure")
    func deviceEnrollmentFailurePreservesSignInTruth() async {
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: SuccessfulAccountOAuthEnrollment(),
            devices: FailingAccountDeviceEnrollment()
        )

        await controller.signIn()

        #expect(controller.state == .failed(AccountEnrollmentFailureCopy.deviceConnection))
        #expect(AccountEnrollmentFailureCopy.deviceConnection.hasPrefix("You’re signed in."))
        #expect(!AccountEnrollmentFailureCopy.deviceConnection.contains("sign-in failed"))
    }

    @MainActor
    @Test("A completed browser ceremony never receives unfinished-browser copy")
    func postBrowserFailurePreservesBrowserSignInTruth() async {
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: PostBrowserFailingAccountOAuthEnrollment(),
            devices: FailingAccountDeviceEnrollment()
        )

        await controller.signIn()

        #expect(controller.state == .failed(AccountEnrollmentFailureCopy.browserCompleted))
        #expect(AccountEnrollmentFailureCopy.browserCompleted.hasPrefix("You’re signed in"))
        #expect(!AccountEnrollmentFailureCopy.browserCompleted.contains("Finish in the browser"))
    }

    @MainActor
    @Test("A registered Mac resumes recovery setup without another browser sign-in")
    func registeredMacResumesWithoutSigningInAgain() async {
        let oauth = CountingAccountOAuthEnrollment()
        let devices = ResumableAccountDeviceEnrollment()
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: oauth,
            devices: devices
        )

        await controller.signIn()
        #expect(controller.state == .finishRecoverySetup("recovery-key", devices.enrollment))

        await controller.finishRecoverySetup()

        #expect(controller.state == .saveRecoveryKey("recovery-key", devices.enrollment))
        #expect(oauth.signInCount == 1)
        #expect(devices.resumeCount == 1)
    }

    @MainActor
    @Test("Recovery retry failures remain retryable and explain that sign-in is complete")
    func recoveryRetryFailureStaysAtTheRecoveryStep() async {
        let devices = FailingRecoveryAccountDeviceEnrollment()
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: SuccessfulAccountOAuthEnrollment(),
            devices: devices
        )

        await controller.signIn()
        await controller.finishRecoverySetup()

        #expect(controller.state == .finishRecoverySetup("recovery-key", devices.enrollment))
        #expect(controller.enrollmentRetryError == AccountEnrollmentFailureCopy.retryConnection)
        #expect(!controller.isFinishingEnrollment)
    }

    @MainActor
    @Test("Recovery retries are single-flight")
    func recoveryRetryIsSingleFlight() async {
        let devices = SlowRecoveryAccountDeviceEnrollment()
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: SuccessfulAccountOAuthEnrollment(),
            devices: devices
        )

        await controller.signIn()
        async let first: Void = controller.finishRecoverySetup()
        await Task.yield()
        async let second: Void = controller.finishRecoverySetup()
        _ = await (first, second)

        #expect(devices.resumeCount == 1)
    }
}

@MainActor
private struct PostBrowserFailingAccountOAuthEnrollment: AccountOAuthEnrolling {
    func signIn(presentationWindow _: NSWindow?) async throws -> AccountOAuthGrant {
        throw AccountOAuthEnrollmentError.browserCompletedConnectionFailed
    }
}

private final class EnrollmentRecoveryMemorySecretStore: AccountSecretStoring {
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
private struct SuccessfulAccountOAuthEnrollment: AccountOAuthEnrolling {
    func signIn(presentationWindow _: NSWindow?) async throws -> AccountOAuthGrant {
        AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "access", refreshToken: "refresh"),
            state: "state",
            codeChallenge: "challenge"
        )
    }
}

@MainActor
private struct FailingAccountDeviceEnrollment: AccountDeviceEnrolling {
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
private final class CountingAccountOAuthEnrollment: AccountOAuthEnrolling {
    private(set) var signInCount = 0

    func signIn(presentationWindow _: NSWindow?) async throws -> AccountOAuthGrant {
        signInCount += 1
        return AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "access", refreshToken: "refresh"),
            state: "state",
            codeChallenge: "challenge"
        )
    }
}

@MainActor
private final class ResumableAccountDeviceEnrollment: AccountDeviceEnrolling {
    let enrollment = Curfew.AccountDeviceEnrollment(
        deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
        keyEpoch: 1,
        enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    private(set) var resumeCount = 0

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
}

@MainActor
private final class FailingRecoveryAccountDeviceEnrollment: AccountDeviceEnrolling {
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
private final class SlowRecoveryAccountDeviceEnrollment: AccountDeviceEnrolling {
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
