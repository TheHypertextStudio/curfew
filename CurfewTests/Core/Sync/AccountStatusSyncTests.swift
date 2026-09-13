@testable import Curfew
import Foundation
import XCTest

@MainActor
final class AccountStatusSyncTests: XCTestCase {
    func testAccountSyncPublishesStatusThroughTheEnrolledTransport() throws {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = RecordingAccountSyncTransport()
        let engine = AccountSyncEngine(transport: transport)
        let report = DeviceStatusReport(
            deviceID: deviceID.uuidString.lowercased(),
            phase: .working,
            timeZone: "America/Los_Angeles",
            scheduleDigest: String(repeating: "a", count: 64),
            statusVersion: 0,
            observedAt: observedAt,
            nextTransitionAt: nil,
            activeLockoutEndsAt: nil
        )

        engine.publishDeviceStatus(report, deviceID: deviceID)
        XCTAssertTrue(transport.statuses.isEmpty)

        engine.start(enrollment: AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: observedAt
        ))
        engine.publishDeviceStatus(report, deviceID: deviceID)

        XCTAssertEqual(transport.statuses.map(\.deviceID), [deviceID])
        XCTAssertEqual(transport.statuses.map(\.report), [report])
    }

    func testAccountSyncForwardsDaemonAuthenticatedRemoteResult() throws {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let transport = RecordingAccountSyncTransport()
        let engine = AccountSyncEngine(transport: transport)
        var received: RemoteCommandResult?
        engine.onRemoteCommandResultReceived = { received = $0 }
        engine.start(enrollment: AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        let result = RemoteCommandResult(
            commandID: UUID(),
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appliedDeadline: Date(timeIntervalSince1970: 1_800_000_900)
        )

        transport.send(result)

        XCTAssertEqual(received, result)
    }

    func testSuccessfulAuthenticatedPollMarksTheAccountConnectionSynchronized() throws {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_123)
        let transport = RecordingAccountSyncTransport()
        let engine = AccountSyncEngine(transport: transport)

        engine.start(enrollment: AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        XCTAssertEqual(engine.syncStatus, .connecting)

        transport.sendSuccessfulPoll(at: confirmedAt)

        XCTAssertEqual(engine.syncStatus, .synchronized(confirmedAt))
    }

    func testReadOnlyPollDoesNotClaimPendingEncryptedChangesWereSaved() throws {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let transport = RecordingAccountSyncTransport()
        let engine = AccountSyncEngine(transport: transport)
        engine.start(enrollment: AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        engine.noteLocalSettingsChanged()
        transport.sendSuccessfulPoll(at: Date(timeIntervalSince1970: 1_800_000_123))

        XCTAssertEqual(engine.syncStatus, .pendingEncryption)
    }

    func testNetworkFailureMarksTheAccountConnectionOffline() throws {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let transport = RecordingAccountSyncTransport()
        let engine = AccountSyncEngine(transport: transport)
        engine.start(enrollment: AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        transport.sendOffline()

        XCTAssertEqual(engine.syncStatus, .offline)
    }

    func testPendingEncryptedChangesSurviveOfflineRecovery() throws {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let transport = RecordingAccountSyncTransport()
        let engine = AccountSyncEngine(transport: transport)
        engine.start(enrollment: AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        engine.noteLocalSettingsChanged()
        transport.sendOffline()
        transport.sendSuccessfulPoll(at: Date(timeIntervalSince1970: 1_800_000_123))

        XCTAssertEqual(engine.syncStatus, .pendingEncryption)
    }

    func testPendingEncryptedChangesSurviveRejectedRecovery() throws {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let transport = RecordingAccountSyncTransport()
        let engine = AccountSyncEngine(transport: transport)
        engine.start(enrollment: AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        engine.noteLocalSettingsChanged()
        transport.sendRejected("Curfew needs you to sign in again.")
        transport.sendSuccessfulPoll(at: Date(timeIntervalSince1970: 1_800_000_123))

        XCTAssertEqual(engine.syncStatus, .pendingEncryption)
    }
}

@MainActor
private final class RecordingAccountSyncTransport: AccountSyncTransporting {
    struct Status: Equatable {
        let report: DeviceStatusReport
        let deviceID: UUID
    }

    private(set) var statuses: [Status] = []
    private var onRemoteCommandResult: ((RemoteCommandResult) -> Void)?
    private var onSynchronized: ((Date) -> Void)?
    private var onOffline: (() -> Void)?
    private var onFailure: ((String) -> Void)?

    func connect(deviceID _: UUID, callbacks: AccountSyncTransportCallbacks) {
        onSynchronized = callbacks.onSynchronized
        onOffline = callbacks.onOffline
        onFailure = callbacks.onFailure
        onRemoteCommandResult = callbacks.onRemoteCommandResult
    }

    func send(_ result: RemoteCommandResult) {
        onRemoteCommandResult?(result)
    }

    func sendSuccessfulPoll(at date: Date) {
        onSynchronized?(date)
    }

    func sendOffline() {
        onOffline?()
    }

    func sendRejected(_ reason: String) {
        onFailure?(reason)
    }

    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID) {
        statuses.append(Status(report: report, deviceID: deviceID))
    }

    func disconnect() {}
}
