@testable import CurfewKit
import Foundation
import Testing

/// Contracts awaiting execution against the intentionally inert storage scaffold.
struct RestCompanionPresentationStoreTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private enum WriteFailure: Error { case injected }

    private final class Storage {
        var bytes: [RestCompanionPresentationStore.Slot: Data] = [:]
        var writes: [(RestCompanionPresentationStore.Slot, Data)] = []
        var limits: [(RestCompanionPresentationStore.Slot, Int)] = []
        var inspections = 0
        var failNextWrite: RestCompanionPresentationStore.Slot?

        func store() -> RestCompanionPresentationStore {
            RestCompanionPresentationStore(read: { slot, maximumBytes in
                self.limits.append((slot, maximumBytes))
                return self.bytes[slot]
            }, write: { slot, data in
                if self.failNextWrite == slot {
                    self.failNextWrite = nil
                    throw WriteFailure.injected
                }
                self.writes.append((slot, data))
                self.bytes[slot] = data
            }, inspectImageHeader: { _ in
                self.inspections += 1
                return .init(width: 1280, height: 720)
            })
        }
    }

    private func snapshot(
        message: String = "Evening",
        offset: Double = 0,
        expiryOffset: Double = 0
    ) -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(3600 + offset + expiryOffset),
            appearance: RestAppearancePreferences(
                background: .image, message: message,
                ownedImageFilename: "51000000-0000-0000-0000-000000000001.jpg",
                saverMessageEnabled: true, sunriseWakeEnabled: true,
                sunriseOnBatteryEnabled: true
            ),
            lockDate: now.addingTimeInterval(-3600 + offset),
            unlockDate: now.addingTimeInterval(1800 + offset)
        )
    }

    @Test("Repeated clock refreshes do not write either storage slot")
    func clockTicksDoNotWrite() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        #expect(storage.writes.count == 2)
        storage.writes.removeAll()
        for _ in 0 ..< 60 {
            try store.publish(snapshot: snapshot(), imageData: Data([1]))
        }
        #expect(storage.writes.isEmpty)
    }

    @Test("Occurrence boundary changes write only tiny metadata referencing the same appearance")
    func occurrenceDoesNotRewriteImage() throws {
        let storage = Storage()
        let store = storage.store()
        let image = Data(repeating: 7, count: 100_000)
        try store.publish(snapshot: snapshot(), imageData: image)
        let appearance = try #require(storage.bytes[.appearance])
        storage.writes.removeAll()
        try store.publish(snapshot: snapshot(offset: 86400), imageData: image)
        #expect(storage.writes.map(\.0) == [.occurrence])
        #expect(storage.writes.allSatisfy { $0.1.count <= 4096 })
        #expect(storage.bytes[.appearance] == appearance)
    }

    @Test("Changed appearance commits its atomic envelope before matching occurrence metadata")
    func appearanceGenerationOrder() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        let first = try #require(store.read(at: now))
        storage.writes.removeAll()
        try store.publish(snapshot: snapshot(message: "Good night"), imageData: Data([2]))
        #expect(storage.writes.map(\.0) == [.appearance, .occurrence])
        let second = try #require(store.read(at: now))
        #expect(second.generation != first.generation)
        #expect(second.presentation.appearance.message == "Good night")
        #expect(second.presentation.imageData == Data([2]))
        #expect(second.presentation.unlockDate == snapshot().unlockDate)
    }

    @Test(
        "Missing, expired, malformed, or generation mismatched occurrence keeps appearance neutral"
    )
    func tornOccurrenceKeepsAppearance() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        let oldOccurrence = try #require(storage.bytes[.occurrence])
        try store.publish(snapshot: snapshot(message: "New appearance"), imageData: Data([2]))
        let newOccurrence = try #require(storage.bytes[.occurrence])
        for occurrence in [nil, Data("invalid".utf8), oldOccurrence, newOccurrence] as [Data?] {
            storage.bytes[.occurrence] = occurrence
            let readTime = occurrence == newOccurrence ? now.addingTimeInterval(3601) : now
            let result = try #require(store.read(at: readTime))
            #expect(result.presentation.appearance.message == "New appearance")
            #expect(result.presentation.imageData == Data([2]))
            #expect(result.presentation.lockDate == nil)
            #expect(result.presentation.unlockDate == nil)
            #expect(result.presentation.resolve(at: readTime, timeZone: .gmt).phase == .allDay)
        }
    }
}

