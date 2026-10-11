import CurfewKit
import Foundation

enum OAuthCredentialPersistenceError: Error {
    case storageUnavailable
}

struct OAuthCredentials {
    let clientID: Data?
    let refreshToken: Data?
    let accessToken: Data?

    var hasUsableTokenPair: Bool {
        guard let accessToken,
              let refreshToken,
              let access = String(data: accessToken, encoding: .utf8),
              let refresh = String(data: refreshToken, encoding: .utf8)
        else { return false }
        return !access.isEmpty && !refresh.isEmpty
    }

    init(secretStore: any AccountSecretStoring) throws {
        self.clientID = try secretStore.data(for: "oauth-client-id")
        self.refreshToken = try secretStore.data(for: "oauth-refresh-token")
        self.accessToken = try secretStore.data(for: "oauth-access-token")
    }

    func replace(with grant: AccountOAuthGrant, in secretStore: any AccountSecretStoring) throws {
        var didWrite = false
        do {
            try secretStore.save(
                Data(AccountOAuthOfficialClient.clientID.utf8),
                for: "oauth-client-id"
            )
            didWrite = true
            try secretStore.save(Data(grant.tokens.refreshToken.utf8), for: "oauth-refresh-token")
            try secretStore.save(Data(grant.tokens.accessToken.utf8), for: "oauth-access-token")
        } catch {
            guard didWrite else { throw error }
            do {
                try restore(to: secretStore)
            } catch {
                throw OAuthCredentialPersistenceError.storageUnavailable
            }
            throw error
        }
    }

    static func discardIfCurrentGrant(
        _ grant: AccountOAuthGrant,
        from secretStore: any AccountSecretStoring
    ) throws {
        guard try secretStore
            .data(for: "oauth-access-token") == Data(grant.tokens.accessToken.utf8),
            try secretStore.data(for: "oauth-refresh-token") == Data(grant.tokens.refreshToken.utf8)
        else { return }
        try secretStore.delete("oauth-access-token")
        try secretStore.delete("oauth-refresh-token")
        try secretStore.delete("oauth-client-id")
    }

    func restoreIfCurrentGrant(
        _ grant: AccountOAuthGrant,
        to secretStore: any AccountSecretStoring
    ) throws {
        guard try secretStore
            .data(for: "oauth-access-token") == Data(grant.tokens.accessToken.utf8),
            try secretStore.data(for: "oauth-refresh-token") == Data(grant.tokens.refreshToken.utf8)
        else { return }
        do {
            try restore(to: secretStore)
        } catch {
            throw OAuthCredentialPersistenceError.storageUnavailable
        }
    }

    private func restore(to secretStore: any AccountSecretStoring) throws {
        try secretStore.delete("oauth-access-token")
        try restore(refreshToken, for: "oauth-refresh-token", in: secretStore)
        try restore(clientID, for: "oauth-client-id", in: secretStore)
        try restore(accessToken, for: "oauth-access-token", in: secretStore)
    }

    private func restore(
        _ value: Data?,
        for key: String,
        in secretStore: any AccountSecretStoring
    ) throws {
        if let value {
            try secretStore.save(value, for: key)
        } else {
            try secretStore.delete(key)
        }
    }
}
