import CurfewKit
import Darwin
import Foundation
import XCTest

final class RemoteCommandEnrollmentStoreTests: XCTestCase {
    func testMalformedSavedIdentityHasTerminalStoreError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("enrollment.json")
        try Data("{not valid json".utf8).write(to: recordURL)

        XCTAssertThrowsError(try RemoteCommandEnrollmentStore(recordURL: recordURL)
            .load()) { error in
                XCTAssertTrue(error is RemoteCommandEnrollmentStoreError)
            }
    }

    func testOversizedSavedIdentityHasTerminalStoreError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("enrollment.json")
        try Data(repeating: 0x41, count: 65537).write(to: recordURL)

        XCTAssertThrowsError(try RemoteCommandEnrollmentStore(recordURL: recordURL)
            .load()) { error in
                XCTAssertTrue(error is RemoteCommandEnrollmentStoreError)
            }
    }

    func testUnsafeSavedIdentityEntryHasTerminalStoreError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("enrollment.json")
        try FileManager.default.createDirectory(at: recordURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try RemoteCommandEnrollmentStore(recordURL: recordURL)
            .load()) { error in
                XCTAssertTrue(error is RemoteCommandEnrollmentStoreError)
            }
    }

    func testTemporarilyUnreadableRegularIdentityStaysRetryable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("enrollment.json")
        let store = RemoteCommandEnrollmentStore(recordURL: recordURL)
        try store.save(RemoteCommandEnrollment(userID: "owner", deviceID: UUID()))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: recordURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: recordURL.path
            )
        }

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? BoundedRegularFileReadError, .openFailed(EACCES))
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recordURL.path
        )
        XCTAssertNotNil(try store.load())
    }
}
