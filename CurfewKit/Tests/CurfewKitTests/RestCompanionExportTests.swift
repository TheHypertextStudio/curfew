@testable import CurfewKit
import Foundation
import Testing

/// Unexecuted contract tests against an inert API scaffold; no behavioral RED is claimed.
struct RestCompanionExportTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let filename = "51000000-0000-0000-0000-000000000001.jpg"

    private func snapshot(
        messageEnabled: Bool = false,
        expiresIn: Double = 3600
    ) -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1,
            expiresAt: now.addingTimeInterval(expiresIn),
            appearance: RestAppearancePreferences(
                background: .image, message: "Private personal message",
                ownedImageFilename: filename, saverMessageEnabled: messageEnabled,
                sunriseWakeEnabled: true, sunriseOnBatteryEnabled: true
            ),
            lockDate: now.addingTimeInterval(-3600), unlockDate: now.addingTimeInterval(1800)
        )
    }

    private func header(_: Data) throws -> RestCompanionExport.ImageDimensions {
        RestCompanionExport.ImageDimensions(width: 3840, height: 2160)
    }

    @Test("Export omits the personal message unless separately opted in")
    func messageOptIn() throws {
        for enabled in [false, true] {
            let bytes = try RestCompanionExport.encode(
                snapshot: snapshot(messageEnabled: enabled), imageData: nil,
                inspectImageHeader: header
            )
            let text = try #require(String(data: bytes, encoding: .utf8))
            #expect(text.contains("Private personal message") == enabled)
            let decoded = try RestCompanionExport.decode(bytes, inspectImageHeader: header)
            #expect(decoded.appearance.message == (enabled ? "Private personal message" : ""))
        }
    }

    @Test("The wire object contains presentation only and never a local filename or wake policy")
    func privacyBoundary() throws {
        let bytes = try RestCompanionExport.encode(
            snapshot: snapshot(), imageData: nil, inspectImageHeader: header
        )
        let root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(root.keys) == ["version", "expiresAt", "appearance", "lockDate", "unlockDate"])
        let appearance = try #require(root["appearance"] as? [String: Any])
        #expect(Set(appearance.keys) == [
            "background", "palette", "solidRed", "solidGreen", "solidBlue", "clockStyle",
            "clockPosition", "staticBackground", "message", "focalX", "focalY", "sunriseLeadMinutes"
        ])
        let text = try #require(String(data: bytes, encoding: .utf8))
        for privateValue in [
            filename,
            "ownedImageFilename",
            "saverMessageEnabled",
            "sunriseWakeEnabled",
            "sunriseOnBatteryEnabled",
            "draft",
            "journal",
            "account",
            "recovery"
        ] {
            #expect(!text.contains(privateValue))
        }
    }

    @Test("A bounded image round-trips without changing image selection or focal position")
    func imageRoundTrip() throws {
        let image = Data(repeating: 7, count: RestCompanionExport.maximumImageBytes)
        let bytes = try RestCompanionExport.encode(
            snapshot: snapshot(), imageData: image, inspectImageHeader: header
        )
        #expect(bytes.count <= RestCompanionExport.maximumEnvelopeBytes)
        let value = try RestCompanionExport.decode(bytes, inspectImageHeader: header)
        #expect(value.version == 1)
        #expect(value.imageData == image)
        #expect(value.appearance.background == .image)
        #expect(value.appearance.focalX == 0.5)
        #expect(value.appearance.focalY == 0.5)
    }

    @Test("Oversized encoded images are rejected before any header inspection")
    func rejectOversizedImageBeforeInspection() {
        var inspected = false
        #expect(throws: RestCompanionExport.ValidationError.imageTooLarge) {
            try RestCompanionExport.encode(
                snapshot: snapshot(),
                imageData: Data(repeating: 0, count: RestCompanionExport.maximumImageBytes + 1)
            ) { _ in
                inspected = true
                return .init(width: 1, height: 1)
            }
        }
        #expect(!inspected)
    }

    @Test(
        "Invalid dimensions are rejected from headers before the visual adapter can decode pixels"
    )
    func rejectDimensions() {
        for (width, height) in [(3841, 1), (1, 3841), (0, 1), (1, 0), (-1, 20)] {
            #expect(throws: RestCompanionExport.ValidationError.invalidImageDimensions) {
                try RestCompanionExport.encode(snapshot: snapshot(), imageData: Data([1])) { _ in
                    .init(width: width, height: height)
                }
            }
        }
    }

    @Test("Malformed image header failures propagate without trusting caller-supplied dimensions")
    func rejectMalformedImage() {
        #expect(throws: RestCompanionExport.ValidationError.invalidImageHeader) {
            try RestCompanionExport.encode(snapshot: snapshot(), imageData: Data([1])) { _ in
                throw RestCompanionExport.ValidationError.invalidImageHeader
            }
        }
    }

    @Test("Decoder rejects excessive envelopes before header inspection")
    func rejectOversizedEnvelope() {
        var inspected = false
        #expect(throws: RestCompanionExport.ValidationError.envelopeTooLarge) {
            try RestCompanionExport.decode(
                Data(repeating: 0, count: RestCompanionExport.maximumEnvelopeBytes + 1)
            ) { _ in
                inspected = true
                return .init(width: 1, height: 1)
            }
        }
        #expect(!inspected)
    }

    @Test("Decoder independently checks embedded image dimensions")
    func consumerRevalidatesImage() throws {
        let bytes = try RestCompanionExport.encode(
            snapshot: snapshot(), imageData: Data([1]), inspectImageHeader: header
        )
        #expect(throws: RestCompanionExport.ValidationError.invalidImageDimensions) {
            try RestCompanionExport.decode(bytes) { _ in .init(width: 1, height: 3841) }
        }
    }

    @Test("Consumer rejects oversized embedded image bytes before metadata inspection")
    func consumerBoundsImageBytes() throws {
        let bytes = try RestCompanionExport.encode(
            snapshot: snapshot(), imageData: nil, inspectImageHeader: header
        )
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        root["imageData"] = Data(
            repeating: 0, count: RestCompanionExport.maximumImageBytes + 1
        ).base64EncodedString()
        let hostile = try JSONSerialization.data(withJSONObject: root)
        #expect(hostile.count < RestCompanionExport.maximumEnvelopeBytes)
        var inspected = false
        #expect(throws: RestCompanionExport.ValidationError.imageTooLarge) {
            try RestCompanionExport.decode(hostile) { _ in
                inspected = true
                return .init(width: 1, height: 1)
            }
        }
        #expect(!inspected)
    }

    @Test("No occurrence exports only a neutral background and clock context")
    func absentOccurrenceIsNeutral() throws {
        let absent = RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(), lockDate: nil, unlockDate: nil
        )
        let bytes = try RestCompanionExport.encode(
            snapshot: absent, imageData: nil, inspectImageHeader: header
        )
        let value = try RestCompanionExport.decode(bytes, inspectImageHeader: header)
        #expect(value.lockDate == nil)
        #expect(value.unlockDate == nil)
        #expect(value.imageData == nil)
        #expect(value.resolve(at: now, timeZone: .gmt).phase == .allDay)
        #expect(value.resolve(at: now, timeZone: .gmt).sunriseProgress == 0)
    }

    @Test("Unsupported versions and malformed JSON are rejected")
    func rejectVersionAndMalformedPayload() throws {
        let bytes = try RestCompanionExport.encode(
            snapshot: snapshot(), imageData: nil, inspectImageHeader: header
        )
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        root["version"] = 999
        let future = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: RestCompanionExport.ValidationError.unsupportedVersion) {
            try RestCompanionExport.decode(future, inspectImageHeader: header)
        }
        #expect(throws: (any Error).self) {
            try RestCompanionExport.decode(Data("not JSON".utf8), inspectImageHeader: header)
        }
    }

    @Test("An expired snapshot keeps appearance but resolves neutral occurrence context")
    func expiredIsNeutral() throws {
        let bytes = try RestCompanionExport.encode(
            snapshot: snapshot(expiresIn: 1), imageData: nil, inspectImageHeader: header
        )
        let value = try RestCompanionExport.decode(bytes, inspectImageHeader: header)
        #expect(value.resolve(at: now, timeZone: .gmt).phase == .sunrise)
        #expect(value.resolve(at: now.addingTimeInterval(1), timeZone: .gmt).phase == .allDay)
        #expect(value.resolve(at: now.addingTimeInterval(2), timeZone: .gmt).sunriseProgress == 0)
        #expect(value.appearance.palette == .sundown)
    }
}
