import AppKit
import Combine
import CurfewProtocols
import Foundation

enum AccountEnrollmentUIState: Equatable {
    case accountFree
    case storageUnavailable
    case signingIn
    case connectingDevice
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
        case .storageUnavailable, .signingIn, .connectingDevice:
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
    func cancelSignIn()
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

enum AccountEnrollmentFailureCopy {
    static let authorization =
        "Curfew didn’t connect this Mac. Finish in the browser, then try again. "
            + "Remote control is still off."
    static let deviceConnection =
        "You’re signed in. Curfew couldn’t connect this Mac, so remote control is still off. "
            + "Try again."
    static let browserCompleted =
        "You’re signed in in the browser. Curfew couldn’t finish connecting this Mac. "
            + "Your browser session is still active; try again."
    static let retryConnection =
        "Curfew still couldn’t finish connecting this Mac. No new sign-in is needed; try again."
}

@MainActor
final class AccountEnrollmentController: ObservableObject {
    @Published private(set) var state: AccountEnrollmentUIState = .accountFree
    @Published private(set) var isFinishingEnrollment = false
    @Published private(set) var enrollmentRetryError: String?
    @Published private(set) var browserSignInURL: URL?

    private let secretStore: any AccountSecretStoring
    private let oauth: any AccountOAuthEnrolling
    private let devices: any AccountDeviceEnrolling
    private let pending: AccountEnrollmentPendingStore
    private let authorizationLinkClipboard: any AccountAuthorizationLinkCopying
    private var activeSignInTask: Task<AccountOAuthGrant, any Error>?
    private var signInCancellationRequested = false
    weak var presentationWindow: NSWindow?

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        oauth: (any AccountOAuthEnrolling)? = nil,
        devices: (any AccountDeviceEnrolling)? = nil,
        authorizationLinkClipboard: (any AccountAuthorizationLinkCopying)? = nil
    ) {
        self.secretStore = secretStore
        self.oauth = oauth ?? AccountOAuthEnrollmentService(secretStore: secretStore)
        self.devices = devices ?? NativeAccountDeviceEnrollmentService(secretStore: secretStore)
        self.pending = AccountEnrollmentPendingStore(secretStore: secretStore)
        self.authorizationLinkClipboard = authorizationLinkClipboard
            ?? SystemAccountAuthorizationLinkClipboard()
        reloadSavedEnrollment()
    }

    func reloadSavedEnrollment() {
        do {
            state = try pending.load() ?? .accountFree
        } catch {
            state = .storageUnavailable
        }
    }

    func signIn() async {
        guard AccountEnrollmentSignInPolicy.canStart(from: state) else { return }
        signInCancellationRequested = false
        state = .signingIn
        browserSignInURL = nil
        let grant: AccountOAuthGrant
        do {
            grant = try await authenticate()
        } catch AccountOAuthEnrollmentError.browserCompletedConnectionFailed {
            state = .failed(AccountEnrollmentFailureCopy.browserCompleted)
            return
        } catch is CancellationError {
            state = .accountFree
            return
        } catch {
            state = .failed(AccountEnrollmentFailureCopy.authorization)
            return
        }
        state = .connectingDevice
        do {
            let outcome = try await devices.enroll(
                grant: grant,
                deviceID: deviceID()
            )
            switch outcome {
            case .finishDeviceRegistration(let key, let enrollment):
                state = .finishDeviceRegistration(key, enrollment)
            case .finishRecoverySetup(let key, let enrollment):
                state = .finishRecoverySetup(key, enrollment)
            case .saveRecoveryKey(let key, let enrollment):
                try pending.save(enrollment: enrollment, recoveryKey: key)
                state = .saveRecoveryKey(key, enrollment)
            case .enterRecoveryKey(let enrollment):
                try pending.save(enrollment: enrollment, recoveryKey: nil)
                state = .enterRecoveryKey(enrollment)
            case .ready(let enrollment):
                state = .ready(enrollment)
            }
        } catch {
            state = .failed(AccountEnrollmentFailureCopy.deviceConnection)
        }
    }

