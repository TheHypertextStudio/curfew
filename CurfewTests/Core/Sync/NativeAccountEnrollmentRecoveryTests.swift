@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testAmbiguousRegistrationResponseResumesTheExactDeviceWithoutOAuth() async throws {
        let fixture = try makeRecoveryFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let enrollmentStore = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("enrollment.json")
        )
        let service = makeEnrollmentService(fixture: fixture, enrollmentStore: enrollmentStore)
        let replay = RegistrationReplayRecorder()
        installAmbiguousRegistrationHandler(replay: replay)
        defer {
            RecoverySetupURLProtocol.handler = nil
            RecoverySetupURLProtocol.requestObserver = nil
        }

        let outcome = try await service.enroll(
            grant: recoveryTestGrant,
            deviceID: fixture.deviceID,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        guard case .finishDeviceRegistration(let recoveryKey, let enrollment) = outcome else {
            return XCTFail("expected pending device registration")
        }
        let checkpoint = try XCTUnwrap(
            AccountEnrollmentPendingStore(secretStore: fixture.secrets).loadRecoverySetup()
        )
        XCTAssertNil(checkpoint.receiptData)

        installRegistrationResumeHandler(deviceID: fixture.deviceID, replay: replay)
        let resumed = try await service.resumeDeviceRegistration(
            recoveryKey: recoveryKey,
            enrollment: enrollment
        )

        XCTAssertEqual(resumed, .saveRecoveryKey(recoveryKey, enrollment))
        XCTAssertEqual(try enrollmentStore.load()?.deviceID, fixture.deviceID)
    }

    func testDeviceRegistrationPersistsAResumableCheckpointBeforeRecoveryUpload() async throws {
        let fixture = try makeRecoveryFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let enrollmentStore = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("enrollment.json")
        )
        let events = RecoverySetupEventRecorder()
        installRecoveryUploadFailureHandler(fixture: fixture, events: events)
        defer { RecoverySetupURLProtocol.handler = nil }
        let service = makeEnrollmentService(
            fixture: fixture,
            enrollmentStore: enrollmentStore
        )

        let outcome = try await service.enroll(
            grant: recoveryTestGrant,
            deviceID: fixture.deviceID,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        guard case .finishRecoverySetup(let recoveryKey, let enrollment) = outcome else {
            return XCTFail("expected resumable recovery setup after registration")
        }
        XCTAssertFalse(recoveryKey.isEmpty)
        XCTAssertEqual(enrollment.deviceID, fixture.deviceID)
        XCTAssertEqual(events.values, ["challenge", "registered", "challenge", "recovery-upload"])
        XCTAssertEqual(try enrollmentStore.load()?.deviceID, fixture.deviceID)
        let pending = AccountEnrollmentPendingStore(secretStore: fixture.secrets)
        let checkpoint = try XCTUnwrap(pending.loadRecoverySetup())

        installRecoveryResumeHandler(checkpoint: checkpoint)
        let resumed = try await service.resumeRecoverySetup(
            recoveryKey: recoveryKey,
            enrollment: enrollment
        )

        XCTAssertEqual(resumed, .saveRecoveryKey(recoveryKey, enrollment))
        XCTAssertNil(try pending.loadRecoverySetup())
    }

    private var recoveryTestGrant: AccountOAuthGrant {
        AccountOAuthGrant(
            tokens: AccountOAuthTokens(
                accessToken: "resource-bound-access-token",
                refreshToken: "refresh-token"
            ),
            state: "state",
            codeChallenge: "challenge"
        )
    }

    private func makeEnrollmentService(
        fixture: (deviceID: UUID, secrets: RecoverySetupMemorySecretStore),
        enrollmentStore: RemoteCommandEnrollmentStore
    ) -> NativeAccountDeviceEnrollmentService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoverySetupURLProtocol.self]
        return NativeAccountDeviceEnrollmentService(
            secretStore: fixture.secrets,
            session: URLSession(configuration: configuration),
            endpoints: .staging,
            remoteCommandEnrollmentStore: enrollmentStore
        )
    }

    private func installRecoveryUploadFailureHandler(
        fixture: (deviceID: UUID, secrets: RecoverySetupMemorySecretStore),
        events: RecoverySetupEventRecorder
    ) {
        RecoverySetupURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                events.append("challenge")
                return Self.recoveryChallengeResponse()
            case ("POST", "/sync/devices/enroll"):
                events.append("registered")
                return try (200, NativeDeviceEnrollmentReceipt(
                    deviceID: fixture.deviceID.uuidString.lowercased(),
                    enrolledAt: "2026-09-05T08:30:00.000Z",
                    protocolVersion: "0.0",
                    userID: "account_018f4f45cafe7f009a82e47805fb4d34"
                ).jsonData())
            case ("PUT", "/sync/e2ee/recovery-envelope"):
                events.append("recovery-upload")
                return (503, Data())
            default:
                XCTFail("unexpected request: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
    }

    private func installRecoveryResumeHandler(checkpoint: AccountRecoverySetupCheckpoint) {
        RecoverySetupURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            if path == "/api/auth/oauth2/token" {
                let json = #"{"access_token":"fresh-access-token","# +
                    #""refresh_token":"fresh-refresh-token","token_type":"Bearer"}"#
                return (200, Data(json.utf8))
            }
            if authorization == "Bearer resource-bound-access-token" {
                return (401, Data())
            }
            XCTAssertEqual(authorization, "Bearer fresh-access-token")
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                return Self.recoveryChallengeResponse()
            case ("PUT", "/sync/e2ee/recovery-envelope"):
                return (409, Data())
            case ("GET", "/sync/e2ee/recovery-envelope"):
                return try (200, checkpoint.recoveryEnvelope.jsonData())
            default:
                XCTFail("unexpected resume request: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
    }

    private func installAmbiguousRegistrationHandler(replay: RegistrationReplayRecorder) {
        var challengeCount = 0
        RecoverySetupURLProtocol.requestObserver = { request in
            guard request.url?.path == "/sync/devices/enroll",
                  let body = request.httpBody else { return }
            replay.originalIdentity = try? Self.enrollmentReplayIdentity(body)
        }
        RecoverySetupURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                challengeCount += 1
                return Self.recoveryChallengeResponse()
            case ("POST", "/sync/devices/enroll"):
                XCTAssertEqual(challengeCount, 1)
                return (503, Data())
            default:
                XCTFail("unexpected registration request: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
    }

    private func installRegistrationResumeHandler(
        deviceID: UUID,
        replay: RegistrationReplayRecorder
    ) {
        RecoverySetupURLProtocol.requestObserver = { request in
            guard request.url?.path == "/sync/devices/enroll",
                  let body = request.httpBody else { return }
            XCTAssertEqual(try? Self.enrollmentReplayIdentity(body), replay.originalIdentity)
        }
        RecoverySetupURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                return Self.recoveryChallengeResponse()
            case ("POST", "/sync/devices/enroll"):
                return try (201, NativeDeviceEnrollmentReceipt(
                    deviceID: deviceID.uuidString.lowercased(),
                    enrolledAt: "2027-01-15T08:00:00.000Z",
                    protocolVersion: "0.0",
                    userID: "account_018f4f45cafe7f009a82e47805fb4d34"
                ).jsonData())
            case ("PUT", "/sync/e2ee/recovery-envelope"):
                return (200, Data())
            default:
                XCTFail("unexpected registration resume: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
    }

    private func makeRecoveryFixture() throws
        -> (deviceID: UUID, secrets: RecoverySetupMemorySecretStore) {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let secrets = RecoverySetupMemorySecretStore()
        try secrets.save(
            Data("resource-bound-access-token".utf8),
            for: "oauth-access-token"
        )
        try secrets.save(Data("refresh-token".utf8), for: "oauth-refresh-token")
        try secrets.save(Data("curfew-native-client".utf8), for: "oauth-client-id")
        return (deviceID, secrets)
    }

    private static func recoveryChallengeResponse() -> (Int, Data) {
        let json = #"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","# +
            #""expiresAt":"2026-09-05T08:35:00Z","keyEpoch":1}"#
        return (200, Data(json.utf8))
    }

    private static func enrollmentReplayIdentity(_ body: Data) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        object.removeValue(forKey: "coordinatorNonce")
        object.removeValue(forKey: "deviceProof")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private final class RegistrationReplayRecorder: @unchecked Sendable {
    var originalIdentity: Data?
}

private final class RecoverySetupURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requestObserver: ((URLRequest) -> Void)?

    override static func canInit(with request: URLRequest) -> Bool {
        requestObserver?(request)
        return true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (status, data) = try handler(request)
            let response = try XCTUnwrap(try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class RecoverySetupMemorySecretStore: AccountSecretStoring {
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        values.removeValue(forKey: account)
    }
}

private final class RecoverySetupEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
