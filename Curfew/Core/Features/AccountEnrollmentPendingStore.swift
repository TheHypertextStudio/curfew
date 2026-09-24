import CurfewProtocols
import Foundation

final class AccountEnrollmentPendingStore {
    private static let readyKey = "pending-account-enrollment-ready"
    private static let authorizedConnectionKey = "pending-account-authorized-connection"
    private let secretStore: any AccountSecretStoring

    init(secretStore: any AccountSecretStoring) {
        self.secretStore = secretStore
    }

    func save(enrollment: AccountDeviceEnrollment, recoveryKey: String?) throws {
        try secretStore.save(JSONEncoder().encode(enrollment), for: "pending-account-enrollment")
        if let recoveryKey {
            try secretStore.save(Data(recoveryKey.utf8), for: "pending-recovery-key")
        } else {
            try secretStore.delete("pending-recovery-key")
        }
        try secretStore.delete("pending-recovery-setup")
        try clearAuthorizedConnection()
    }

    func saveAuthorizedConnection(grant: AccountOAuthGrant, deviceID: UUID) throws {
        let checkpoint = AccountAuthorizedConnectionCheckpoint(
            oauthState: grant.state,
            pkceChallenge: grant.codeChallenge,
            deviceID: deviceID
        )
        try secretStore.save(
            JSONEncoder().encode(checkpoint),
            for: Self.authorizedConnectionKey
        )
    }

    func loadAuthorizedConnection() throws -> AccountAuthorizedConnection? {
        guard let data = try secretStore.data(for: Self.authorizedConnectionKey) else { return nil }
        let checkpoint = try JSONDecoder().decode(
            AccountAuthorizedConnectionCheckpoint.self,
            from: data
        )
        guard let accessData = try secretStore.data(for: "oauth-access-token"),
              let refreshData = try secretStore.data(for: "oauth-refresh-token"),
              let accessToken = String(data: accessData, encoding: .utf8),
              let refreshToken = String(data: refreshData, encoding: .utf8),
              !accessToken.isEmpty, !refreshToken.isEmpty
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return AccountAuthorizedConnection(
            grant: AccountOAuthGrant(
                tokens: AccountOAuthTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                ),
                state: checkpoint.oauthState,
                codeChallenge: checkpoint.pkceChallenge
            ),
            deviceID: checkpoint.deviceID
        )
    }

    func clearAuthorizedConnection() throws {
        try secretStore.delete(Self.authorizedConnectionKey)
    }

    func saveRecoverySetup(
        enrollment: AccountDeviceEnrollment,
        recoveryKey: String,
        recoveryEnvelope: RecoveryKeyEnvelope,
        receiptData: Data,
        oauthState: String = "",
        pkceChallenge: String = ""
    ) throws {
        try save(AccountRecoverySetupCheckpoint(
            enrollment: enrollment,
            recoveryKey: recoveryKey,
            recoveryEnvelope: recoveryEnvelope,
            oauthState: oauthState,
            pkceChallenge: pkceChallenge,
            receiptData: receiptData
        ))
    }

    func saveDeviceRegistration(
        enrollment: AccountDeviceEnrollment,
        recoveryKey: String,
        recoveryEnvelope: RecoveryKeyEnvelope,
        oauthState: String,
        pkceChallenge: String
    ) throws {
        try save(AccountRecoverySetupCheckpoint(
            enrollment: enrollment,
            recoveryKey: recoveryKey,
            recoveryEnvelope: recoveryEnvelope,
            oauthState: oauthState,
            pkceChallenge: pkceChallenge,
            receiptData: nil
        ))
    }

    func saveRegistrationReceipt(_ receiptData: Data) throws {
        guard let checkpoint = try loadRecoverySetup() else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        try save(checkpoint.updating(receiptData: receiptData))
    }

    func markRecoveryKeySaved() throws {
        guard let checkpoint = try loadRecoverySetup(), checkpoint.receiptData != nil else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        try save(checkpoint.updating(recoveryKeySaved: true))
    }

    /// Records the completed enrollment before removing any earlier checkpoint.
    /// Loading prioritizes this marker, so a crash during cleanup can never
    /// roll a server-complete enrollment back into recovery setup.
    func markReady(_ enrollment: AccountDeviceEnrollment) throws {
        try secretStore.save(JSONEncoder().encode(enrollment), for: Self.readyKey)
        try secretStore.delete("pending-account-enrollment")
        try secretStore.delete("pending-recovery-key")
        try secretStore.delete("pending-recovery-setup")
        try clearAuthorizedConnection()
    }

    private func save(_ checkpoint: AccountRecoverySetupCheckpoint) throws {
        try secretStore.save(JSONEncoder().encode(checkpoint), for: "pending-recovery-setup")
        try clearAuthorizedConnection()
    }

    func loadRecoverySetup() throws -> AccountRecoverySetupCheckpoint? {
        guard let data = try secretStore.data(for: "pending-recovery-setup") else { return nil }
        return try JSONDecoder().decode(AccountRecoverySetupCheckpoint.self, from: data)
    }

    func load() throws -> AccountEnrollmentUIState? {
        if let data = try secretStore.data(for: Self.readyKey) {
            return try .ready(JSONDecoder().decode(AccountDeviceEnrollment.self, from: data))
        }
        if let checkpoint = try loadRecoverySetup() {
            if checkpoint.receiptData == nil {
                return .finishDeviceRegistration(checkpoint.recoveryKey, checkpoint.enrollment)
            }
            return checkpoint.recoveryKeySaved == true
                ? .finishRecoverySetup(checkpoint.recoveryKey, checkpoint.enrollment)
                : .saveRecoveryKey(checkpoint.recoveryKey, checkpoint.enrollment)
        }
        if let data = try secretStore.data(for: "pending-account-enrollment") {
            let enrollment = try JSONDecoder().decode(AccountDeviceEnrollment.self, from: data)
            if let keyData = try secretStore.data(for: "pending-recovery-key"),
               let key = String(data: keyData, encoding: .utf8),
               !key.isEmpty {
                return .saveRecoveryKey(key, enrollment)
            }
            return .enterRecoveryKey(enrollment)
        }
        if try loadAuthorizedConnection() != nil {
            return .finishDeviceConnection
        }
        return nil
    }

    func clear() throws {
        try secretStore.delete(Self.readyKey)
        try secretStore.delete("pending-account-enrollment")
        try secretStore.delete("pending-recovery-key")
        try secretStore.delete("pending-recovery-setup")
        try clearAuthorizedConnection()
    }
}

