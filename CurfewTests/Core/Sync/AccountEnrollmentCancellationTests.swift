import AppKit
@testable import Curfew
import Foundation
import Testing

struct AccountEnrollmentCancellationTests {
    @MainActor
    @Test("A missed browser callback can be cancelled and sign-in started again")
    func missedBrowserCallbackCanBeRetriedWithoutRelaunch() async {
        let oauth = SuspendedAccountOAuthEnrollment()
        let controller = AccountEnrollmentController(
            secretStore: CancellationMemorySecretStore(),
            oauth: oauth
        )

        let firstSignIn = Task { await controller.signIn() }
        await oauth.waitUntilStarted()
        #expect(controller.state == .signingIn)

        controller.cancelSignIn()
        await firstSignIn.value
        #expect(controller.state == .accountFree)
        #expect(controller.browserSignInURL == nil)

        let secondSignIn = Task { await controller.signIn() }
        await oauth.waitUntilStarted()
        #expect(controller.state == .signingIn)
        oauth.fail()
        await secondSignIn.value
    }

    @MainActor
    @Test("Cancelling while token exchange waits frees the sign-in state promptly")
    func stalledTokenExchangeCanBeCancelled() async {
        let oauth = StalledTokenExchangeOAuthEnrollment()
        let controller = AccountEnrollmentController(
            secretStore: CancellationMemorySecretStore(),
            oauth: oauth
        )

        let signIn = Task { await controller.signIn() }
        await oauth.waitUntilStarted()
        controller.cancelSignIn()
        await signIn.value

        #expect(controller.state == .accountFree)
        #expect(AccountEnrollmentSignInPolicy.canStart(from: controller.state))
    }

    @MainActor
    @Test("Cancel after OAuth completion still prevents device enrollment")
    func cancelAfterOAuthCompletionPreventsDeviceEnrollment() async throws {
        let secrets = CancellationMemorySecretStore()
        let oauth = CompletingAccountOAuthEnrollment(secretStore: secrets)
        let devices = CancelledEnrollmentRecorder()
        let controller = AccountEnrollmentController(
            secretStore: secrets,
            oauth: oauth,
            devices: devices
        )

        let signIn = Task { await controller.signIn() }
        await oauth.waitUntilStarted()
        try oauth.complete()
        controller.cancelSignIn()
        await signIn.value

        #expect(controller.state == .accountFree)
        #expect(devices.enrollCount == 0)
        #expect(try secrets.data(for: "oauth-access-token") == nil)
        #expect(try secrets.data(for: "oauth-refresh-token") == nil)
    }
}

@MainActor
private final class CompletingAccountOAuthEnrollment: AccountOAuthEnrolling {
    private let secretStore: any AccountSecretStoring
    private var continuation: CheckedContinuation<AccountOAuthGrant, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(secretStore: any AccountSecretStoring) {
        self.secretStore = secretStore
    }

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters {
                waiter.resume()
            }
            startWaiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func complete() throws {
        let grant = AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "access", refreshToken: "refresh"),
            state: "state",
            codeChallenge: "challenge"
        )
        try secretStore.save(Data(grant.tokens.refreshToken.utf8), for: "oauth-refresh-token")
        try secretStore.save(Data(grant.tokens.accessToken.utf8), for: "oauth-access-token")
        continuation?.resume(returning: grant)
        continuation = nil
    }

    func cancelSignIn() {}
}

@MainActor
private final class CancelledEnrollmentRecorder: AccountDeviceEnrolling {
    private enum Failure: Error { case unexpected }
    private(set) var enrollCount = 0

    func enroll(
        grant _: AccountOAuthGrant,
        deviceID _: UUID
    ) async throws -> NativeAccountEnrollmentState {
        enrollCount += 1
        throw Failure.unexpected
    }

    func restore(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> Curfew.AccountDeviceEnrollment {
        throw Failure.unexpected
    }

    func resumeRecoverySetup(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        throw Failure.unexpected
    }

    func resumeDeviceRegistration(
        recoveryKey _: String,
        enrollment _: Curfew.AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        throw Failure.unexpected
    }
}

@MainActor
private final class StalledTokenExchangeOAuthEnrollment: AccountOAuthEnrolling {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        started = true
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()
        try await Task.sleep(for: .milliseconds(500))
        throw AccountOAuthEnrollmentError.browserCompletedConnectionFailed
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func cancelSignIn() {}
}

private final class CancellationMemorySecretStore: AccountSecretStoring {
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
