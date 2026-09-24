import AppKit
@testable import Curfew
import Foundation
import Testing

struct AccountEnrollmentStorageRecoveryTests {
    @MainActor
    @Test("An unreadable saved enrollment cannot begin a replacement sign-in")
    func unreadableEnrollmentFailsClosed() async {
        let secrets = FailingReadEnrollmentSecretStore()
        let oauth = UnexpectedStorageRecoveryOAuthEnrollment()
        let controller = AccountEnrollmentController(secretStore: secrets, oauth: oauth)

        #expect(controller.state == .storageUnavailable)
        #expect(!AccountEnrollmentSignInPolicy.canStart(from: controller.state))
        await controller.signIn()
        #expect(oauth.signInCount == 0)
        controller.reloadSavedEnrollment()
        #expect(controller.state == .storageUnavailable)
        #expect(secrets.deletedAccounts.isEmpty)
    }

    @MainActor
    @Test(
        "Malformed saved enrollment cannot be mistaken for an empty account",
        arguments: [
            "pending-account-enrollment-ready",
            "pending-recovery-setup",
            "pending-account-enrollment"
        ]
    )
    func malformedEnrollmentFailsClosed(account: String) throws {
        let secrets = FailingReadEnrollmentSecretStore(failsReads: false)
        try secrets.save(Data("{".utf8), for: account)

        let controller = AccountEnrollmentController(secretStore: secrets)

        #expect(controller.state == .storageUnavailable)
        #expect(!AccountEnrollmentSignInPolicy.canStart(from: controller.state))
        #expect(secrets.deletedAccounts.isEmpty)
    }

    @MainActor
    @Test("A storage retry restores the exact unfinished Recovery Key step")
    func storageRetryRestoresPendingStep() throws {
        let secrets = FailingReadEnrollmentSecretStore()
        let enrollment = try AccountDeviceEnrollment(
            deviceID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")),
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try AccountEnrollmentPendingStore(secretStore: secrets).save(
            enrollment: enrollment,
            recoveryKey: "retained-recovery-key"
        )
        let controller = AccountEnrollmentController(secretStore: secrets)
        #expect(controller.state == .storageUnavailable)

        secrets.failsReads = false
        controller.reloadSavedEnrollment()

        #expect(controller.state == .saveRecoveryKey("retained-recovery-key", enrollment))
        #expect(secrets.deletedAccounts == [
            "pending-recovery-setup", "pending-account-authorized-connection"
        ])
    }

    @MainActor
    @Test("A storage retry with no checkpoint does not invent an enrollment")
    func storageRetryWithNoCheckpointReturnsAccountFree() {
        let secrets = FailingReadEnrollmentSecretStore()
        let controller = AccountEnrollmentController(secretStore: secrets)
        #expect(controller.state == .storageUnavailable)

        secrets.failsReads = false
        controller.reloadSavedEnrollment()

        #expect(controller.state == .accountFree)
        #expect(secrets.deletedAccounts.isEmpty)
    }
}

private final class FailingReadEnrollmentSecretStore: AccountSecretStoring {
    private enum Failure: Error { case unavailable }
    var failsReads: Bool
    private var values: [String: Data] = [:]
    private(set) var deletedAccounts: [String] = []

    init(failsReads: Bool = true) {
        self.failsReads = failsReads
    }

    func data(for account: String) throws -> Data? {
        if failsReads {
            throw Failure.unavailable
        }
        return values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        deletedAccounts.append(account)
        values.removeValue(forKey: account)
    }
}

@MainActor
private final class UnexpectedStorageRecoveryOAuthEnrollment: AccountOAuthEnrolling {
    private enum Failure: Error { case unexpected }
    private(set) var signInCount = 0

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        signInCount += 1
        throw Failure.unexpected
    }

    func cancelSignIn() {}
}
