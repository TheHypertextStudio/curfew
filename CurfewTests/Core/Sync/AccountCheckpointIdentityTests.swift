@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class AccountCheckpointIdentityTests: XCTestCase {
    private let deviceID = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testPendingRegistrationKeepsTheOriginalAccountForSafeReauthorization() throws {
        let checkpoint = AccountRecoverySetupCheckpoint(
            enrollment: AccountDeviceEnrollment(
                deviceID: deviceID,
                keyEpoch: 1,
                enrolledAt: createdAt
            ),
            recoveryKey: "recovery-key",
            recoveryEnvelope: recoveryEnvelopeFixture(),
            oauthState: "state",
            pkceChallenge: "challenge",
            accountUserID: "original-account",
            receiptData: nil
        )

        XCTAssertEqual(try checkpoint.expectedAccountUserID(), "original-account")
    }

    func testLegacyRegisteredCheckpointUsesTheCoordinatorReceiptForReauthorization() throws {
        let checkpoint = try AccountRecoverySetupCheckpoint(
            enrollment: AccountDeviceEnrollment(
                deviceID: deviceID,
                keyEpoch: 1,
                enrolledAt: createdAt
            ),
            recoveryKey: "recovery-key",
            recoveryEnvelope: recoveryEnvelopeFixture(),
            oauthState: "state",
            pkceChallenge: "challenge",
            receiptData: NativeDeviceEnrollmentReceipt(
                deviceID: deviceID.uuidString.lowercased(),
                enrolledAt: "2026-09-23T00:00:00.000Z",
                protocolVersion: "0.0",
                userID: "original-account"
            ).jsonData()
        )

        XCTAssertEqual(try checkpoint.expectedAccountUserID(), "original-account")
        let unanchored = AccountRecoverySetupCheckpoint(
            enrollment: checkpoint.enrollment,
            recoveryKey: checkpoint.recoveryKey,
            recoveryEnvelope: checkpoint.recoveryEnvelope,
            oauthState: checkpoint.oauthState,
            pkceChallenge: checkpoint.pkceChallenge,
            receiptData: nil
        )
        XCTAssertThrowsError(try unanchored.expectedAccountUserID())
    }

    func testDisplayingRecoveryKeyKeepsTheRegisteredDeviceReceipt() throws {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        let pending = AccountEnrollmentPendingStore(secretStore: secrets)
        let enrollment = AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: createdAt
        )
        try pending.saveDeviceRegistration(
            enrollment: enrollment,
            recoveryKey: "recovery-key",
            recoveryEnvelope: recoveryEnvelopeFixture(),
            oauthState: "state",
            pkceChallenge: "challenge",
            accountUserID: "original-account"
        )
        let receipt = try NativeDeviceEnrollmentReceipt(
            deviceID: deviceID.uuidString.lowercased(),
            enrolledAt: "2026-09-23T00:00:00.000Z",
            protocolVersion: "0.0",
            userID: "original-account"
        ).jsonData()
        try pending.saveRegistrationReceipt(receipt)

        try pending.save(enrollment: enrollment, recoveryKey: "recovery-key")

        XCTAssertEqual(try pending.loadRecoverySetup()?.receiptData, receipt)
        XCTAssertEqual(try pending.load(), .saveRecoveryKey("recovery-key", enrollment))
        try pending.markRecoveryKeySaved()
        XCTAssertEqual(try pending.load(), .finishRecoverySetup("recovery-key", enrollment))
    }

    func testExistingKeyRecoveryKeepsAccountIdentityWithoutTheGeneratedKey() throws {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        let pending = AccountEnrollmentPendingStore(secretStore: secrets)
        let enrollment = AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: createdAt
        )
        try pending.saveDeviceRegistration(
            enrollment: enrollment,
            recoveryKey: "new-generated-key",
            recoveryEnvelope: recoveryEnvelopeFixture(),
            oauthState: "state",
            pkceChallenge: "challenge",
            accountUserID: "original-account"
        )
        try pending.saveRegistrationReceipt(NativeDeviceEnrollmentReceipt(
            deviceID: deviceID.uuidString.lowercased(),
            enrolledAt: "2026-09-23T00:00:00.000Z",
            protocolVersion: "0.0",
            userID: "original-account"
        ).jsonData())
        let checkpoint = try XCTUnwrap(pending.loadRecoverySetup())

        try pending.saveExistingKeyRecovery(from: checkpoint)
        try pending.save(enrollment: enrollment, recoveryKey: nil)

        XCTAssertEqual(try pending.load(), .enterRecoveryKey(enrollment))
        XCTAssertEqual(
            try pending.loadExistingKeyRecovery()?.expectedAccountUserID(),
            "original-account"
        )
        XCTAssertNil(try pending.loadRecoverySetup())
        XCTAssertNil(try secrets.data(for: "pending-recovery-key"))
    }

    private func recoveryEnvelopeFixture() -> RecoveryKeyEnvelope {
        RecoveryKeyEnvelope(
            aead: .aes256Gcm,
            ciphertext: String(repeating: "A", count: 64),
            createdAt: "2026-08-10T14:00:00.000Z",
            info: .curfewRecoveryWrapV2,
            kdf: .hkdfSha256,
            keyEpoch: 1,
            nonce: String(repeating: "B", count: 16),
            salt: String(repeating: "C", count: 22)
        )
    }
}
