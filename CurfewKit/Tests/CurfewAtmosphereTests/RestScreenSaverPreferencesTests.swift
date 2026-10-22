import CoreGraphics
@testable import CurfewAtmosphere
import CurfewKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Behavioral contracts awaiting an authorized, observed failing run.
struct RestScreenSaverPreferencesTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func withSuite(_ body: (UserDefaults, UserDefaults) throws -> Void) throws {
        let name = "RestScreenSaverPreferencesTests.\(UUID().uuidString)"
        let publisher = try #require(UserDefaults(suiteName: name))
        let host = try #require(UserDefaults(suiteName: name))
        defer { publisher.removePersistentDomain(forName: name) }
        try body(publisher, host)
    }

    private func snapshot(message: String = "Rest") -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(message: message, saverMessageEnabled: true),
            lockDate: now.addingTimeInterval(-60), unlockDate: now.addingTimeInterval(1800)
        )
    }

    @Test("Fresh injected defaults instances exchange persistent presentation slots")
    func crossInstancePersistence() throws {
        try withSuite { publisher, host in
            try RestScreenSaverPreferences(defaults: publisher).publish(
                snapshot: snapshot(), imageData: nil
            )
            let result = try #require(RestScreenSaverPreferences(defaults: host).read(at: now))
            #expect(result.presentation.appearance.message == "Rest")
            #expect(result.presentation.unlockDate == snapshot().unlockDate)
            #expect(publisher.object(forKey: RestScreenSaverPreferences.Keys.appearance) is Data)
            #expect(publisher.object(forKey: RestScreenSaverPreferences.Keys.occurrence) is Data)
        }
    }

    @Test("Wrong types and oversized appearance never reach image metadata inspection")
    func boundedAppearanceReads() throws {
        try withSuite { publisher, host in
            var inspections = 0
            let adapter = RestScreenSaverPreferences(defaults: host, inspectImageHeader: { _ in
                inspections += 1
                return .init(width: 1, height: 1)
            })
            let values: [Any] = [
                "wrong type", 42,
                Data(repeating: 0, count: RestCompanionPresentationStore.maximumAppearanceBytes + 1)
            ]
            for value in values {
                publisher.set(value, forKey: RestScreenSaverPreferences.Keys.appearance)
                #expect(adapter.read(at: now) == nil)
            }
            #expect(inspections == 0)
        }
    }

    @Test("Invalid small occurrence preserves appearance without inventing occurrence status")
    func boundedOccurrenceReads() throws {
        try withSuite { publisher, host in
            try RestScreenSaverPreferences(defaults: publisher).publish(
                snapshot: snapshot(), imageData: nil
            )
            let values: [Any] = ["wrong type", Data(repeating: 0, count: 4097)]
            for value in values {
                publisher.set(value, forKey: RestScreenSaverPreferences.Keys.occurrence)
                let result = try #require(RestScreenSaverPreferences(defaults: host).read(at: now))
                #expect(result.presentation.appearance.message == "Rest")
                #expect(result.presentation.unlockDate == nil)
            }
        }
    }

    @Test("Host acknowledgement requires current generation and fresh requested nonce")
    func acknowledgedNonceRoundtrip() throws {
        try withSuite { publisher, host in
            let app = RestScreenSaverPreferences(defaults: publisher)
            let saver = RestScreenSaverPreferences(defaults: host)
            try app.publish(snapshot: snapshot(), imageData: nil)
            #expect(!app.hasAcknowledgedCurrentPublication())
            let nonce = try app.requestReadback()
            let publication = try #require(saver.read(at: now))
            #expect(publication.readbackNonce == nonce)
            try saver.acknowledge(publication)
            let freshApp = RestScreenSaverPreferences(defaults: publisher)
            #expect(freshApp.hasAcknowledgedCurrentPublication())
            let bytes = try #require(host.data(
                forKey: RestScreenSaverPreferences.Keys.acknowledgement
            ))
            #expect(bytes.count <= 4096)
            let root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(Set(root.keys) == ["version", "generation", "nonce"])
            _ = try app.requestReadback()
            #expect(!app.hasAcknowledgedCurrentPublication())
            let freshPublication = try #require(saver.read(at: now))
            try saver.acknowledge(freshPublication)
            try #require(app.hasAcknowledgedCurrentPublication())
            try app.publish(snapshot: snapshot(message: "Changed"), imageData: nil)
            #expect(!app.hasAcknowledgedCurrentPublication())
        }
    }

    @Test("Acknowledgement rejects wrong types and oversized bytes")
    func boundedAcknowledgementReads() throws {
        try withSuite { publisher, host in
            let adapter = RestScreenSaverPreferences(defaults: publisher)
            let saver = RestScreenSaverPreferences(defaults: host)
            try adapter.publish(snapshot: snapshot(), imageData: nil)
            _ = try adapter.requestReadback()
            let publication = try #require(saver.read(at: now))
            try saver.acknowledge(publication)
            try #require(adapter.hasAcknowledgedCurrentPublication())
            let validBytes = try #require(host.data(
                forKey: RestScreenSaverPreferences.Keys.acknowledgement
            ))
            try #require(validBytes.count <= 4096)
            var oversized = validBytes
            oversized.append(Data(repeating: 0x20, count: 4097 - validBytes.count))
            // Valid trailing JSON whitespace isolates the byte guard from decoder rejection.
            let paddedRoot = try JSONSerialization.jsonObject(with: oversized) as? [String: Any]
            try #require(paddedRoot != nil)
            publisher.set(oversized, forKey: RestScreenSaverPreferences.Keys.acknowledgement)
            #expect(!adapter.hasAcknowledgedCurrentPublication())

            publisher.set(validBytes, forKey: RestScreenSaverPreferences.Keys.acknowledgement)
            try #require(adapter.hasAcknowledgedCurrentPublication())
            publisher.set("wrong type", forKey: RestScreenSaverPreferences.Keys.acknowledgement)
            #expect(!adapter.hasAcknowledgedCurrentPublication())
        }
    }

    @Test("Image metadata adapter rejects invalid and oversized encoded input")
    func boundedImageMetadata() {
        #expect(throws: (any Error).self) {
            try RestScreenSaverPreferences.inspectImageHeader(Data("invalid".utf8))
        }
        #expect(throws: (any Error).self) {
            try RestScreenSaverPreferences.inspectImageHeader(Data(
                repeating: 0, count: RestCompanionExport.maximumImageBytes + 1
            ))
        }
    }

    @Test(
        "Image metadata accepts real JPEG and PNG dimensions without renderer decoding",
        arguments: [UTType.jpeg.identifier, UTType.png.identifier]
    )
    func validImageMetadata(type: String) throws {
        let bytes = try encodedImage(type: type, width: 64, height: 32)
        #expect(bytes.count <= RestCompanionExport.maximumImageBytes)
        let dimensions = try RestScreenSaverPreferences.inspectImageHeader(bytes)
        #expect(dimensions == .init(width: 64, height: 32))
    }

    @Test(
        "A small encoded image cannot bypass maximum header dimension bounds",
        arguments: [UTType.jpeg.identifier, UTType.png.identifier]
    )
    func oversizedImageDimensions(type: String) throws {
        let bytes = try encodedImage(
            type: type,
            width: RestCompanionExport.maximumImageDimension + 1,
            height: 1
        )
        // The byte-size guard passes, so rejection must come from image metadata.
        #expect(bytes.count <= RestCompanionExport.maximumImageBytes)
        #expect(throws: (any Error).self) {
            try RestScreenSaverPreferences.inspectImageHeader(bytes)
        }
    }

    @Test(
        "Bounded pixel decoding preserves real JPEG, PNG, and HEIC dimensions",
        arguments: [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier]
    )
    func boundedPixelDecode(type: String) throws {
        let bytes = try encodedImage(type: type, width: 64, height: 32)
        try #require(bytes.count <= RestCompanionExport.maximumImageBytes)
        let image = try #require(RestScreenSaverPreferences.boundedImage(bytes))
        #expect(image.width == 64)
        #expect(image.height == 32)
    }

    @Test("Bounded pixel decoding rejects empty, corrupt, and oversized input")
    func invalidPixelDecode() {
        #expect(RestScreenSaverPreferences.boundedImage(Data()) == nil)
        #expect(RestScreenSaverPreferences.boundedImage(Data("invalid".utf8)) == nil)
        #expect(RestScreenSaverPreferences.boundedImage(Data(
            repeating: 0, count: RestCompanionExport.maximumImageBytes + 1
        )) == nil)
    }

    @Test("Bounded pixel decoding rejects a real unsupported GIF")
    func unsupportedPixelDecode() throws {
        let bytes = try encodedImage(type: UTType.gif.identifier, width: 64, height: 32)
        try #require(bytes.count <= RestCompanionExport.maximumImageBytes)
        #expect(RestScreenSaverPreferences.boundedImage(bytes) == nil)
    }

    @Test(
        "Bounded pixel decoding rejects real encoded dimensions above the limit",
        arguments: [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier]
    )
    func oversizedPixelDecodeDimensions(type: String) throws {
        let bytes = try encodedImage(
            type: type, width: RestCompanionExport.maximumImageDimension + 2, height: 64
        )
        try #require(bytes.count <= RestCompanionExport.maximumImageBytes)
        #expect(RestScreenSaverPreferences.boundedImage(bytes) == nil)
    }

    /// Synthetic in-memory ImageIO fixture; no screenshot, native surface, or user image.
    private func encodedImage(type: String, width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 127, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) {
            pixels[index] = 255
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            bytes, type as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
