import CryptoKit
@testable import Curfew
import Foundation
import Testing

struct RemoteCommandVerifierTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let deviceID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
}

extension RemoteCommandVerifierTests {
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

    @Test("Daemon reuses one JWKS snapshot within the bounded cache window")
    func cachesCoordinatorJWKS() throws {
        let key = P256.Signing.PrivateKey()
        let expected = RemoteCommandJWKS(keys: [
            RemoteCommandJWK(keyID: "coordinator-key", publicKey: key.publicKey)
        ])
        var requestCount = 0
        RemoteJWKSURLProtocol.handler = { _ in
            requestCount += 1
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

        _ = try provider.jwks()
        _ = try provider.jwks()

        #expect(requestCount == 1)
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
            controller: DaemonRemoteCommandController(
                store: state,
                eligibility: RemoteCommandEligibilitySnapshot(
                    statusVersion: 4,
                    scheduleDigest: String(repeating: "S", count: 43)
                )
            )
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
            controller: DaemonRemoteCommandController(
                store: state,
                eligibility: RemoteCommandEligibilitySnapshot(
                    statusVersion: 4,
                    scheduleDigest: String(repeating: "S", count: 43)
                )
            )
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

    @Test("A bounded batch is applied in authenticated sequence order, never filename order")
    func appliesAuthenticatedSequenceOrder() throws {
        let key = P256.Signing.PrivateKey()
        let keyID = "remote-command-order-key"
        let verifier = try RemoteCommandVerifier(
            configuration: RemoteCommandVerifierConfiguration(
                userID: "remote-command-user",
                deviceID: deviceID
            ),
            jwksProvider: StaticRemoteCommandJWKSProvider(keys: [
                RemoteCommandJWK(keyID: keyID, publicKey: key.publicKey)
            ])
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = DaemonRemoteCommandStateStore(stateURL: root.appendingPathComponent("state"))
        let processor = DaemonRemoteCommandProcessor(
            inboxStore: RemoteCommandInboxStore(directoryURL: root.appendingPathComponent("inbox")),
            verifier: verifier,
            controller: DaemonRemoteCommandController(
                store: state,
                eligibility: RemoteCommandEligibilitySnapshot(
                    statusVersion: 4,
                    scheduleDigest: String(repeating: "S", count: 43)
                )
            )
        )
        let sequenceTwo = try delivery(
            cursor: "filename-sorts-first",
            sequence: 2,
            duration: 300,
            key: key,
            keyID: keyID
        )
        let sequenceOne = try delivery(
            cursor: "filename-sorts-last",
            sequence: 1,
            duration: 3600,
            key: key,
            keyID: keyID
        )

        let receipts = try processor.process([sequenceTwo, sequenceOne], at: now)

        #expect(receipts.map(\.result.sequence) == [1, 2])
        #expect(try state.load().highestSequence == 2)
        #expect(try state.load().activeLockout?.scheduledUnlockAt == now.addingTimeInterval(3600))
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
}

private extension RemoteCommandVerifierTests {
    func delivery(
        cursor: String,
        sequence: Int64,
        duration: Int,
        key: P256.Signing.PrivateKey,
        keyID: String
    ) throws -> PendingRemoteCommandDelivery {
        let payload = RemoteLockoutCommandPayload(
            commandID: UUID(),
            idempotencyKey: "key_\(sequence)_abcdefghijklmnopq",
            userID: "remote-command-user",
            deviceID: deviceID,
            sequence: sequence,
            deadlinePolicy: .fixedDuration(seconds: duration),
            issuedAt: now.addingTimeInterval(-30),
            expiresAt: now.addingTimeInterval(60),
            nonce: "nonce_\(sequence)_abcdefghijklmnopq",
            coordinatorAudience: "curfew-device-agent",
            statusVersion: 4,
            scheduleDigest: String(repeating: "S", count: 43)
        )
        return try PendingRemoteCommandDelivery(
            cursor: cursor,
            envelope: SignedRemoteLockoutCommandEnvelope(
                compactJWS: RemoteCommandJWSTestSupport.sign(
                    payload: payload,
                    privateKey: key,
                    keyID: keyID
                )
            )
        )
    }

    func makeFixture(
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
            scheduleDigest: String(repeating: "S", count: 43),
            kind: "lock_device"
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
