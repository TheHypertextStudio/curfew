@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class AccountEncryptedRecordWireTests: XCTestCase {
    private let deviceID = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testSettingsRecordsUseCanonicalLowSSignatures() throws {
        let store = AccountDeviceKeyStore(secretStore: NativeTransportMemorySecretStore())
        _ = try store.createEnrollment(deviceID: deviceID, keyEpoch: 1, createdAt: createdAt)
        let keys = try XCTUnwrap(store.load(deviceID: deviceID))
        let halfOrder = try XCTUnwrap(Data(base64Encoded:
            "f////4AAAAB//////////95zfVbTi89CedzlYX4xkqg="
        ))
        var noncanonical = 0
        for counter in 1 ... 64 {
            let record = try AccountRecordCrypto().seal(
                CurfewSettings.default,
                namespace: .accountSettings,
                recordID: UUID(),
                version: 1,
                writerCounter: counter,
                writerDeviceID: deviceID,
                keyEpoch: 1,
                updatedAt: createdAt,
                keys: keys
            )
            let base64 = record.signature.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/") + "=="
            let signature = try XCTUnwrap(Data(base64Encoded: base64))
            XCTAssertEqual(signature.count, 64)
            if halfOrder.lexicographicallyPrecedes(signature.suffix(32)) {
                noncanonical += 1
            }
        }
        XCTAssertEqual(noncanonical, 0, "Every record must use a low-S signature")
    }

    func testSettingsRecordEncodesAsTheSharedWireContract() throws {
        let store = AccountDeviceKeyStore(secretStore: NativeTransportMemorySecretStore())
        _ = try store.createEnrollment(deviceID: deviceID, keyEpoch: 1, createdAt: createdAt)
        let keys = try XCTUnwrap(store.load(deviceID: deviceID))
        let recordID = UUID()
        let record = try AccountRecordCrypto().seal(
            CurfewSettings.default,
            namespace: .accountSettings,
            recordID: recordID,
            version: 1,
            writerCounter: 1,
            writerDeviceID: deviceID,
            keyEpoch: 1,
            updatedAt: createdAt,
            keys: keys
        )

        let wire = try CurfewProtocols.EncryptedRecord(data: JSONEncoder().encode(record))

        XCTAssertEqual(wire.recordID, recordID.uuidString.lowercased())
        XCTAssertEqual(wire.writerDeviceID, deviceID.uuidString.lowercased())
        XCTAssertEqual(wire.namespace, .accountSettings)
    }
}
