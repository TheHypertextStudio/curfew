import AppKit
@testable import Curfew
import CurfewProtocols
import Foundation
import Testing

@MainActor
struct AccountEnrollmentReauthorizationTests {
    @Test("A saved registration cannot be replaced by starting ordinary enrollment")
    func savedRegistrationRejectsFreshEnrollment() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices
        )

        await controller.signIn()

        #expect(controller.state == .finishDeviceRegistration("recovery-key", fixture.enrollment))
        #expect(devices.enrollCount == 0)
        #expect(oauth.reauthorizeCount == 0)
    }

    @Test("A rejected refresh resumes the saved Mac after same-account sign-in")
    func sameAccountResumesSavedRegistration() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(
            enrollment: fixture.enrollment,
            pending: fixture.pending
        )
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices
        )

        await controller.finishDeviceRegistration()
        #expect(controller.requiresReauthorization)
        await controller.reauthorizeSavedEnrollment()

        #expect(controller.state == .saveRecoveryKey("recovery-key", fixture.enrollment))
        #expect(devices.resumeCount == 2)
        #expect(devices.enrollCount == 0)
        #expect(oauth.reauthorizeCount == 1)
        #expect(oauth.expectedAccountUserID == "original-account")
    }

    @Test("A different account cannot replace a pending Mac's credentials or checkpoint")
    func differentAccountCannotTakeOverSavedRegistration() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        oauth.rejectAsDifferentAccount = true
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices
        )

        await controller.finishDeviceRegistration()
        await controller.reauthorizeSavedEnrollment()

        #expect(controller.state == .finishDeviceRegistration("recovery-key", fixture.enrollment))
        #expect(controller.requiresReauthorization)
        #expect(devices.resumeCount == 1)
        #expect(try fixture.secrets.data(for: "oauth-refresh-token") == Data("old-refresh".utf8))
        #expect(try fixture.pending.loadRecoverySetup()?.accountUserID == "original-account")
    }

    @Test("An unanchored legacy checkpoint never authorizes another account")
    func legacyCheckpointFailsClosed() async throws {
        let fixture = try makeFixture(accountUserID: nil)
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices
        )

        await controller.finishDeviceRegistration()
        await controller.reauthorizeSavedEnrollment()

        #expect(controller.state == .finishDeviceRegistration("recovery-key", fixture.enrollment))
        #expect(oauth.reauthorizeCount == 0)
        #expect(devices.resumeCount == 1)
        #expect(controller.enrollmentRetryError?.contains("account") == true)
    }

    @Test("A registered Mac uses its receipt to reauthorize recovery setup")
    func registeredMacResumesRecoveryWithSameAccount() async throws {
        let fixture = try makeFixture(accountUserID: nil)
        try fixture.pending.saveRegistrationReceipt(NativeDeviceEnrollmentReceipt(
            deviceID: fixture.enrollment.deviceID.uuidString.lowercased(),
            enrolledAt: "2027-01-15T08:00:00.000Z",
            protocolVersion: "0.0",
            userID: "original-account"
        ).jsonData())
        try fixture.pending.markRecoveryKeySaved()
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices
        )

        await controller.finishRecoverySetup()
        #expect(controller.requiresReauthorization)
        await controller.reauthorizeSavedEnrollment()

        #expect(controller.state == .ready(fixture.enrollment))
        #expect(devices.recoveryResumeCount == 2)
        #expect(oauth.expectedAccountUserID == "original-account")
        #expect(devices.enrollCount == 0)
    }

    @Test("A rejected refresh after saving the Recovery Key offers same-account sign-in")
    func confirmationCanReauthorize() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        try fixture.pending.saveRegistrationReceipt(NativeDeviceEnrollmentReceipt(
            deviceID: fixture.enrollment.deviceID.uuidString.lowercased(),
            enrolledAt: "2027-01-15T08:00:00.000Z",
            protocolVersion: "0.0",
            userID: "original-account"
        ).jsonData())
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: ReauthorizationOAuthFixture(secretStore: fixture.secrets),
            devices: ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        )

        _ = await controller.acknowledgeSavedRecoveryKey()

        #expect(controller.state == .finishRecoverySetup("recovery-key", fixture.enrollment))
        #expect(controller.requiresReauthorization)
    }

    @Test("Existing Recovery Key restoration can sign in again with the owning account")
    func existingKeyRestorationCanReauthorize() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        try fixture.pending.saveRegistrationReceipt(NativeDeviceEnrollmentReceipt(
            deviceID: fixture.enrollment.deviceID.uuidString.lowercased(),
            enrolledAt: "2027-01-15T08:00:00.000Z",
            protocolVersion: "0.0",
            userID: "original-account"
        ).jsonData())
        let checkpoint = try #require(try fixture.pending.loadRecoverySetup())
        try fixture.pending.saveExistingKeyRecovery(from: checkpoint)
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices
        )

        await controller.restore(recoveryKey: "correct-existing-key")
        #expect(controller.state == .enterRecoveryKey(fixture.enrollment))
        #expect(controller.requiresReauthorization)

        await controller.reauthorizeSavedEnrollment()
        #expect(controller.state == .enterRecoveryKey(fixture.enrollment))
        #expect(!controller.requiresReauthorization)
        #expect(oauth.expectedAccountUserID == "original-account")

        await controller.restore(recoveryKey: "correct-existing-key")
        #expect(controller.state == .ready(fixture.enrollment))
        #expect(devices.restoreCount == 2)
    }

    private func makeFixture(accountUserID: String?) throws -> ReauthorizationFixture {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        try secrets.save(Data("old-access".utf8), for: "oauth-access-token")
        try secrets.save(Data("old-refresh".utf8), for: "oauth-refresh-token")
        let pending = AccountEnrollmentPendingStore(secretStore: secrets)
        let enrollment = Curfew.AccountDeviceEnrollment(
            deviceID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!,
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try pending.saveDeviceRegistration(
            enrollment: enrollment,
            recoveryKey: "recovery-key",
            recoveryEnvelope: RecoveryKeyEnvelope(
                aead: .aes256Gcm,
                ciphertext: String(repeating: "A", count: 64),
                createdAt: "2026-08-10T14:00:00.000Z",
                info: .curfewRecoveryWrapV2,
                kdf: .hkdfSha256,
                keyEpoch: 1,
                nonce: String(repeating: "B", count: 16),
                salt: String(repeating: "C", count: 22)
            ),
            oauthState: "old-state",
            pkceChallenge: "old-challenge",
            accountUserID: accountUserID
        )
        return ReauthorizationFixture(
            secrets: secrets,
            pending: pending,
            enrollment: enrollment
        )
    }
}

