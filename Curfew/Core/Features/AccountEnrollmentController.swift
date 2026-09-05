import Combine
import Foundation

enum AccountEnrollmentUIState: Equatable {
    case accountFree
    case signingIn
    case saveRecoveryKey(String, AccountDeviceEnrollment)
    case enterRecoveryKey(AccountDeviceEnrollment)
    case ready(AccountDeviceEnrollment)
    case failed(String)
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
    }

    func load() throws -> AccountEnrollmentUIState? {
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
    }
}

@MainActor
final class AccountEnrollmentController: ObservableObject {
    @Published private(set) var state: AccountEnrollmentUIState = .accountFree

    private let secretStore: any AccountSecretStoring
    private let oauth: AccountOAuthEnrollmentService
    private let devices: NativeAccountDeviceEnrollmentService
    private let pending: AccountEnrollmentPendingStore

    init(secretStore: any AccountSecretStoring = KeychainAccountSecretStore()) {
        self.secretStore = secretStore
        self.oauth = AccountOAuthEnrollmentService(secretStore: secretStore)
        self.devices = NativeAccountDeviceEnrollmentService(secretStore: secretStore)
        self.pending = AccountEnrollmentPendingStore(secretStore: secretStore)
        self.state = (try? pending.load()) ?? .accountFree
    }

    func signIn() async {
        state = .signingIn
        do {
            let grant = try await oauth.signIn()
            let outcome = try await devices.enroll(
                grant: grant,
                deviceID: deviceID()
            )
            switch outcome {
            case .saveRecoveryKey(let key, let enrollment):
                try pending.save(enrollment: enrollment, recoveryKey: key)
                state = .saveRecoveryKey(key, enrollment)
            case .enterRecoveryKey(let enrollment):
                try pending.save(enrollment: enrollment, recoveryKey: nil)
                state = .enterRecoveryKey(enrollment)
            }
        } catch {
            state = .failed("Account sign-in or encrypted device enrollment failed.")
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
