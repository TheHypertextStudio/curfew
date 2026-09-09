import AppKit
import Combine
import CurfewProtocols
import Foundation

enum AccountEnrollmentUIState: Equatable {
    case accountFree
    case signingIn
    case finishDeviceRegistration(String, AccountDeviceEnrollment)
    case finishRecoverySetup(String, AccountDeviceEnrollment)
    case saveRecoveryKey(String, AccountDeviceEnrollment)
    case enterRecoveryKey(AccountDeviceEnrollment)
    case ready(AccountDeviceEnrollment)
    case failed(String)
}

enum AccountEnrollmentSignInPolicy {
    static func canStart(from state: AccountEnrollmentUIState) -> Bool {
        if case .signingIn = state {
            return false
        }
        return true
    }
}

@MainActor
protocol AccountOAuthEnrolling {
    func signIn(presentationWindow: NSWindow?) async throws -> AccountOAuthGrant
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

final class AccountEnrollmentPendingStore {
    private let secretStore: any AccountSecretStoring

    init(secretStore: any AccountSecretStoring) {
        self.secretStore = secretStore
    }

    func save(enrollment: AccountDeviceEnrollment, recoveryKey: String?) throws {
        try secretStore.save(
            JSONEncoder().encode(enrollment),
            for: "pending-account-enrollment"
        )
        if let recoveryKey {
            try secretStore.save(Data(recoveryKey.utf8), for: "pending-recovery-key")
        } else {
            try secretStore.delete("pending-recovery-key")
        }
        try secretStore.delete("pending-recovery-setup")
    }

    func saveRecoverySetup(
        enrollment: AccountDeviceEnrollment,
        recoveryKey: String,
        recoveryEnvelope: RecoveryKeyEnvelope,
        receiptData: Data,
        oauthState: String = "",
        pkceChallenge: String = ""
    ) throws {
        let checkpoint = AccountRecoverySetupCheckpoint(
            enrollment: enrollment,
            recoveryKey: recoveryKey,
            recoveryEnvelope: recoveryEnvelope,
            oauthState: oauthState,
            pkceChallenge: pkceChallenge,
            receiptData: receiptData
        )
        try secretStore.save(
            JSONEncoder().encode(checkpoint),
            for: "pending-recovery-setup"
        )
    }

    func saveDeviceRegistration(
        enrollment: AccountDeviceEnrollment,
        recoveryKey: String,
        recoveryEnvelope: RecoveryKeyEnvelope,
        oauthState: String,
        pkceChallenge: String
    ) throws {
        let checkpoint = AccountRecoverySetupCheckpoint(
            enrollment: enrollment,
            recoveryKey: recoveryKey,
            recoveryEnvelope: recoveryEnvelope,
            oauthState: oauthState,
            pkceChallenge: pkceChallenge,
            receiptData: nil
        )
        try save(checkpoint)
    }

    func saveRegistrationReceipt(_ receiptData: Data) throws {
        guard let checkpoint = try loadRecoverySetup() else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        try save(AccountRecoverySetupCheckpoint(
            enrollment: checkpoint.enrollment,
            recoveryKey: checkpoint.recoveryKey,
            recoveryEnvelope: checkpoint.recoveryEnvelope,
            oauthState: checkpoint.oauthState,
            pkceChallenge: checkpoint.pkceChallenge,
            receiptData: receiptData
        ))
    }

    private func save(_ checkpoint: AccountRecoverySetupCheckpoint) throws {
        try secretStore.save(
            JSONEncoder().encode(checkpoint),
            for: "pending-recovery-setup"
        )
    }

    func loadRecoverySetup() throws -> AccountRecoverySetupCheckpoint? {
        guard let data = try secretStore.data(for: "pending-recovery-setup") else {
            return nil
        }
        return try JSONDecoder().decode(AccountRecoverySetupCheckpoint.self, from: data)
    }

    func load() throws -> AccountEnrollmentUIState? {
        if let checkpoint = try loadRecoverySetup() {
            if checkpoint.receiptData == nil {
                return .finishDeviceRegistration(
                    checkpoint.recoveryKey,
                    checkpoint.enrollment
                )
            }
            return .finishRecoverySetup(
                checkpoint.recoveryKey,
                checkpoint.enrollment
            )
        }
        guard let data = try secretStore.data(for: "pending-account-enrollment") else {
            return nil
        }
        let enrollment = try JSONDecoder().decode(AccountDeviceEnrollment.self, from: data)
        if let keyData = try secretStore.data(for: "pending-recovery-key"),
           let key = String(data: keyData, encoding: .utf8),
           !key.isEmpty {
            return .saveRecoveryKey(key, enrollment)
        }
        return .enterRecoveryKey(enrollment)
    }

    func clear() throws {
        try secretStore.delete("pending-account-enrollment")
        try secretStore.delete("pending-recovery-key")
        try secretStore.delete("pending-recovery-setup")
    }
}

struct AccountRecoverySetupCheckpoint: Codable {
    let enrollment: AccountDeviceEnrollment
    let recoveryKey: String
    let recoveryEnvelope: RecoveryKeyEnvelope
    let oauthState: String
    let pkceChallenge: String
    let receiptData: Data?
}

@MainActor
final class AccountEnrollmentController: ObservableObject {
    @Published private(set) var state: AccountEnrollmentUIState = .accountFree
    @Published private(set) var isFinishingEnrollment = false
    @Published private(set) var enrollmentRetryError: String?

    private let secretStore: any AccountSecretStoring
    private let oauth: any AccountOAuthEnrolling
    private let devices: any AccountDeviceEnrolling
    private let pending: AccountEnrollmentPendingStore
    weak var presentationWindow: NSWindow?

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        oauth: (any AccountOAuthEnrolling)? = nil,
        devices: (any AccountDeviceEnrolling)? = nil
    ) {
        self.secretStore = secretStore
        self.oauth = oauth ?? AccountOAuthEnrollmentService(secretStore: secretStore)
        self.devices = devices ?? NativeAccountDeviceEnrollmentService(secretStore: secretStore)
        self.pending = AccountEnrollmentPendingStore(secretStore: secretStore)
        self.state = (try? pending.load()) ?? .accountFree
    }

    func signIn() async {
        guard AccountEnrollmentSignInPolicy.canStart(from: state) else { return }
        state = .signingIn
        let grant: AccountOAuthGrant
        do {
            grant = try await oauth.signIn(presentationWindow: presentationWindow)
        } catch AccountOAuthEnrollmentError.browserCompletedConnectionFailed {
            state = .failed(AccountEnrollmentFailureCopy.browserCompleted)
            return
        } catch {
            state = .failed(AccountEnrollmentFailureCopy.authorization)
            return
        }
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
            }
        } catch {
            state = .failed(AccountEnrollmentFailureCopy.deviceConnection)
        }
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
        }
    }

    func restore(recoveryKey: String) async {
        guard case .enterRecoveryKey(let enrollment) = state else { return }
        do {
            let restored = try await devices.restore(
                recoveryKey: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines),
                enrollment: enrollment
            )
            try pending.clear()
            state = .ready(restored)
        } catch {
            state = .failed("That Recovery Key could not decrypt this Curfew account.")
        }
    }

    func acknowledgeSavedRecoveryKey() throws -> AccountDeviceEnrollment? {
        guard case .saveRecoveryKey(_, let enrollment) = state else { return nil }
        try pending.clear()
        state = .ready(enrollment)
        return enrollment
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
