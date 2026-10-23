import CoreGraphics
@testable import CurfewAtmosphere
import CurfewKit
import Foundation
import Testing

/// Unit lifecycle contracts only; these do not prove a native saver host or image rendering.
@MainActor
struct RestScreenSaverSessionTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let zone = TimeZone(secondsFromGMT: 0)!

    @MainActor
    private final class Exchange {
        var slots: [RestCompanionPresentationStore.Slot: Data] = [:]
        var reads = 0
        var acknowledgements: [Data] = []
        var decodes = 0
        var acknowledgementFailures = 0
        lazy var store = RestCompanionPresentationStore(
            read: { slot, maximum in
                guard let bytes = self.slots[slot], bytes.count <= maximum else { return nil }
                return bytes
            },
            write: { self.slots[$0] = $1 },
            // Deliberately synthetic metadata exercises session caching, not real ImageIO
            // validation.
            inspectImageHeader: { _ in .init(width: 1, height: 1) }
        )

        func session(image: CGImage? = nil) -> RestScreenSaverSession {
            RestScreenSaverSession(
                read: { self.reads += 1; return self.store.read(at: $0) },
                acknowledge: {
                    if self.acknowledgementFailures > 0 {
                        self.acknowledgementFailures -= 1
                        throw AcknowledgementFailure.injected
                    }
                    try self.acknowledgements.append(self.store.acknowledgement(for: $0))
                },
                decodeImage: { _ in self.decodes += 1; return image }
            )
        }
    }

    private enum AcknowledgementFailure: Error { case injected }

    private func snapshot(message: String = "Rest") -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(7200),
            appearance: RestAppearancePreferences(
                background: .image,
                clockStyle: .serif, clockPosition: .lowerLeft,
                message: message,
                ownedImageFilename: "00000000-0000-0000-0000-000000000001.jpg",
                saverMessageEnabled: true
            ),
            lockDate: now.addingTimeInterval(-3600), unlockDate: now.addingTimeInterval(1800)
        )
    }

    @Test("Start loads a validated publication and acknowledges its current nonce")
    func startLoadsAndAcknowledges() throws {
        let exchange = Exchange()
        try exchange.store.publish(snapshot: snapshot(), imageData: nil)
        _ = try exchange.store.requestReadback()
        let session = exchange.session()
        session.start(at: now)
        let publication = try #require(exchange.store.read(at: now))
        #expect(session.snapshot == RestSceneSnapshot(presentation: publication.presentation))
        #expect(exchange.reads == 1)
        let acknowledgement = try #require(exchange.acknowledgements.last)
        #expect(exchange.store.matchesCurrentPublication(acknowledgement))
    }

    @Test("Frame resolves absolute occurrence dates at the host supplied instant")
    func absoluteFrames() throws {
        let exchange = Exchange()
        try exchange.store.publish(snapshot: snapshot(), imageData: nil)
        let session = exchange.session()
        session.start(at: now)
        for offset in [0.0, 1500, 1800] {
            let date = now.addingTimeInterval(offset)
            let expected = snapshot().resolve(at: date, timeZone: zone)
            #expect(session.frame(at: date, timeZone: zone) == expected)
        }
    }

    @Test("Missing or expired occurrence keeps appearance and neutral phase")
    func neutralOccurrence() throws {
        for missing in [false, true] {
            let exchange = Exchange()
            try exchange.store.publish(snapshot: snapshot(), imageData: nil)
            if missing {
                exchange.slots[.occurrence] = nil
            }
            let date = now.addingTimeInterval(8000)
            let session = exchange.session()
            session.start(at: date)
            #expect(session.snapshot?.appearance.message == "Rest")
            #expect(session.snapshot?.appearance.clockStyle == .serif)
            #expect(session.snapshot?.appearance.clockPosition == .lowerLeft)
            #expect(session.snapshot?.appearance.saverMessageEnabled == false)
            #expect(session.frame(at: date, timeZone: zone)?.phase == .allDay)
        }
    }

    @Test("Occurrence ticks and fresh nonce acknowledge without decoding the same appearance again")
    func generationCacheAndFreshNonce() throws {
        let exchange = Exchange()
        let bytes = Data([1, 2, 3])
        try exchange.store.publish(snapshot: snapshot(), imageData: bytes)
        let image = try tinyImage()
        let session = exchange.session(image: image)
        session.start(at: now)
        #expect(session.image === image)
        #expect(exchange.decodes == 1)
        let changedOccurrence = RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(9000),
            appearance: snapshot().appearance, lockDate: snapshot().lockDate,
            unlockDate: now.addingTimeInterval(3600)
        )
        try exchange.store.publish(snapshot: changedOccurrence, imageData: bytes)
        _ = session.frame(at: now, timeZone: zone)
        #expect(session.snapshot?.unlockDate == changedOccurrence.unlockDate)
        _ = try exchange.store.requestReadback()
        _ = session.frame(at: now, timeZone: zone)
        let acknowledgement = try #require(exchange.acknowledgements.last)
        #expect(exchange.store.matchesCurrentPublication(acknowledgement))
        #expect(exchange.decodes == 1)
        try exchange.store.publish(snapshot: snapshot(message: "Changed"), imageData: bytes)
        _ = session.frame(at: now, timeZone: zone)
        #expect(exchange.decodes == 2)
    }

    @Test("Failed pixel decode retains usable appearance and frame")
    func failedDecodeFallsBack() throws {
        let exchange = Exchange()
        try exchange.store.publish(snapshot: snapshot(), imageData: Data([1]))
        let session = exchange.session()
        session.start(at: now)
        #expect(exchange.decodes == 1)
        #expect(session.image == nil)
        #expect(session.snapshot?.appearance.message == "Rest")
        #expect(session.frame(at: now, timeZone: zone) != nil)
        #expect(exchange.decodes == 1)
    }

    @Test("Stop clears retained presentation and late frames perform no work; restart reloads")
    func stopAndRestart() throws {
        let exchange = Exchange()
        try exchange.store.publish(snapshot: snapshot(), imageData: Data([1]))
        _ = try exchange.store.requestReadback()
        let session = try exchange.session(image: tinyImage())
        session.start(at: now)
        session.stop()
        #expect(session.snapshot == nil)
        #expect(session.image == nil)
        let counts = (exchange.reads, exchange.acknowledgements.count, exchange.decodes)
        #expect(session.frame(at: now, timeZone: zone) == nil)
        #expect(exchange.reads == counts.0)
        #expect(exchange.acknowledgements.count == counts.1)
        #expect(exchange.decodes == counts.2)
        _ = try exchange.store.requestReadback()
        session.start(at: now)
        #expect(session.snapshot != nil)
        #expect(exchange.reads == counts.0 + 1)
        #expect(exchange.acknowledgements.count == counts.1 + 1)
        #expect(exchange.decodes == counts.2 + 1)
    }

    @Test("Acknowledgement errors preserve rendering and retry without decoding again")
    func acknowledgementFailureRetries() throws {
        let exchange = Exchange()
        try exchange.store.publish(snapshot: snapshot(), imageData: Data([1]))
        _ = try exchange.store.requestReadback()
        exchange.acknowledgementFailures = 1
        let session = try exchange.session(image: tinyImage())
        session.start(at: now)
        #expect(session.snapshot != nil)
        #expect(session.image != nil)
        #expect(exchange.acknowledgements.isEmpty)
        #expect(session.frame(at: now, timeZone: zone) != nil)
        let acknowledgement = try #require(exchange.acknowledgements.last)
        #expect(exchange.store.matchesCurrentPublication(acknowledgement))
        #expect(exchange.decodes == 1)
    }

    @Test("Publication disappearance retains appearance and image with a neutral clock")
    func disappearanceRetainsNeutralAppearance() throws {
        let exchange = Exchange()
        try exchange.store.publish(snapshot: snapshot(), imageData: Data([1]))
        let image = try tinyImage()
        let session = exchange.session(image: image)
        session.start(at: now)
        exchange.slots[.appearance] = nil
        exchange.slots[.occurrence] = nil
        #expect(session.frame(at: now, timeZone: zone)?.phase == .allDay)
        #expect(session.snapshot?.lockDate == nil)
        #expect(session.snapshot?.unlockDate == nil)
        #expect(session.snapshot?.appearance.message == "Rest")
        #expect(session.snapshot?.appearance.clockStyle == .serif)
        #expect(session.image === image)
        #expect(exchange.decodes == 1)
    }

    private func tinyImage() throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data([127, 127, 127, 255]) as CFData))
        return try #require(CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}