struct AccountAuthorizedConnectionCheckpoint: Codable {
    let oauthState: String
    let pkceChallenge: String
    let deviceID: UUID
}

struct AccountAuthorizedConnection {
    let grant: AccountOAuthGrant
    let deviceID: UUID
}

struct AccountRecoverySetupCheckpoint: Codable {
    let enrollment: AccountDeviceEnrollment
    let recoveryKey: String
    let recoveryEnvelope: RecoveryKeyEnvelope
    let oauthState: String
    let pkceChallenge: String
    let receiptData: Data?
    let recoveryKeySaved: Bool?

    init(
        enrollment: AccountDeviceEnrollment,
        recoveryKey: String,
        recoveryEnvelope: RecoveryKeyEnvelope,
        oauthState: String,
        pkceChallenge: String,
        receiptData: Data?,
        recoveryKeySaved: Bool? = false
    ) {
        self.enrollment = enrollment
        self.recoveryKey = recoveryKey
        self.recoveryEnvelope = recoveryEnvelope
        self.oauthState = oauthState
        self.pkceChallenge = pkceChallenge
        self.receiptData = receiptData
        self.recoveryKeySaved = recoveryKeySaved
    }

    func updating(
        receiptData: Data? = nil,
        recoveryKeySaved: Bool? = nil
    ) -> AccountRecoverySetupCheckpoint {
        AccountRecoverySetupCheckpoint(
            enrollment: enrollment,
            recoveryKey: recoveryKey,
            recoveryEnvelope: recoveryEnvelope,
            oauthState: oauthState,
            pkceChallenge: pkceChallenge,
            receiptData: receiptData ?? self.receiptData,
            recoveryKeySaved: recoveryKeySaved ?? self.recoveryKeySaved
        )
    }
}
