import CryptoKit
@testable import Curfew
import Foundation
import Testing

struct RemoteCommandVerifierTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let deviceID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!

    @Test("Signed remote envelope uses the protocol compactJws JSON key")
    func envelopeUsesProtocolJSONKey() throws {
        let envelope = SignedRemoteLockoutCommandEnvelope(compactJWS: "header.payload.signature")
        let data = try JSONEncoder().encode(envelope)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["compactJws": "header.payload.signature"])
        let wireData = Data(#"{"compactJws":"header.payload.signature"}"#.utf8)
        #expect(try JSONDecoder()
            .decode(SignedRemoteLockoutCommandEnvelope.self, from: wireData) == envelope)
    }

    @Test("Remote verifier accepts an ES256 command for its enrolled device")
    func acceptsValidES256Command() throws {
        let fixture = try makeFixture()
        let record = try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        #expect(record.lockoutID == fixture.commandID)
        #expect(record.scheduledUnlockAt == now.addingTimeInterval(300))
    }

    @Test("Daemon fetches command keys only from the configured public JWKS endpoint")
    func fetchesTrustedCoordinatorJWKS() throws {
        let key = P256.Signing.PrivateKey()
        let expected = RemoteCommandJWKS(keys: [
            RemoteCommandJWK(keyID: "coordinator-key", publicKey: key.publicKey)
        ])
        RemoteJWKSURLProtocol.handler = { request in
            #expect(
                request.url?.absoluteString
                    == "https://curfew-sync.hypertext.studio/.well-known/curfew-command-jwks.json"
            )
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return try (200, JSONEncoder().encode(expected))
        }
        defer { RemoteJWKSURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteJWKSURLProtocol.self]
        let provider = try HTTPRemoteCommandJWKSProvider(
            endpoint: #require(URL(
                string: "https://curfew-sync.hypertext.studio/.well-known/curfew-command-jwks.json"
            )),
            session: URLSession(configuration: configuration)
        )

        let fetched = try provider.jwks()

        #expect(fetched.keys == expected.keys)
    }

    @Test("Daemon consumes a delivery only after verified state commits")
    func daemonConsumesOnlyAfterVerifiedCommit() throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = RemoteCommandInboxStore(
            directoryURL: root.appendingPathComponent("inbox", isDirectory: true)
        )
        let state = DaemonRemoteCommandStateStore(
            stateURL: root.appendingPathComponent("state.json")
        )
        let delivery = try PendingRemoteCommandDelivery(
            cursor: "cursor_018f4f45cafe7f009a82e47805fb4d34",
            envelope: JSONDecoder().decode(
                SignedRemoteLockoutCommandEnvelope.self,
                from: fixture.envelope
            )
        )
        try inbox.stage(delivery)
        let processor = DaemonRemoteCommandProcessor(
            inboxStore: inbox,
            verifier: fixture.verifier,
            controller: DaemonRemoteCommandController(store: state)
        )

        let receipts = try processor.processPending(at: now)

        #expect(receipts.map(\.cursor) == [delivery.cursor])
        #expect(receipts.map(\.result.commandID) == [fixture.commandID])
        #expect(try inbox.pendingDeliveries().isEmpty)
        #expect(
            try state.load().activeLockout?.scheduledUnlockAt
                == now.addingTimeInterval(300)
        )
    }

    @Test("Forged inbox input cannot block a later authenticated command")
    func daemonDropsForgedInputWithoutBlockingValidDelivery() throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = RemoteCommandInboxStore(
            directoryURL: root.appendingPathComponent("inbox", isDirectory: true)
        )
        let state = DaemonRemoteCommandStateStore(
            stateURL: root.appendingPathComponent("state.json")
        )
        try inbox.stage(PendingRemoteCommandDelivery(
            cursor: "forged_cursor_018f4f45cafe7f009a82e47805fb4d34",
            envelope: SignedRemoteLockoutCommandEnvelope(
                compactJWS: "forged.payload.signature"
            )
        ))
        try inbox.stage(PendingRemoteCommandDelivery(
            cursor: "valid_cursor_018f4f45cafe7f009a82e47805fb4d34",
            envelope: JSONDecoder().decode(
                SignedRemoteLockoutCommandEnvelope.self,
                from: fixture.envelope
            )
        ))
        let processor = DaemonRemoteCommandProcessor(
            inboxStore: inbox,
            verifier: fixture.verifier,
            controller: DaemonRemoteCommandController(store: state)
        )

        let receipts = try processor.processPending(at: now)

        #expect(receipts.map(\.result.commandID) == [fixture.commandID])
        #expect(try inbox.pendingDeliveries().isEmpty)
        #expect(try state.load().activeLockout?.kind == .remoteCommand)
    }

    @Test("Authentication alone does not consume a command before enforcement commits")
    func verificationIsSideEffectFree() throws {
        let fixture = try makeFixture()
        let first = try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        let retry = try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        #expect(first == retry)
    }

    @Test(
        "Remote verifier accepts long locks with five-minute delivery validity",
        arguments: [300, 3600, 43200]
    )
    func acceptsSupportedCoordinatorLifetime(seconds: Int) throws {
        let fixture = try makeFixture(
            durationSeconds: seconds,
            expiresAt: now.addingTimeInterval(270)
        )
        let record = try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        #expect(record.lockoutID == fixture.commandID)
        #expect(record.scheduledUnlockAt == now.addingTimeInterval(TimeInterval(seconds)))
    }

    @Test("Remote verifier rejects an envelope exceeding five-minute delivery validity")
    func rejectsExcessiveCoordinatorLifetime() throws {
        let fixture = try makeFixture(
            durationSeconds: 43200,
            expiresAt: now.addingTimeInterval(271)
        )
        #expect(throws: RemoteCommandVerificationError.invalidClock) {
            try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        }
    }

    @Test("Remote verifier rejects an invalid ES256 signature")
    func rejectsInvalidES256Signature() throws {
        let fixture = try makeFixture(tamperSignature: true)
        #expect(throws: RemoteCommandVerificationError.invalidSignature) {
            try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        }
    }

    @Test("Remote verifier rejects a JWS key absent from the coordinator JWKS")
    func rejectsJWKSKeyMismatch() throws {
        let fixture = try makeFixture(includeSigningKey: false)
        #expect(throws: RemoteCommandVerificationError.unknownKey) {
            try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        }
    }

    @Test("Remote verifier rejects a command for another coordinator audience")
    func rejectsWrongAudience() throws {
        let fixture = try makeFixture(audience: "another-device-agent")
        #expect(throws: RemoteCommandVerificationError.invalidAudience) {
            try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        }
    }

    @Test("Remote verifier rejects an expired command")
    func rejectsExpiredEnvelope() throws {
        let fixture = try makeFixture(expiresAt: now.addingTimeInterval(-1))
        #expect(throws: RemoteCommandVerificationError.expired) {
            try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        }
    }

    @Test("Remote verifier rejects a command for a different device")
    func rejectsNonTargetDevice() throws {
        let fixture = try makeFixture(targetDeviceID: UUID())
        #expect(throws: RemoteCommandVerificationError.nonTargetDevice) {
            try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        }
    }

    @Test("Remote verifier rejects a signed command for a different enrolled account")
    func rejectsNonEnrolledAccount() throws {
        let fixture = try makeFixture(targetUserID: "other-account")
        #expect(throws: RemoteCommandVerificationError.invalidCommand) {
            try fixture.verifier.verifiedLockoutRecord(envelope: fixture.envelope, at: now)
        }
    }

    private func makeFixture(
        audience: String = "curfew-device-agent",
        durationSeconds: Int = 300,
        expiresAt: Date? = nil,
        includeSigningKey: Bool = true,
        sequence: Int64 = 1,
        tamperSignature: Bool = false,
        targetDeviceID: UUID? = nil,
        targetUserID: String = "remote-command-user"
    ) throws -> RemoteCommandVerifierFixture {
        let privateKey = P256.Signing.PrivateKey()
        let keyID = "remote-command-test-key"
        let commandID = UUID()
        let payload = RemoteLockoutCommandPayload(
            commandID: commandID,
            idempotencyKey: String(repeating: "I", count: 22),
            userID: targetUserID,
            deviceID: targetDeviceID ?? deviceID,
            sequence: sequence,
            deadlinePolicy: .fixedDuration(seconds: durationSeconds),
            issuedAt: now.addingTimeInterval(-30),
            expiresAt: expiresAt ?? now.addingTimeInterval(60),
            nonce: String(repeating: "N", count: 22),
            coordinatorAudience: audience,
            statusVersion: 4,
            scheduleDigest: String(repeating: "S", count: 43)
        )
        var compactJWS = try RemoteCommandJWSTestSupport.sign(
            payload: payload,
            privateKey: privateKey,
            keyID: keyID
        )
        if tamperSignature {
            compactJWS = RemoteCommandJWSTestSupport.tamper(compactJWS)
        }
        let verifier = try RemoteCommandVerifier(
            configuration: RemoteCommandVerifierConfiguration(
                userID: "remote-command-user",
                deviceID: deviceID
            ),
            jwksProvider: StaticRemoteCommandJWKSProvider(
                keys: includeSigningKey
                    ? [RemoteCommandJWK(keyID: keyID, publicKey: privateKey.publicKey)]
                    : []
            )
        )
        return try RemoteCommandVerifierFixture(
            verifier: verifier,
            envelope: JSONEncoder().encode(
                SignedRemoteLockoutCommandEnvelope(compactJWS: compactJWS)
            ),
            commandID: commandID
        )
    }
}