private struct ReauthorizationFixture {
    let secrets: EnrollmentRecoveryMemorySecretStore
    let pending: AccountEnrollmentPendingStore
    let enrollment: Curfew.AccountDeviceEnrollment
}

@MainActor
private final class ReauthorizationOAuthFixture: AccountOAuthEnrolling {
    var rejectAsDifferentAccount = false
    private(set) var reauthorizeCount = 0
    private(set) var expectedAccountUserID: String?
    private let secretStore: any AccountSecretStoring

    init(secretStore: any AccountSecretStoring) {
        self.secretStore = secretStore
    }

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        Issue.record("A saved Mac must not start a new device enrollment")
        throw AccountOAuthEnrollmentError.invalidResponse
    }

    func reauthorize(
        expectedAccountUserID: String,
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        reauthorizeCount += 1
        self.expectedAccountUserID = expectedAccountUserID
        if rejectAsDifferentAccount {
            throw AccountOAuthEnrollmentError.accountMismatch
        }
        try secretStore.save(Data("new-refresh".utf8), for: "oauth-refresh-token")
        try secretStore.save(Data("new-access".utf8), for: "oauth-access-token")
        return AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "new-access", refreshToken: "new-refresh"),
            state: "new-state",
            codeChallenge: "new-challenge",
            subjectID: expectedAccountUserID
        )
    }

    func cancelSignIn() {}
}

@MainActor
private final class ReauthorizationDeviceFixture: AccountDeviceEnrolling {
    let enrollment: Curfew.AccountDeviceEnrollment
    let pending: AccountEnrollmentPendingStore?
    private(set) var resumeCount = 0
    private(set) var recoveryResumeCount = 0
    private(set) var restoreCount = 0
    private(set) var enrollCount = 0

    init(
        enrollment: Curfew.AccountDeviceEnrollment,
        pending: AccountEnrollmentPendingStore? = nil
    ) {
        self.enrollment = enrollment
        self.pending = pending
    }

    func enroll(grant _: AccountOAuthGrant, deviceID _: UUID) async throws
        -> NativeAccountEnrollmentState {
        enrollCount += 1
        throw AccountOAuthEnrollmentError.invalidResponse
    }

    func resumeDeviceRegistration(recoveryKey: String, enrollment: Curfew.AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        resumeCount += 1
        guard recoveryKey == "recovery-key", enrollment == self.enrollment else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        if resumeCount == 1 {
            throw AccountOAuthTokenRefreshError.rejected(400)
        }
        try pending?.saveRegistrationReceipt(NativeDeviceEnrollmentReceipt(
            deviceID: enrollment.deviceID.uuidString.lowercased(),
            enrolledAt: "2027-01-15T08:00:00.000Z",
            protocolVersion: "0.0",
            userID: "original-account"
        ).jsonData())
        return .saveRecoveryKey(recoveryKey, enrollment)
    }

    func resumeRecoverySetup(recoveryKey _: String, enrollment: Curfew.AccountDeviceEnrollment)
        async throws -> NativeAccountEnrollmentState {
        recoveryResumeCount += 1
        if recoveryResumeCount == 1 {
            throw AccountOAuthTokenRefreshError.rejected(400)
        }
        return .ready(enrollment)
    }

    func restore(recoveryKey _: String, enrollment _: Curfew.AccountDeviceEnrollment) async throws
        -> Curfew.AccountDeviceEnrollment {
        restoreCount += 1
        if restoreCount == 1 {
            throw AccountOAuthTokenRefreshError.rejected(400)
        }
        return enrollment
    }
}
