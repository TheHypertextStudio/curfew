@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Injected publication effects only; these tests never open a real defaults module.
@MainActor
struct RestCompanionPublicationTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let firstFilename = "00000000-0000-0000-0000-000000000001.jpg"
    private let secondFilename = "00000000-0000-0000-0000-000000000002.jpg"

    private func snapshot(
        filename: String? = nil,
        background: RestAppearancePreferences.Background? = nil,
        unlockOffset: TimeInterval? = 1800,
        message: String = "Private app message",
        sharesMessage: Bool = false
    ) -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(7200),
            appearance: RestAppearancePreferences(
                background: background ?? (filename == nil ? .atmosphere : .image),
                message: message, ownedImageFilename: filename,
                saverMessageEnabled: sharesMessage
            ),
            lockDate: unlockOffset == nil ? nil : now.addingTimeInterval(-3600),
            unlockDate: unlockOffset.map { now.addingTimeInterval($0) }
        )
    }

    @Test("Publication is inert by default and explicit disarming performs no effects")
    func disarmedPublication() async {
        let effects = Effects()
        let publisher = effects.publisher()
        await publisher.reconcile(snapshot: snapshot(filename: firstFilename))
        await publisher.reconcile(
            snapshot: snapshot(filename: secondFilename), allowsPublication: false
        )
        #expect(effects.imageReads.isEmpty)
        #expect(effects.attempts.isEmpty)
        #expect(publisher.status == .notPublished)
    }

    @Test("Initial publication reads the owned rendition and preserves visual choices")
    func initialPublication() async throws {
        let effects = Effects()
        let expected = snapshot(filename: firstFilename)
        let publisher = effects.publisher()
        await publisher.reconcile(snapshot: expected, allowsPublication: true)
        #expect(effects.imageReads == [firstFilename])
        let written = try #require(effects.attempts.first)
        #expect(written.0 == expected)
        #expect(written.1 == effects.imageBytes)
        #expect(publisher.status == .publicationWritten)
    }

    @Test("Identical clock ticks do not republish or reread the image")
    func unchangedPublication() async {
        let effects = Effects()
        let publisher = effects.publisher()
        let stable = snapshot(filename: firstFilename)
        await publisher.reconcile(snapshot: stable, allowsPublication: true)
        await publisher.reconcile(snapshot: stable, allowsPublication: true)
        await publisher.reconcile(snapshot: stable, allowsPublication: true)
        #expect(effects.attempts.count == 1)
        #expect(effects.imageReads == [firstFilename])
    }

    @Test("Occurrence changes reuse the rendition while a changed filename loads once")
    func changedPublication() async throws {
        let effects = Effects()
        let publisher = effects.publisher()
        await publisher.reconcile(
            snapshot: snapshot(filename: firstFilename), allowsPublication: true
        )
        let changedOccurrence = snapshot(filename: firstFilename, unlockOffset: 3600)
        await publisher.reconcile(snapshot: changedOccurrence, allowsPublication: true)
        let changedImage = snapshot(filename: secondFilename, unlockOffset: 3600)
        await publisher.reconcile(snapshot: changedImage, allowsPublication: true)
        await publisher.reconcile(snapshot: changedImage, allowsPublication: true)
        #expect(effects.attempts.count == 3)
        #expect(effects.imageReads == [firstFilename, secondFilename])
        #expect(try #require(effects.attempts.last).0 == changedImage)
    }

    @Test(
        "A rejected write reports failure and the same snapshot retries instead of caching success"
    )
    func failedPublicationRetries() async {
        let effects = Effects()
        effects.writeFailures = 1
        let publisher = effects.publisher()
        let stable = snapshot(filename: firstFilename)
        await publisher.reconcile(snapshot: stable, allowsPublication: true)
        #expect(publisher.status == .failed)
        await publisher.reconcile(snapshot: stable, allowsPublication: true)
        #expect(effects.attempts.count == 2)
        #expect(publisher.status == .publicationWritten)
    }

    @Test("Missing owned bytes retain the chosen appearance without inventing an occurrence")
    func missingImage() async throws {
        let effects = Effects()
        effects.imageBytes = nil
        let publisher = effects.publisher()
        let expected = snapshot(filename: firstFilename, unlockOffset: nil)
        await publisher.reconcile(snapshot: expected, allowsPublication: true)
        let written = try #require(effects.attempts.first)
        #expect(written.0 == expected)
        #expect(written.1 == nil)
        #expect(written.0.resolve(at: now, timeZone: .current).phase == .allDay)
        #expect(publisher.status == .publicationWritten)
    }

    @Test("The publication adapter exports only visual consent and never the owned filename")
    func privacyAllowlist() async throws {
        let effects = Effects()
        let publisher = effects.publisher()
        await publisher.reconcile(
            snapshot: snapshot(filename: firstFilename), allowsPublication: true
        )
        let bytes = try #require(effects.exportedBytes.last)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(object.keys) == [
            "version", "expiresAt", "appearance", "lockDate", "unlockDate", "imageData"
        ])
        let appearance = try #require(object["appearance"] as? [String: Any])
        #expect(appearance["message"] as? String == "")
        #expect(appearance["ownedImageFilename"] == nil)
        #expect(appearance["sunriseWakeEnabled"] == nil)
        #expect(appearance["sunriseOnBatteryEnabled"] == nil)
        await publisher.reconcile(
            snapshot: snapshot(filename: firstFilename, sharesMessage: true),
            allowsPublication: true
        )
        let shared = try RestCompanionExport.decode(
            #require(effects.exportedBytes.last), inspectImageHeader: { _ in .init(
                width: 1,
                height: 1
            ) }
        )
        #expect(shared.appearance.message == "Private app message")
    }

    @Test("An obsolete suspended image read cannot overwrite a newer appearance")
    func obsoleteReadCannotPublish() async {
        let suspension = ImageSuspension()
        var published: [RestSceneSnapshot] = []
        let publisher = RestCompanionPublisher(
            readOwnedImage: { filename in
                if filename == firstFilename {
                    return await suspension.read()
                }
                return Data([2])
            },
            publish: { scene, _ in published.append(scene) }
        )
        let first = Task { @MainActor in
            await publisher.reconcile(
                snapshot: snapshot(filename: firstFilename), allowsPublication: true
            )
            suspension.operationEnded()
        }
        guard await suspension.waitForEntryOrCompletion() else {
            Issue.record("Publication ended without reading the requested owned image")
            await first.value
            return
        }
        let latest = snapshot(filename: secondFilename)
        await publisher.reconcile(snapshot: latest, allowsPublication: true)
        suspension.resume()
        await first.value
        #expect(published == [latest])
        #expect(publisher.status == .publicationWritten)
    }

    private enum Failure: Error { case injected }

    @MainActor
    private final class Effects {
        var imageReads: [String] = []
        var attempts: [(RestSceneSnapshot, Data?)] = []
        var exportedBytes: [Data] = []
        var imageBytes: Data? = Data([1, 2, 3])
        var writeFailures = 0
        var readFailures = 0

        func publisher() -> RestCompanionPublisher {
            RestCompanionPublisher(
                readOwnedImage: { filename in
                    self.imageReads.append(filename)
                    if self.readFailures > 0 {
                        self.readFailures -= 1
                        throw Failure.injected
                    }
                    return self.imageBytes
                },
                publish: { scene, bytes in
                    self.attempts.append((scene, bytes))
                    if self.writeFailures > 0 {
                        self.writeFailures -= 1
                        throw Failure.injected
                    }
                    // Synthetic image dimensions test publication plumbing, not ImageIO.
                    try self.exportedBytes.append(RestCompanionExport.encode(
                        snapshot: scene, imageData: bytes,
                        inspectImageHeader: { _ in .init(width: 1, height: 1) }
                    ))
                }
            )
        }
    }

    /// Completion also wakes the waiter, so the inert contract cannot hang the test.
    @MainActor
    private final class ImageSuspension {
        private var entryResult: Bool?
        private var entryWaiter: CheckedContinuation<Bool, Never>?
        private var imageWaiter: CheckedContinuation<Data?, Never>?

        func read() async -> Data? {
            signalEntry(true)
            return await withCheckedContinuation { imageWaiter = $0 }
        }

        func operationEnded() {
            if entryResult == nil {
                signalEntry(false)
            }
        }

        func waitForEntryOrCompletion() async -> Bool {
            if let entryResult {
                return entryResult
            }
            return await withCheckedContinuation { entryWaiter = $0 }
        }

        func resume() {
            imageWaiter?.resume(returning: Data([1]))
            imageWaiter = nil
        }

        private func signalEntry(_ entered: Bool) {
            entryResult = entered
            entryWaiter?.resume(returning: entered)
            entryWaiter = nil
        }
    }
}

