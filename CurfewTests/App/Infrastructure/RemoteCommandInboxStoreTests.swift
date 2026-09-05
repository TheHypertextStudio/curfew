import CryptoKit
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

    @Test("Daemon rejects a partial oversized batch and drops a FIFO without opening it")
    func inboxBatchIsBoundedAndNonblocking() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RemoteCommandInboxStore(directoryURL: directory)
        for index in 0 ..< 33 {
            try store.stage(PendingRemoteCommandDelivery(
                cursor: "cursor_\(index)_abcdefghijklmnopq",
                envelope: SignedRemoteLockoutCommandEnvelope(
                    compactJWS: "header.payload.signature"
                )
            ))
        }
        #expect(try store.pendingDeliveries().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        let delivery = PendingRemoteCommandDelivery(
            cursor: "cursor_fifo_abcdefghijklmnopq",
            envelope: SignedRemoteLockoutCommandEnvelope(
                compactJWS: "header.payload.signature"
            )
        )
        try store.stage(delivery)

        let entry = try #require(FileManager.default.contentsOfDirectory(atPath: directory.path)
            .first)
        let file = directory.appendingPathComponent(entry)
        try FileManager.default.removeItem(at: file)
        #expect(mkfifo(file.path, 0o600) == 0)

        #expect(try store.pendingDeliveries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("A filename whose embedded cursor points elsewhere is removed")
    func embeddedCursorMustMatchEnumeratedFilename() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = RemoteCommandInboxStore(directoryURL: directory)
        let embeddedCursor = "cursor_embedded_abcdefghijklmnopq"
        let enumeratedCursor = "cursor_enumerated_abcdefghijklmnopq"
        let delivery = PendingRemoteCommandDelivery(
            cursor: embeddedCursor,
            envelope: SignedRemoteLockoutCommandEnvelope(
                compactJWS: "header.payload.invalid-signature"
            )
        )
        let data = try JSONEncoder().encode(delivery)
        let poisonedURL = directory.appendingPathComponent(entryName(for: enumeratedCursor))
        try data.write(to: poisonedURL)

        #expect(try store.pendingDeliveries() == [])
        #expect(!FileManager.default.fileExists(atPath: poisonedURL.path))
    }

    @Test(
        "An oversized poison prefix is discarded in bounded batches and cannot starve a redelivery"
    )
    func poisonPrefixCannotPermanentlyStarveCommands() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = RemoteCommandInboxStore(directoryURL: directory)
        let legitimate = PendingRemoteCommandDelivery(
            cursor: "cursor_legitimate_abcdefghijklmnopq",
            envelope: SignedRemoteLockoutCommandEnvelope(
                compactJWS: "header.payload.signature"
            )
        )
        for index in 0 ..< 96 {
            let poison = PendingRemoteCommandDelivery(
                cursor: "cursor_elsewhere_\(index)_abcdefghijklmnopq",
                envelope: SignedRemoteLockoutCommandEnvelope(
                    compactJWS: "header.payload.invalid-signature"
                )
            )
            try JSONEncoder().encode(poison).write(
                to: directory.appendingPathComponent(
                    String(format: "%064x.json", index)
                )
            )
        }

        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).count
        #expect(try store.pendingDeliveries().isEmpty)
        let afterOneBoundedPass = try FileManager.default
            .contentsOfDirectory(atPath: directory.path).count
        #expect(before - afterOneBoundedPass <= 33)
        #expect(afterOneBoundedPass < before)

        while try !FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty {
            #expect(try store.pendingDeliveries().isEmpty)
        }
        try store.stage(legitimate)
        #expect(try store.pendingDeliveries() == [legitimate])
    }

    @Test("Oversized nested directories are quarantined and cannot monopolize every daemon pass")
    func directoryPoisonCannotPermanentlyStarveCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent("inbox", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = RemoteCommandInboxStore(directoryURL: directory)
        for index in 0 ..< 33 {
            let poison = directory.appendingPathComponent(
                String(format: "%064x.json", index),
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: poison, withIntermediateDirectories: true)
            try Data("nested".utf8).write(to: poison.appendingPathComponent("payload"))
        }

        #expect(try store.pendingDeliveries().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        let legitimate = PendingRemoteCommandDelivery(
            cursor: "cursor_after_directory_poison_abcdefghijklmnopq",
            envelope: SignedRemoteLockoutCommandEnvelope(
                compactJWS: "header.payload.signature"
            )
        )
        try store.stage(legitimate)
        #expect(try store.pendingDeliveries() == [legitimate])
    }
}

