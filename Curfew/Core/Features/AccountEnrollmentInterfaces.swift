import AppKit
import Foundation

enum AccountEnrollmentUIState: Equatable {
    case accountFree
    case storageUnavailable
    case signingIn
    case connectingDevice
    case finishDeviceConnection
    case finishDeviceRegistration(String, AccountDeviceEnrollment)
    case finishRecoverySetup(String, AccountDeviceEnrollment)
    case saveRecoveryKey(String, AccountDeviceEnrollment)
    case enterRecoveryKey(AccountDeviceEnrollment)
    case ready(AccountDeviceEnrollment)
    case failed(String)
}

enum AccountEnrollmentSignInPolicy {
    static func canStart(from state: AccountEnrollmentUIState) -> Bool {
        switch state {
        case .storageUnavailable, .signingIn, .connectingDevice, .finishDeviceConnection,
             .finishDeviceRegistration, .finishRecoverySetup, .saveRecoveryKey, .enterRecoveryKey:
            false
        default:
            true
        }
    }
}

@MainActor
protocol AccountOAuthEnrolling {
    func signIn(
        presentationWindow: NSWindow?,
        authorizationURLHandler: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant
    func reauthorize(
        expectedAccountUserID: String,
        presentationWindow: NSWindow?,
        authorizationURLHandler: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant
    func cancelSignIn()
}

extension AccountOAuthEnrolling {
    func reauthorize(
        expectedAccountUserID _: String,
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        throw AccountOAuthEnrollmentError.invalidResponse
    }
}

@MainActor
protocol AccountDeviceEnrolling {
    func enroll(
        grant: AccountOAuthGrant,
        deviceID: UUID
    ) async throws -> NativeAccountEnrollmentState
    func resumeRecoverySetup(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState
    func resumeDeviceRegistration(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState
    func restore(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> AccountDeviceEnrollment
    func acknowledgeSavedRecoveryKey(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState
}

extension AccountDeviceEnrolling {
    func acknowledgeSavedRecoveryKey(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        try await resumeRecoverySetup(recoveryKey: recoveryKey, enrollment: enrollment)
    }
}

extension AccountOAuthEnrollmentService: AccountOAuthEnrolling {}

extension NativeAccountDeviceEnrollmentService: AccountDeviceEnrolling {
    func enroll(
        grant: AccountOAuthGrant,
        deviceID: UUID
    ) async throws -> NativeAccountEnrollmentState {
        try await enroll(grant: grant, deviceID: deviceID, enrolledAt: Date())
    }
}

@MainActor
protocol AccountAuthorizationLinkCopying: AnyObject {
    func copy(_ url: URL)
    func clearIfUnchanged()
}

@MainActor
final class SystemAccountAuthorizationLinkClipboard: AccountAuthorizationLinkCopying {
    private var copiedValue: String?

    func copy(_ url: URL) {
        let value = url.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedValue = value
    }

    func clearIfUnchanged() {
        defer { copiedValue = nil }
        guard let copiedValue,
              NSPasteboard.general.string(forType: .string) == copiedValue
        else { return }
        NSPasteboard.general.clearContents()
    }
}