extension RestCompanionPublicationTests {
    @Test("Disarming invalidates an earlier suspended read without writing its publication")
    func disarmingInvalidatesRead() async {
        let suspension = ImageSuspension()
        var published: [RestSceneSnapshot] = []
        let publisher = RestCompanionPublisher(
            readOwnedImage: { _ in await suspension.read() },
            publish: { scene, _ in published.append(scene) }
        )
        let pending = Task { @MainActor in
            await publisher.reconcile(
                snapshot: snapshot(filename: firstFilename), allowsPublication: true
            )
            suspension.operationEnded()
        }
        guard await suspension.waitForEntryOrCompletion() else {
            Issue.record("Publication ended without reading the requested owned image")
            await pending.value
            return
        }
        await publisher.reconcile(
            snapshot: snapshot(filename: firstFilename), allowsPublication: false
        )
        suspension.resume()
        await pending.value
        #expect(published.isEmpty)
        #expect(publisher.status == .notPublished)
    }

    @Test("Choosing atmosphere does not read or export a retained image filename")
    func atmosphereDoesNotExportRetainedImage() async throws {
        let effects = Effects()
        let publisher = effects.publisher()
        let atmosphere = snapshot(filename: firstFilename, background: .atmosphere)
        await publisher.reconcile(snapshot: atmosphere, allowsPublication: true)
        #expect(effects.imageReads.isEmpty)
        #expect(try #require(effects.attempts.first).1 == nil)
        await publisher.reconcile(
            snapshot: snapshot(filename: firstFilename), allowsPublication: true
        )
        #expect(effects.imageReads == [firstFilename])
        await publisher.reconcile(snapshot: atmosphere, allowsPublication: true)
        #expect(effects.imageReads == [firstFilename])
        #expect(try #require(effects.attempts.last).1 == nil)
        let exported = try RestCompanionExport.decode(
            #require(effects.exportedBytes.last),
            inspectImageHeader: { _ in .init(width: 1, height: 1) }
        )
        #expect(exported.appearance.background == .atmosphere)
        #expect(exported.imageData == nil)
    }

    @Test("An owned image read error reports failure without writing and can retry")
    func readFailureDoesNotPublish() async {
        let effects = Effects()
        effects.readFailures = 1
        let publisher = effects.publisher()
        let stable = snapshot(filename: firstFilename)
        await publisher.reconcile(snapshot: stable, allowsPublication: true)
        #expect(publisher.status == .failed)
        #expect(effects.attempts.isEmpty)
        await publisher.reconcile(snapshot: stable, allowsPublication: true)
        #expect(effects.imageReads == [firstFilename, firstFilename])
        #expect(effects.attempts.count == 1)
        #expect(publisher.status == .publicationWritten)
    }
}