extension RemoteCommandInboxStoreTests {
    @Test("Daemon results and coordinator-signed receipts survive either process restarting")
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
        let receipt = CoordinatorSignedRemoteCommandResultReceiptEnvelope(
            compactJWS: "header.payload.signature"
        )

        try store.publish([result])
        #expect(try store.pendingResults() == [result])

        try store.recordReceipt(receipt, for: result)
        try store.recordReceipt(receipt, for: result)
        #expect(try store.pendingReceipt(for: result) == receipt)

        try store.removeReceipt(for: result)
        #expect(try store.pendingReceipt(for: result) == nil)
    }

    @Test("App can acknowledge through a write-and-search-only daemon directory")
    func appAcknowledgesWithoutDirectoryReadPermission() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let acknowledgements = root.appendingPathComponent("ack", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: acknowledgements.path
            )
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(
            at: acknowledgements,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o300]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o300],
            ofItemAtPath: acknowledgements.path
        )
        let store = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: acknowledgements
        )
        let result = try RemoteCommandResult(
            commandID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")),
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appliedDeadline: Date(timeIntervalSince1970: 1_800_000_900)
        )

        try store.recordReceipt(
            CoordinatorSignedRemoteCommandResultReceiptEnvelope(
                compactJWS: "header.payload.signature"
            ),
            for: result
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: acknowledgements.path
        )
        #expect(try store.pendingReceipt(for: result)?.compactJWS == "header.payload.signature")
    }

    @Test("A malformed exact receipt is removed without suppressing its pending result")
    func malformedAcknowledgementIsQuarantined() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let acknowledgements = root.appendingPathComponent("ack", isDirectory: true)
        let store = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: acknowledgements
        )
        let result = try RemoteCommandResult(
            commandID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")),
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appliedDeadline: Date(timeIntervalSince1970: 1_800_000_900)
        )
        try store.publish([result])
        let malformed = store.receiptURL(for: result)
        try FileManager.default.createDirectory(
            at: acknowledgements,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: malformed)

        #expect(try store.pendingReceipt(for: result) == nil)
        #expect(!FileManager.default.fileExists(atPath: malformed.path))
        #expect(try store.pendingResults() == [result])
    }

    @Test("An exact FIFO receipt is removed without blocking or clearing the result")
    func receiptFIFOCannotBlockDaemon() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true)
        )
        let result = try RemoteCommandResult(
            commandID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")),
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appliedDeadline: Date(timeIntervalSince1970: 1_800_000_900)
        )
        try store.publish([result])
        let fifo = store.receiptURL(for: result)
        #expect(mkfifo(fifo.path, 0o600) == 0)

        #expect(try store.pendingReceipt(for: result) == nil)
        #expect(!FileManager.default.fileExists(atPath: fifo.path))
        #expect(try store.pendingResults() == [result])
    }

    @Test("Daemon never traverses an acknowledgement-directory symlink")
    func acknowledgementDirectorySymlinkCannotEscapeExchangeRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let victim = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: victim)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        let victimFile = victim.appendingPathComponent(String(repeating: "a", count: 64) + ".json")
        try Data("not-json".utf8).write(to: victimFile)
        let acknowledgements = root.appendingPathComponent("ack", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: acknowledgements, withDestinationURL: victim)
        let store = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: acknowledgements
        )
        let result = try RemoteCommandResult(
            commandID: #require(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")),
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appliedDeadline: Date(timeIntervalSince1970: 1_800_000_900)
        )

        #expect(throws: RemoteCommandResultExchangeError.unsafeFilesystemEntry) {
            try store.pendingReceipt(for: result)
        }
        #expect(FileManager.default.fileExists(atPath: victimFile.path))
    }

    @Test("Production exchange rejects a directory not owned by root")
    func productionExchangeRejectsNonRootOwner() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true),
            requiredDirectoryOwnerUserID: 0
        )

        #expect(throws: RemoteCommandResultExchangeError.unsafeFilesystemEntry) {
            try store.pendingResults()
        }
    }

    @Test("App refuses a daemon-result symlink instead of trusting forged terminal state")
    func resultSymlinkCannotForgeDaemonOutput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let forged = root.appendingPathComponent("forged.json")
        try Data("[]".utf8).write(to: forged)
        let results = root.appendingPathComponent("results.json")
        try FileManager.default.createSymbolicLink(at: results, withDestinationURL: forged)
        let store = RemoteCommandResultExchangeStore(
            resultsURL: results,
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true)
        )

        #expect(throws: RemoteCommandResultExchangeError.unsafeFilesystemEntry) {
            try store.pendingResults()
        }
    }
}

private func entryName(for cursor: String) -> String {
    let digest = SHA256.hash(data: Data(cursor.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    return "\(digest).json"
}
