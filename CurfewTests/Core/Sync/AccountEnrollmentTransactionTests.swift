import AppKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct AccountEnrollmentTransactionTests {
    @MainActor
    @Test("A second enrollment cannot start while another is in progress")
    func simultaneousEnrollmentsDoNotOverwriteEachOther() async {
        let suspended = SuspendedAccountOAuthEnrollment()
        let first = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: suspended,
            devices: FailingAccountDeviceEnrollment()
        )
        let secondSecrets = EnrollmentRecoveryMemorySecretStore()
        let second = AccountEnrollmentController(
            secretStore: secondSecrets,
            oauth: CountingAccountOAuthEnrollment(secretStore: secondSecrets),
            devices: FailingAccountDeviceEnrollment()
        )
        let firstAttempt = Task { await first.signIn() }
        await suspended.waitUntilStarted()

        await second.signIn()

        guard case .failed = second.state else {
            suspended.fail()
            await firstAttempt.value
            Issue.record("The second enrollment must stop before writing credentials")
            return
        }
        suspended.fail()
        await firstAttempt.value
    }
}