extension RestCompanionPresentationStoreTests {
    @Test("Stored data allowlists presentation and excludes local ownership and wake policy")
    func storagePrivacyBoundary() throws {
        let storage = Storage()
        try storage.store().publish(snapshot: snapshot(), imageData: Data([1]))
        #expect(storage.writes.count == 2)
        for (_, data) in storage.writes {
            let text = try #require(String(data: data, encoding: .utf8))
            for privateField in [
                "ownedImageFilename",
                "saverMessageEnabled",
                "sunriseWakeEnabled",
                "sunriseOnBatteryEnabled",
                "51000000-0000-0000-0000-000000000001.jpg"
            ] {
                #expect(!text.contains(privateField))
            }
        }
    }

    @Test(
        "Read requests bounded bytes and independently rejects oversized appearance "
            + "before inspection"
    )
    func boundedRead() {
        let storage = Storage()
        storage.bytes[.appearance] = Data(
            repeating: 0, count: RestCompanionPresentationStore.maximumAppearanceBytes + 1
        )
        let result = storage.store().read(at: now)
        #expect(result == nil)
        #expect(storage.inspections == 0)
        #expect(storage.limits
            .contains {
                $0.0 == .appearance && $0.1 == RestCompanionPresentationStore.maximumAppearanceBytes
            })
        #expect(RestCompanionPresentationStore.maximumAppearanceBytes <= RestCompanionExport
            .maximumEnvelopeBytes + 4096)
        #expect(RestCompanionPresentationStore.maximumOccurrenceBytes <= 4096)
    }

    @Test(
        "A fresh facade deduplicates persisted appearance and occurrence across publisher relaunch"
    )
    func persistedDeduplication() throws {
        let storage = Storage()
        try storage.store().publish(snapshot: snapshot(), imageData: Data([1]))
        #expect(storage.writes.count == 2)
        storage.writes.removeAll()
        try storage.store().publish(snapshot: snapshot(), imageData: Data([1]))
        #expect(storage.writes.isEmpty)
    }

    @Test(
        "Host acknowledgement is versioned, generation matched, "
            + "and contains no presentation content"
    )
    func acknowledgementHandshake() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        let nonce = try store.requestReadback()
        let publication = try #require(store.read(at: now))
        #expect(publication.readbackNonce == nonce)
        let acknowledgement = try store.acknowledgement(for: publication)
        let root = try #require(JSONSerialization
            .jsonObject(with: acknowledgement) as? [String: Any])
        #expect(Set(root.keys) == ["version", "generation", "nonce"])
        #expect(store.matchesCurrentPublication(acknowledgement))
        var future = root
        future["version"] = 999
        #expect(try !store
            .matchesCurrentPublication(JSONSerialization.data(withJSONObject: future)))
        try store.publish(snapshot: snapshot(message: "Changed"), imageData: Data([1]))
        #expect(!store.matchesCurrentPublication(acknowledgement))
        #expect(!store.matchesCurrentPublication(Data("invalid".utf8)))
    }

    @Test("Explicit fresh readback request prevents unchanged-generation acknowledgement replay")
    func nonceFreshness() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        let unsolicited = try #require(store.read(at: now))
        #expect(unsolicited.readbackNonce == nil)
        let unsolicitedAck = try store.acknowledgement(for: unsolicited)
        #expect(!store.matchesCurrentPublication(unsolicitedAck))
        storage.writes.removeAll()
        let firstNonce = try store.requestReadback()
        let first = try #require(store.read(at: now))
        #expect(first.readbackNonce == firstNonce)
        let firstAck = try store.acknowledgement(for: first)
        #expect(store.matchesCurrentPublication(firstAck))
        let nextNonce = try store.requestReadback()
        #expect(nextNonce != firstNonce)
        #expect(!store.matchesCurrentPublication(firstAck))
        #expect(storage.writes.map(\.0) == [.readbackRequest, .readbackRequest])
        #expect(storage.writes.allSatisfy { $0.1.count <= 4096 })
        let next = try #require(store.read(at: now))
        #expect(next.generation == first.generation)
        #expect(next.readbackNonce == nextNonce)
        let nextAck = try store.acknowledgement(for: next)
        #expect(store.matchesCurrentPublication(nextAck))
    }

    @Test("Explicit occurrence expiry changes only small metadata; appearance expiry stays fixed")
    func movingExpiryOnlyWritesOccurrence() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        let appearance = try #require(storage.bytes[.appearance])
        storage.writes.removeAll()
        try store.publish(snapshot: snapshot(expiryOffset: 60), imageData: Data([1]))
        #expect(storage.writes.map(\.0) == [.occurrence])
        #expect(storage.bytes[.appearance] == appearance)
        #expect(storage.writes.allSatisfy { $0.1.count <= 4096 })
        let result = try #require(store.read(at: now))
        #expect(result.presentation.expiresAt == snapshot(expiryOffset: 60).expiresAt)
    }

    @Test("Appearance write failure preserves previous publication and permits complete retry")
    func appearanceFailureRetry() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        let previous = try #require(store.read(at: now))
        storage.writes.removeAll()
        storage.failNextWrite = .appearance
        #expect(throws: WriteFailure.injected) {
            try store.publish(snapshot: snapshot(message: "Updated"), imageData: Data([2]))
        }
        #expect(storage.writes.isEmpty)
        #expect(store.read(at: now) == previous)
        try store.publish(snapshot: snapshot(message: "Updated"), imageData: Data([2]))
        #expect(storage.writes.map(\.0) == [.appearance, .occurrence])
        let result = try #require(store.read(at: now))
        #expect(result.presentation.appearance.message == "Updated")
    }

    @Test("Occurrence write failure leaves new appearance neutral; retry writes metadata only")
    func occurrenceFailureRetry() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        storage.writes.removeAll()
        storage.failNextWrite = .occurrence
        #expect(throws: WriteFailure.injected) {
            try store.publish(snapshot: snapshot(message: "Updated"), imageData: Data([2]))
        }
        #expect(storage.writes.map(\.0) == [.appearance])
        let torn = try #require(store.read(at: now))
        #expect(torn.presentation.appearance.message == "Updated")
        #expect(torn.presentation.imageData == Data([2]))
        #expect(torn.presentation.lockDate == nil)
        #expect(torn.presentation.unlockDate == nil)
        storage.writes.removeAll()
        try store.publish(snapshot: snapshot(message: "Updated"), imageData: Data([2]))
        #expect(storage.writes.map(\.0) == [.occurrence])
        let result = try #require(store.read(at: now))
        #expect(result.presentation.unlockDate == snapshot().unlockDate)
    }

    @Test("Oversized occurrence reads retain image and neutralize occurrence")
    func oversizedOccurrenceIsNeutral() throws {
        let storage = Storage()
        let store = storage.store()
        try store.publish(snapshot: snapshot(), imageData: Data([1]))
        storage.bytes[.occurrence] = Data(
            repeating: 0,
            count: RestCompanionPresentationStore.maximumOccurrenceBytes + 1
        )
        let result = try #require(store.read(at: now))
        #expect(result.presentation.imageData == Data([1]))
        #expect(result.presentation.lockDate == nil)
        #expect(result.presentation.unlockDate == nil)
        #expect(storage.limits
            .contains {
                $0.0 == .occurrence && $0.1 == RestCompanionPresentationStore.maximumOccurrenceBytes
            })
    }
}
