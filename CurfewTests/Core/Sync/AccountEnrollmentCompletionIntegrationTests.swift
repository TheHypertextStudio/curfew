import AppKit
@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class AccountEnrollmentCompletionTests: XCTestCase {
    func testBrowserGrantToSavedRecoveryKeyToReadyKeepsTheReceipt() async throws {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        try secrets.save(Data("access-token".utf8), for: "oauth-access-token")
        try secrets.save(Data("refresh-token".utf8), for: "oauth-refresh-token")
        try secrets.save(Data("curfew-native-client".utf8), for: "oauth-client-id")
        try secrets.save(
            Data("018f4f45-cafe-7f00-9a82-e47805fb4d35".utf8),
            for: "account-device-id"
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnrollmentCompletionURLProtocol.self]
        EnrollmentCompletionURLProtocol.handler = Self.response
        EnrollmentCompletionURLProtocol.conflictingEnvelope = false
        EnrollmentCompletionURLProtocol.observedPaths = []
        EnrollmentCompletionURLProtocol.observedErrors = []
        defer { EnrollmentCompletionURLProtocol.handler = nil }
        let devices = NativeAccountDeviceEnrollmentService(
            secretStore: secrets,
            session: URLSession(configuration: configuration),
            endpoints: .staging,
            remoteCommandEnrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: root.appendingPathComponent("enrollment.json")
            )
        )
        let controller = AccountEnrollmentController(
            secretStore: secrets,
            oauth: CompletionOAuthFixture(),
            devices: devices
        )

        await controller.signIn()

        guard case .saveRecoveryKey(_, let enrollment) = controller.state else {
            return XCTFail(
                "registration should display its Recovery Key; "
                    + "requests: \(EnrollmentCompletionURLProtocol.observedPaths); "
                    + "errors: \(EnrollmentCompletionURLProtocol.observedErrors)"
            )
        }
        let pending = AccountEnrollmentPendingStore(secretStore: secrets)
        XCTAssertNotNil(try pending.loadRecoverySetup()?.receiptData)

        let completed = await controller.acknowledgeSavedRecoveryKey()

        XCTAssertEqual(completed, enrollment)
        XCTAssertEqual(controller.state, .ready(enrollment))
        XCTAssertNil(try pending.loadRecoverySetup())
        XCTAssertEqual(try pending.load(), .ready(enrollment))
    }

    func testExistingEnvelopeKeepsAccountBindingForLaterKeyRestoration() async throws {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        try secrets.save(Data("access-token".utf8), for: "oauth-access-token")
        try secrets.save(Data("refresh-token".utf8), for: "oauth-refresh-token")
        try secrets.save(Data("curfew-native-client".utf8), for: "oauth-client-id")
        try secrets.save(
            Data("018f4f45-cafe-7f00-9a82-e47805fb4d35".utf8),
            for: "account-device-id"
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnrollmentCompletionURLProtocol.self]
        EnrollmentCompletionURLProtocol.handler = Self.response
        EnrollmentCompletionURLProtocol.conflictingEnvelope = true
        defer {
            EnrollmentCompletionURLProtocol.handler = nil
            EnrollmentCompletionURLProtocol.conflictingEnvelope = false
        }
        let devices = NativeAccountDeviceEnrollmentService(
            secretStore: secrets,
            session: URLSession(configuration: configuration),
            endpoints: .staging,
            remoteCommandEnrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: root.appendingPathComponent("enrollment.json")
            )
        )
        let controller = AccountEnrollmentController(
            secretStore: secrets,
            oauth: CompletionOAuthFixture(),
            devices: devices
        )

        await controller.signIn()
        guard case .saveRecoveryKey = controller.state else {
            return XCTFail("registration should display its Recovery Key")
        }
        _ = await controller.acknowledgeSavedRecoveryKey()

        guard case .enterRecoveryKey(let enrollment) = controller.state else {
            return XCTFail("existing envelope should require the account's older key")
        }
        let pending = AccountEnrollmentPendingStore(secretStore: secrets)
        XCTAssertEqual(try pending.load(), .enterRecoveryKey(enrollment))
        XCTAssertEqual(
            try pending.loadExistingKeyRecovery()?.expectedAccountUserID(),
            "original-account"
        )
        XCTAssertNil(try pending.loadRecoverySetup())
    }

    private static func response(for request: URLRequest) throws -> (Int, Data) {
        guard let path = request.url?.path else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        switch (request.httpMethod, path) {
        case ("POST", "/sync/device-proof/challenge"):
            let json = #"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","# +
                #""expiresAt":"2026-09-05T08:35:00Z","keyEpoch":1}"#
            return (200, Data(json.utf8))
        case ("POST", "/sync/devices/enroll"):
            return try (201, NativeDeviceEnrollmentReceipt(
                deviceID: "018f4f45-cafe-7f00-9a82-e47805fb4d35",
                enrolledAt: "2026-09-23T00:00:00.000Z",
                protocolVersion: "0.0",
                userID: "original-account"
            ).jsonData())
        case ("PUT", "/sync/e2ee/recovery-envelope"):
            return EnrollmentCompletionURLProtocol.conflictingEnvelope
                ? (409, Data()) : (200, Data())
        case ("GET", "/sync/e2ee/recovery-envelope"):
            return try (200, RecoveryKeyEnvelope(
                aead: .aes256Gcm,
                ciphertext: "different-envelope",
                createdAt: "2026-09-23T00:00:00.000Z",
                info: .curfewRecoveryWrapV2,
                kdf: .hkdfSha256,
                keyEpoch: 1,
                nonce: "different-nonce",
                salt: "different-salt"
            ).jsonData())
        default:
            throw AccountOAuthEnrollmentError.invalidResponse
        }
    }
}

@MainActor
private struct CompletionOAuthFixture: AccountOAuthEnrolling {
    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        AccountOAuthGrant(
            tokens: AccountOAuthTokens(
                accessToken: "access-token",
                refreshToken: "refresh-token"
            ),
            state: "state",
            codeChallenge: "challenge",
            subjectID: "original-account"
        )
    }

    func cancelSignIn() {}
}

private final class EnrollmentCompletionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var observedPaths: [String] = []
    nonisolated(unsafe) static var observedErrors: [String] = []
    nonisolated(unsafe) static var conflictingEnvelope = false

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        Self.observedPaths.append("\(request.httpMethod ?? "nil") \(url.path)")
        do {
            let (status, data) = try handler(request)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            Self.observedErrors.append(String(describing: error))
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
