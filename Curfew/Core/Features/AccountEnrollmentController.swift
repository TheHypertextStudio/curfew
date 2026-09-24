import AppKit
import Combine
import CurfewProtocols
import Foundation

@MainActor
final class AccountEnrollmentController: ObservableObject {
    @Published private(set) var state: AccountEnrollmentUIState = .accountFree
    @Published private(set) var isFinishingEnrollment = false
    @Published private(set) var enrollmentRetryError: String?
    @Published private(set) var requiresReauthorization = false
    @Published private(set) var canReauthorizeSavedEnrollment = true
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
        } catch AccountOAuthTokenRefreshError.missingCredentials {
            requireReauthorization()
        } catch {
            state = .storageUnavailable
        }
    }

    func signIn() async {
        if case .finishDeviceConnection = state {
            await resumeAuthorizedConnection()
            return
        }
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
        let identifier: UUID
        do {
            identifier = try deviceID()
            try pending.saveAuthorizedConnection(grant: grant, deviceID: identifier)
        } catch {
            state = .storageUnavailable
            return
        }
        await connectDevice(grant: grant, deviceID: identifier)
    }

    private func resumeAuthorizedConnection() async {
        do {
            guard let checkpoint = try pending.loadAuthorizedConnection() else {
                reloadSavedEnrollment()
                return
            }
            await connectDevice(grant: checkpoint.grant, deviceID: checkpoint.deviceID)
        } catch AccountOAuthTokenRefreshError.missingCredentials {
            requireReauthorization()
        } catch {
            state = .storageUnavailable
        }
    }

    private func connectDevice(grant: AccountOAuthGrant, deviceID: UUID) async {
        state = .connectingDevice
        enrollmentRetryError = nil
        do {
            let outcome = try await devices.enroll(grant: grant, deviceID: deviceID)
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
                try pending.markReady(enrollment)
                state = .ready(enrollment)
            }
        } catch AccountOAuthTokenRefreshError.rejected {
            requireReauthorization()
        } catch {
            reloadSavedEnrollment()
            if case .accountFree = state {
                state = .failed(AccountEnrollmentFailureCopy.deviceConnection)
            } else if case .storageUnavailable = state {
                return
            }
            enrollmentRetryError = AccountEnrollmentFailureCopy.deviceConnection
        }
    }

    private func authenticate(expectedAccountUserID: String? = nil) async throws
        -> AccountOAuthGrant {
        let authorizationURLHandler: @MainActor (URL) -> Void = { [weak self] authorizationURL in
            self?.browserSignInURL = authorizationURL
        }
        let authentication = Task {
            if let expectedAccountUserID {
                try await oauth.reauthorize(
                    expectedAccountUserID: expectedAccountUserID,
                    presentationWindow: presentationWindow,
                    authorizationURLHandler: authorizationURLHandler
                )
            } else {
                try await oauth.signIn(
                    presentationWindow: presentationWindow,
                    authorizationURLHandler: authorizationURLHandler
                )
            }
        }
        activeSignInTask = authentication
        defer {
            activeSignInTask = nil
            browserSignInURL = nil
            authorizationLinkClipboard.clearIfUnchanged()
        }
        let grant = try await authentication.value
        if signInCancellationRequested {
            if expectedAccountUserID == nil {
                try discardCancelledGrant(grant)
            }
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
        } catch AccountOAuthTokenRefreshError.rejected,
            AccountOAuthTokenRefreshError.missingCredentials {
            requireSavedEnrollmentReauthorization()
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
        } catch AccountOAuthTokenRefreshError.rejected,
            AccountOAuthTokenRefreshError.missingCredentials {
            requireSavedEnrollmentReauthorization()
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.retryConnection
        }
    }
}

extension AccountEnrollmentController {
    func reauthorizeSavedEnrollment() async {
        guard requiresReauthorization, canReauthorizeSavedEnrollment else { return }
        let savedState = state
        guard let step = SavedEnrollmentReauthorizationStep(state: savedState) else { return }
        let expectedAccountUserID: String
        do {
            expectedAccountUserID = try accountUserID(for: step)
        } catch AccountOAuthEnrollmentError.invalidResponse {
            canReauthorizeSavedEnrollment = false
            enrollmentRetryError = AccountEnrollmentFailureCopy.unanchoredCheckpoint
            return
        } catch {
            enrollmentRetryError = AccountEnrollmentFailureCopy.retryConnection
            return
        }
        signInCancellationRequested = false
        state = .signingIn
        browserSignInURL = nil
        do {
            _ = try await authenticate(expectedAccountUserID: expectedAccountUserID)
            state = savedState
            requiresReauthorization = false
            enrollmentRetryError = nil
            switch step {
            case .deviceRegistration:
                await finishDeviceRegistration()
            case .recoverySetup:
                await finishRecoverySetup()
            case .existingKeyRecovery:
                break
            }
        } catch AccountOAuthEnrollmentError.accountMismatch {
            state = savedState
            enrollmentRetryError = AccountEnrollmentFailureCopy.wrongAccount
        } catch {
            state = savedState
            enrollmentRetryError = AccountEnrollmentFailureCopy.reauthorization
        }
    }

    private func accountUserID(for step: SavedEnrollmentReauthorizationStep) throws -> String {
        switch step {
        case .deviceRegistration, .recoverySetup:
            guard let checkpoint = try pending.loadRecoverySetup() else {
                throw AccountOAuthEnrollmentError.invalidResponse
            }
            return try checkpoint.expectedAccountUserID()
        case .existingKeyRecovery:
            guard let checkpoint = try pending.loadExistingKeyRecovery() else {
                throw AccountOAuthEnrollmentError.invalidResponse
            }
            return try checkpoint.expectedAccountUserID()
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
        guard case .enterRecoveryKey(let enrollment) = state,
              !requiresReauthorization else { return }
        enrollmentRetryError = nil
        do {
            let restored = try await devices.restore(
                recoveryKey: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines),
                enrollment: enrollment
            )
            try pending.markReady(restored)
            state = .ready(restored)
        } catch AccountOAuthTokenRefreshError.rejected,
            AccountOAuthTokenRefreshError.missingCredentials {
            state = .enterRecoveryKey(enrollment)
            requireSavedEnrollmentReauthorization()
        } catch {
            state = .enterRecoveryKey(enrollment)
            enrollmentRetryError = "Curfew couldn’t restore encrypted data. "
                + "Check the Recovery Key and your connection, then try again."
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
        } catch AccountOAuthTokenRefreshError.rejected,
            AccountOAuthTokenRefreshError.missingCredentials {
            state = .finishRecoverySetup(key, enrollment)
            requireSavedEnrollmentReauthorization()
            return nil
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

private enum SavedEnrollmentReauthorizationStep {
    case deviceRegistration
    case recoverySetup
    case existingKeyRecovery

    init?(state: AccountEnrollmentUIState) {
        switch state {
        case .finishDeviceRegistration:
            self = .deviceRegistration
        case .finishRecoverySetup:
            self = .recoverySetup
        case .enterRecoveryKey:
            self = .existingKeyRecovery
        default:
            return nil
        }
    }
}

private extension AccountEnrollmentController {
    func requireSavedEnrollmentReauthorization() {
        requiresReauthorization = true
        canReauthorizeSavedEnrollment = true
        enrollmentRetryError = AccountEnrollmentFailureCopy.reauthorization
    }

    func requireReauthorization() {
        do {
            try pending.clearAuthorizedConnection()
            state = try pending.load() ?? .failed(AccountEnrollmentFailureCopy.reauthorization)
        } catch {
            state = .storageUnavailable
        }
    }
}