private final class RemoteJWKSURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, data) = try handler(request)
            let requestURL = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: requestURL,
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

private struct RemoteCommandVerifierFixture {
    let verifier: RemoteCommandVerifier
    let envelope: Data
    let commandID: UUID
}

private struct StaticRemoteCommandJWKSProvider: RemoteCommandJWKSProvider {
    let keys: [RemoteCommandJWK]
    func jwks() throws -> RemoteCommandJWKS {
        RemoteCommandJWKS(keys: keys)
    }
}

private enum RemoteCommandJWSTestSupport {
    static func sign(
        payload: RemoteLockoutCommandPayload,
        privateKey: P256.Signing.PrivateKey,
        keyID: String
    ) throws -> String {
        let header = try JSONSerialization.data(
            withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "curfew-command+jwt"],
            options: [.sortedKeys]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(payload)
        let signingInput = "\(base64URL(header)).\(base64URL(body))"
        let signature = try privateKey.signature(for: Data(signingInput.utf8)).rawRepresentation
        return "\(signingInput).\(base64URL(signature))"
    }

    static func tamper(_ compactJWS: String) -> String {
        let parts = compactJWS.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return compactJWS }
        let replacement = parts[2].first == "A" ? "B" : "A"
        return "\(parts[0]).\(parts[1]).\(replacement)\(parts[2].dropFirst())"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
