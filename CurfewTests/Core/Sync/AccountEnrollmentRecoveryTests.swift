import AppKit
@testable import Curfew
import Foundation
import Testing

struct AccountEnrollmentRecoveryTests {
    @MainActor
    @Test("A signed-in user sees a device connection failure, never a sign-in failure")
    func deviceEnrollmentFailurePreservesSignInTruth() async {
        let secretStore = EnrollmentRecoveryMemorySecretStore()
        let controller = AccountEnrollmentController(
            secretStore: secretStore,
            oauth: CountingAccountOAuthEnrollment(secretStore: secretStore),
            devices: FailingAccountDeviceEnrollment()
        )

        await controller.signIn()

        #expect(controller.state == .finishDeviceConnection)
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
    @Test("A live browser sign-in link remains available while authorization is waiting")
    func browserSignInLinkCanMoveToThePasskeyProfile() async {
        let oauth = SuspendedAccountOAuthEnrollment()
        let clipboard = MemoryAccountAuthorizationLinkClipboard()
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: oauth,
            devices: FailingAccountDeviceEnrollment(),
            authorizationLinkClipboard: clipboard
        )

        let signIn = Task { await controller.signIn() }
        await oauth.waitUntilStarted()

        #expect(controller.browserSignInURL == oauth.authorizationURL)
        #expect(controller.copyBrowserSignInLink())
        #expect(clipboard.contents == oauth.authorizationURL.absoluteString)

        oauth.fail()
        await signIn.value
        #expect(controller.browserSignInURL == nil)
        #expect(clipboard.contents == nil)
    }

    @MainActor
    @Test("Finishing sign-in never erases something the user copied afterward")
    func browserSignInLinkCleanupPreservesNewClipboardContents() async {
        let oauth = SuspendedAccountOAuthEnrollment()
        let clipboard = MemoryAccountAuthorizationLinkClipboard()
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: oauth,
            devices: FailingAccountDeviceEnrollment(),
            authorizationLinkClipboard: clipboard
        )

        let signIn = Task { await controller.signIn() }
        await oauth.waitUntilStarted()
        #expect(controller.copyBrowserSignInLink())
        clipboard.contents = "new clipboard contents"

        oauth.fail()
        await signIn.value

        #expect(clipboard.contents == "new clipboard contents")
    }

    @MainActor
    @Test("A consumed sign-in link disappears before device enrollment finishes")
    func browserSignInLinkClearsBeforeDeviceEnrollment() async {
        let oauth = LinkedSuccessfulAccountOAuthEnrollment()
        let devices = SuspendedAccountDeviceEnrollment()
        let clipboard = MemoryAccountAuthorizationLinkClipboard()
        let controller = AccountEnrollmentController(
            secretStore: EnrollmentRecoveryMemorySecretStore(),
            oauth: oauth,
            devices: devices,
            authorizationLinkClipboard: clipboard
        )

        let signIn = Task { await controller.signIn() }
        await oauth.waitUntilLinkPublished()
        #expect(controller.copyBrowserSignInLink())
        await devices.waitUntilStarted()

        #expect(controller.state == .connectingDevice)
        #expect(controller.browserSignInURL == nil)
        #expect(clipboard.contents == nil)

        devices.fail()
        await signIn.value
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
        let completed = await controller.acknowledgeSavedRecoveryKey()
        #expect(completed == devices.enrollment)
        #expect(controller.state == .ready(devices.enrollment))
        #expect(oauth.signInCount == 1)
        #expect(devices.resumeCount == 1)
        #expect(devices.acknowledgeCount == 1)
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

    @MainActor
    @Test("A wrong Recovery Key keeps the same enrolled Mac ready for another key")
    func wrongRecoveryKeyDoesNotRestartSignIn() async throws {
        let secretStore = EnrollmentRecoveryMemorySecretStore()
        let devices = RecoveryKeyAttemptDeviceEnrollment()
        try AccountEnrollmentPendingStore(secretStore: secretStore).save(
            enrollment: devices.enrollment,
            recoveryKey: nil
        )
        let oauth = CountingAccountOAuthEnrollment()
        let controller = AccountEnrollmentController(
            secretStore: secretStore,
            oauth: oauth,
            devices: devices
        )

        await controller.restore(recoveryKey: "wrong-key")
        #expect(controller.state == .enterRecoveryKey(devices.enrollment))
        #expect(controller.enrollmentRetryError != nil)

        await controller.restore(recoveryKey: "correct-key")
        #expect(controller.state == .ready(devices.enrollment))
        #expect(oauth.signInCount == 0)
        #expect(devices.restoreCount == 2)
    }

    @MainActor
    @Test(
        "A connection failure before registration survives relaunch without another OAuth sign-in"
    )
    func initialDeviceConnectionCanResumeAfterRelaunch() async {
        let secretStore = EnrollmentRecoveryMemorySecretStore()
        let oauth = CountingAccountOAuthEnrollment(secretStore: secretStore)
        let devices = RetryableInitialAccountDeviceEnrollment()
        let first = AccountEnrollmentController(
            secretStore: secretStore,
            oauth: oauth,
            devices: devices
        )

        await first.signIn()
        let relaunched = AccountEnrollmentController(
            secretStore: secretStore,
            oauth: oauth,
            devices: devices
        )
        #expect(relaunched.state != .accountFree)

        await relaunched.signIn()
        #expect(relaunched.state == .saveRecoveryKey("recovery-key", devices.enrollment))
        #expect(oauth.signInCount == 1)
        #expect(devices.enrollCount == 2)
    }
}