    private func authenticate() async throws -> AccountOAuthGrant {
        let authorizationURLHandler: @MainActor (URL) -> Void = { [weak self] authorizationURL in
            self?.browserSignInURL = authorizationURL
        }
        let authentication = Task {
            try await oauth.signIn(
                presentationWindow: presentationWindow,
                authorizationURLHandler: authorizationURLHandler
            )
        }
        activeSignInTask = authentication
        defer {
            activeSignInTask = nil
            browserSignInURL = nil
            authorizationLinkClipboard.clearIfUnchanged()
        }
        let grant = try await authentication.value
        if signInCancellationRequested {
            try discardCancelledGrant(grant)
            throw CancellationError()
        }
        return grant
    }

    private func discardCancelledGrant(_ grant: AccountOAuthGrant) throws {
        guard try secretStore
            .data(for: "oauth-access-token") == Data(grant.tokens.accessToken.utf8),
            try secretStore.data(for: "oauth-refresh-token") == Data(grant.tokens.refreshToken.utf8)
        else { return }
        try secretStore.delete("oauth-access-token")
        try secretStore.delete("oauth-refresh-token")
        try secretStore.delete("oauth-client-id")
    }

    func cancelSignIn() {
        guard case .signingIn = state else { return }
        signInCancellationRequested = true
        activeSignInTask?.cancel()
        oauth.cancelSignIn()
    }

    @discardableResult
    func copyBrowserSignInLink() -> Bool {
        guard let browserSignInURL else { return false }
        authorizationLinkClipboard.copy(browserSignInURL)
        return true
    }

    func finishDeviceRegistration() async {
        guard !isFinishingEnrollment,
              case .finishDeviceRegistration(let key, let enrollment) = state else { return }
        isFinishingEnrollment = true
        enrollmentRetryError = nil
        defer { isFinishingEnrollment = false }
        do {
            try await apply(devices.resumeDeviceRegistration(
                recoveryKey: key,
                enrollment: enrollment
            ))
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.retryConnection
        }
    }

    func finishRecoverySetup() async {
        guard !isFinishingEnrollment,
              case .finishRecoverySetup(let key, let enrollment) = state else { return }
        isFinishingEnrollment = true
        enrollmentRetryError = nil
        defer { isFinishingEnrollment = false }
        do {
            try await apply(devices.resumeRecoverySetup(
                recoveryKey: key,
                enrollment: enrollment
            ))
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.retryConnection
        }
    }

    private func apply(_ outcome: NativeAccountEnrollmentState) throws {
        switch outcome {
        case .finishDeviceRegistration(let key, let enrollment):
            state = .finishDeviceRegistration(key, enrollment)
        case .finishRecoverySetup(let key, let enrollment):
            state = .finishRecoverySetup(key, enrollment)
        case .saveRecoveryKey(let key, let enrollment):
            try pending.save(enrollment: enrollment, recoveryKey: key)
            state = .saveRecoveryKey(key, enrollment)
        case .enterRecoveryKey(let enrollment):
            try pending.save(enrollment: enrollment, recoveryKey: nil)
            state = .enterRecoveryKey(enrollment)
        case .ready(let enrollment):
            state = .ready(enrollment)
        }
    }

    func restore(recoveryKey: String) async {
        guard case .enterRecoveryKey(let enrollment) = state else { return }
        do {
            let restored = try await devices.restore(
                recoveryKey: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines),
                enrollment: enrollment
            )
            try pending.markReady(restored)
            state = .ready(restored)
        } catch {
            state = .failed("That Recovery Key could not decrypt this Curfew account.")
        }
    }

    func acknowledgeSavedRecoveryKey() async -> AccountDeviceEnrollment? {
        guard !isFinishingEnrollment,
              case .saveRecoveryKey(let key, let enrollment) = state else { return nil }
        isFinishingEnrollment = true
        enrollmentRetryError = nil
        defer { isFinishingEnrollment = false }
        do {
            try await apply(devices.acknowledgeSavedRecoveryKey(
                recoveryKey: key,
                enrollment: enrollment
            ))
            guard case .ready(let completed) = state else { return nil }
            return completed
        } catch {
            state = .finishRecoverySetup(key, enrollment)
            enrollmentRetryError = AccountEnrollmentFailureCopy.retryConnection
            return nil
        }
    }

    private func deviceID() throws -> UUID {
        if let data = try secretStore.data(for: "account-device-id"),
           let text = String(data: data, encoding: .utf8),
           let identifier = UUID(uuidString: text) {
            return identifier
        }
        let identifier = UUID()
        try secretStore.save(
            Data(identifier.uuidString.lowercased().utf8),
            for: "account-device-id"
        )
        return identifier
    }
}
