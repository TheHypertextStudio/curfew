@testable import Curfew
import Foundation
import XCTest

@MainActor
final class AccountOAuthUserInfoTests: XCTestCase {
    func testAcceptedResourceTokenCarriesTheCheckpointAccountID() {
        let payload = Data(#"{"sub":"original-account"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payload).signature"

        XCTAssertEqual(AccountOAuthTokenSubject.extract(from: token), "original-account")
        XCTAssertNil(AccountOAuthTokenSubject.extract(from: "not-a-token"))
        let grant = AccountOAuthGrant(
            resourceTokens: AccountOAuthTokens(accessToken: token, refreshToken: "refresh"),
            state: "state",
            codeChallenge: "challenge"
        )
        XCTAssertEqual(grant.subjectID, "original-account")
    }

    func testResourceTokenIsBoundToTheServerVerifiedAccount() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountUserInfoURLProtocol.self]
        let session = URLSession(configuration: configuration)
        AccountUserInfoURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/oauth2/userinfo")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer resource-access-token"
            )
            return (200, Data(#"{"sub":"original-account"}"#.utf8))
        }
        defer { AccountUserInfoURLProtocol.handler = nil }

        let subject = try await AccountOAuthUserInfo.subject(
            accessToken: "resource-access-token",
            session: session,
            endpoints: .staging
        )

        XCTAssertEqual(subject, "original-account")
    }

    func testWrongAccountCannotReplaceSavedOAuthCredentials() async throws {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        try secrets.save(Data("old-access".utf8), for: "oauth-access-token")
        try secrets.save(Data("old-refresh".utf8), for: "oauth-refresh-token")
        let session = userInfoSession(subject: "different-account")
        defer { AccountUserInfoURLProtocol.handler = nil }

        do {
            try await AccountOAuthReauthorization.commit(
                grant: stagedGrant,
                expectedAccountUserID: "original-account",
                secretStore: secrets,
                session: session,
                endpoints: .staging
            )
            XCTFail("another account must not replace the pending Mac's credentials")
        } catch AccountOAuthEnrollmentError.accountMismatch {
            XCTAssertEqual(try secrets.data(for: "oauth-access-token"), Data("old-access".utf8))
            XCTAssertEqual(try secrets.data(for: "oauth-refresh-token"), Data("old-refresh".utf8))
        }
    }

    func testSameAccountCanReplaceCredentialsAfterServerIdentityCheck() async throws {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        let session = userInfoSession(subject: "original-account")
        defer { AccountUserInfoURLProtocol.handler = nil }

        try await AccountOAuthReauthorization.commit(
            grant: stagedGrant,
            expectedAccountUserID: "original-account",
            secretStore: secrets,
            session: session,
            endpoints: .staging
        )

        XCTAssertEqual(try secrets.data(for: "oauth-access-token"), Data("new-access".utf8))
        XCTAssertEqual(try secrets.data(for: "oauth-refresh-token"), Data("new-refresh".utf8))
    }

    func testFailedCredentialWriteDoesNotReplaceExistingAccountTokens() async throws {
        let secrets = FailingReauthorizationSecretStore()
        let session = userInfoSession(subject: "original-account")
        defer { AccountUserInfoURLProtocol.handler = nil }

        do {
            try await AccountOAuthReauthorization.commit(
                grant: stagedGrant,
                expectedAccountUserID: "original-account",
                secretStore: secrets,
                session: session,
                endpoints: .staging
            )
            XCTFail("a failed Keychain write must abort staged reauthorization")
        } catch FailingReauthorizationSecretStore.WriteError.denied {
            XCTAssertEqual(try secrets.data(for: "oauth-access-token"), Data("old-access".utf8))
            XCTAssertEqual(try secrets.data(for: "oauth-refresh-token"), Data("old-refresh".utf8))
        }
    }

    private var stagedGrant: AccountOAuthGrant {
        AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "new-access", refreshToken: "new-refresh"),
            state: "new-state",
            codeChallenge: "new-challenge"
        )
    }

    private func userInfoSession(subject: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountUserInfoURLProtocol.self]
        AccountUserInfoURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
            return (200, Data(#"{"sub":"\#(subject)"}"#.utf8))
        }
        return URLSession(configuration: configuration)
    }
}

private final class FailingReauthorizationSecretStore: AccountSecretStoring {
    enum WriteError: Error { case denied }

    private let values: [String: Data] = [
        "oauth-access-token": Data("old-access".utf8),
        "oauth-refresh-token": Data("old-refresh".utf8)
    ]

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_: Data, for _: String) throws {
        throw WriteError.denied
    }

    func delete(_: String) throws {
        throw WriteError.denied
    }
}

private final class AccountUserInfoURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler,
              let url = request.url
        else { return }
        let (status, data) = handler(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
