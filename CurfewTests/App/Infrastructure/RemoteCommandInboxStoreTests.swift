@testable import Curfew
import Foundation
import Testing

struct RemoteCommandInboxStoreTests {
    private let deviceID = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!

    @Test("Authenticated account binding survives app and daemon restarts")
    func enrollmentBindingRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("enrollment.json")
        )
        let enrollment = try RemoteCommandEnrollment(
            userID: "account_018f4f45cafe7f009a82e47805fb4d34",
            deviceID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35"))
        )

        try store.save(enrollment)

        #expect(try store.load() == enrollment)
    }

    @Test("Repeated coordinator delivery creates one durable opaque inbox item")
    func repeatedDeliveryIsDurablyDeduplicated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RemoteCommandInboxStore(directoryURL: directory)
        let delivery = PendingRemoteCommandDelivery(
            cursor: "cursor_018f4f45cafe7f009a82e47805fb4d34",
            envelope: SignedRemoteLockoutCommandEnvelope(
                compactJWS: "header.payload.signature"
            )
        )

        try store.stage(delivery)
        try store.stage(delivery)

        #expect(try store.pendingDeliveries() == [delivery])
    }

    @Test("Daemon results and app acknowledgements survive either process restarting")
    func resultExchangeRoundTripsDurably() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent(
                "result-acknowledgements",
                isDirectory: true
            )
        )
        let result = try RemoteCommandResult(
            commandID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")),
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appliedDeadline: Date(timeIntervalSince1970: 1_800_000_900)
        )
        let acknowledgement = RemoteCommandResultIdentity(result: result)

        try store.publish([result])
        #expect(try store.pendingResults() == [result])

        try store.acknowledge(acknowledgement)
        try store.acknowledge(acknowledgement)
        #expect(try store.pendingAcknowledgements() == [acknowledgement])

        try store.removeAcknowledgement(acknowledgement)
        #expect(try store.pendingAcknowledgements().isEmpty)
    }

    @Test("A malformed acknowledgement cannot block a later exact acknowledgement")
    func malformedAcknowledgementIsQuarantined() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let acknowledgements = root.appendingPathComponent("ack", isDirectory: true)
        let store = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: acknowledgements
        )
        let identity = try RemoteCommandResultIdentity(
            commandID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")),
            deviceID: deviceID,
            sequence: 7
        )
        try store.acknowledge(identity)
        try Data("not-json".utf8).write(
            to: acknowledgements.appendingPathComponent("000-malformed.json")
        )

        #expect(try store.pendingAcknowledgements() == [identity])
        #expect(!FileManager.default.fileExists(
            atPath: acknowledgements.appendingPathComponent("000-malformed.json").path
        ))
    }
}
