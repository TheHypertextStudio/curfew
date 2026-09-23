import AppKit
@testable import Curfew
import Foundation

@MainActor
final class SuspendedAccountOAuthEnrollment: AccountOAuthEnrolling {
    let authorizationURL = URL(
        string: "https://curfew-account-staging.hypertext.studio/api/auth/oauth2/authorize?state=test"
    )!
    private var continuation: CheckedContinuation<AccountOAuthGrant, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        authorizationURLHandler(authorizationURL)
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func fail() {
        continuation?.resume(throwing: AccountOAuthEnrollmentError.authorizationRejected)
        continuation = nil
    }

    func cancelSignIn() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

@MainActor
final class LinkedSuccessfulAccountOAuthEnrollment: AccountOAuthEnrolling {
    let authorizationURL = URL(
        string: "https://curfew-account-staging.hypertext.studio/api/auth/oauth2/authorize?state=test"
    )!
    private var linkWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasPublishedLink = false

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        authorizationURLHandler(authorizationURL)
        hasPublishedLink = true
        for waiter in linkWaiters {
            waiter.resume()
        }
        linkWaiters.removeAll()
        await Task.yield()
        return AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "access", refreshToken: "refresh"),
            state: "state",
            codeChallenge: "challenge"
        )
    }

    func waitUntilLinkPublished() async {
        if hasPublishedLink {
            return
        }
        await withCheckedContinuation { linkWaiters.append($0) }
    }

    func cancelSignIn() {}
}

@MainActor
final class MemoryAccountAuthorizationLinkClipboard: AccountAuthorizationLinkCopying {
    var contents: String?
    private var curfewValue: String?

    func copy(_ url: URL) {
        curfewValue = url.absoluteString
        contents = curfewValue
    }

    func clearIfUnchanged() {
        if contents == curfewValue {
            contents = nil
        }
        curfewValue = nil
    }
}

@MainActor
final class SuspendedAccountDeviceEnrollment: AccountDeviceEnrolling {
    private enum Failure: Error { case unavailable }
    private var continuation: CheckedContinuation<NativeAccountEnrollmentState, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func enroll(
        grant _: AccountOAuthGrant,
        deviceID _: UUID
    ) async throws -> NativeAccountEnrollmentState {
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func fail() {
        continuation?.resume(throwing: Failure.unavailable)
        continuation = nil
    }

    func restore(
        recoveryKey _: String,
        enrollment _: AccountDeviceEnrollment
    ) async throws -> AccountDeviceEnrollment {
        throw Failure.unavailable
    }

    func resumeRecoverySetup(
        recoveryKey _: String,
        enrollment _: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        throw Failure.unavailable
    }

    func resumeDeviceRegistration(
        recoveryKey _: String,
        enrollment _: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        throw Failure.unavailable
    }
}
