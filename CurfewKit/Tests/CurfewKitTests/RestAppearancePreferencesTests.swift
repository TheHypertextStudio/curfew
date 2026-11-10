@testable import CurfewKit
import Foundation
import Testing

/// Contract preparation only: intended production types do not exist yet.
/// Compilation failure is not behavioral RED. See the task-1 report.
struct RestAppearancePreferencesTests {
    private func decode(_ json: String) throws -> RestAppearancePreferences {
        try JSONDecoder().decode(RestAppearancePreferences.self, from: Data(json.utf8))
    }

    @Test("Migration preserves Sundown and leaves every permission opt-in disabled")
    func migrationDefaults() throws {
        let expected = RestAppearancePreferences()
        #expect(try decode("{}") == expected)
        #expect(expected.background == .atmosphere)
        #expect(expected.palette == .sundown)
        #expect(expected.clockStyle == .rounded)
        #expect(expected.clockPosition == .center)
        #expect(!expected.staticBackground)
        #expect(expected.message.isEmpty)
        #expect(expected.ownedImageFilename == nil)
        #expect(expected.focalX == 0.5)
        #expect(expected.focalY == 0.5)
        #expect(!expected.saverMessageEnabled)
        #expect(!expected.sunriseWakeEnabled)
        #expect(!expected.sunriseOnBatteryEnabled)
        #expect(expected.sunriseLeadMinutes == 30)
    }

    @Test("A partial record retains its choices while new fields use migration defaults")
    func partialMigration() throws {
        let preferences = try decode(#"{"palette":"warmAmber","message":"Rest well"}"#)
        #expect(preferences.palette == .warmAmber)
        #expect(preferences.message == "Rest well")
        #expect(preferences.background == .atmosphere)
        #expect(preferences.clockStyle == .rounded)
        #expect(!preferences.saverMessageEnabled)
        #expect(!preferences.sunriseWakeEnabled)
        #expect(!preferences.sunriseOnBatteryEnabled)
        #expect(preferences.sunriseLeadMinutes == 30)
    }

    @Test("Unknown choices and malformed fields fall back independently")
    func invalidValuesPreserveOtherFields() throws {
        let preferences =
            try decode(
                #"""
                {
                  "background": "unknown",
                  "palette": "unknown",
                  "clockStyle": 5,
                  "clockPosition": null,
                  "message": false,
                  "focalX": "left",
                  "focalY": null,
                  "staticBackground": "yes",
                  "sunriseLeadMinutes": "soon",
                  "sunriseWakeEnabled": "yes",
                  "sunriseOnBatteryEnabled": null,
                  "saverMessageEnabled": 1
                }
                """#
            )
        #expect(preferences == RestAppearancePreferences())
        let mixed =
            try decode(
                #"""
                {
                  "palette": "coolTwilight",
                  "clockStyle": "unknown",
                  "message": "Keep this",
                  "sunriseWakeEnabled": true
                }
                """#
            )
        #expect(mixed.palette == .coolTwilight)
        #expect(mixed.clockStyle == .rounded)
        #expect(mixed.message == "Keep this")
        #expect(mixed.sunriseWakeEnabled)
        #expect(!mixed.sunriseOnBatteryEnabled)
    }

    @Test("Appearance choices and independent opt-ins survive Codable roundtrip")
    func roundtrip() throws {
        let preferences = RestAppearancePreferences(
            background: .solid,
            palette: .coolTwilight,
            solidRed: 0.2,
            solidGreen: 0.3,
            solidBlue: 0.4,
            clockStyle: .serif,
            clockPosition: .lowerLeft,
            staticBackground: true,
            message: "Tomorrow can wait.",
            focalX: 0.2,
            focalY: 0.8,
            saverMessageEnabled: true,
            sunriseWakeEnabled: true,
            sunriseLeadMinutes: 45,
            sunriseOnBatteryEnabled: true
        )
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(RestAppearancePreferences.self, from: data) == preferences)
        let alternate =
            try decode(
                #"{"clockStyle":"standard","clockPosition":"upperCenter","palette":"warmAmber"}"#
            )
        #expect(alternate.clockStyle == .standard)
        #expect(alternate.clockPosition == .upperCenter)
        #expect(alternate.palette == .warmAmber)
    }

    @Test("Solid sRGB components persist and normalize independently")
    func solidColorNormalization() throws {
        let defaults = RestAppearancePreferences()
        #expect(defaults.solidRed == 0.06)
        #expect(defaults.solidGreen == 0.07)
        #expect(defaults.solidBlue == 0.15)
        let bounded = RestAppearancePreferences(solidRed: -1, solidGreen: 2, solidBlue: 0.4)
        #expect(bounded.solidRed == 0)
        #expect(bounded.solidGreen == 1)
        #expect(bounded.solidBlue == 0.4)
        let malformed = try decode(#"{"solidRed":"red","solidGreen":null,"solidBlue":0.4}"#)
        #expect(malformed.solidRed == 0.06)
        #expect(malformed.solidGreen == 0.07)
        #expect(malformed.solidBlue == 0.4)
        for value in [Double.nan, .infinity, -.infinity] {
            let invalid = RestAppearancePreferences(
                solidRed: value,
                solidGreen: value,
                solidBlue: value
            )
            #expect(invalid.solidRed == 0.06)
            #expect(invalid.solidGreen == 0.07)
            #expect(invalid.solidBlue == 0.15)
        }
    }

    @Test("Messages trim surrounding whitespace and truncate by extended grapheme Character")
    func messageNormalization() throws {
        let grapheme = "👨‍👩‍👧‍👦"
        let expected = String(repeating: grapheme, count: 140)
        let input = " \n" + expected + "e\u{301}end\t "
        #expect(RestAppearancePreferences(message: input).message == expected)
        #expect(RestAppearancePreferences(message: input).message.count == 140)
        let encoded = try JSONEncoder().encode(["message": input])
        #expect(try JSONDecoder().decode(RestAppearancePreferences.self, from: encoded)
            .message == expected)
        let exactly140 = String(repeating: "e\u{301}", count: 140)
        #expect(RestAppearancePreferences(message: exactly140).message == exactly140)
        #expect(RestAppearancePreferences(message: " \n\t ").message.isEmpty)
    }

    @Test("Focal points clamp to the image and nonfinite input returns to center")
    func focalBounds() throws {
        let preferences = RestAppearancePreferences(focalX: -2, focalY: 3)
        #expect(preferences.focalX == 0)
        #expect(preferences.focalY == 1)
        let decoded = try decode(#"{"focalX":-0.1,"focalY":1.1}"#)
        #expect(decoded.focalX == 0)
        #expect(decoded.focalY == 1)
        for value in [Double.nan, .infinity, -.infinity] {
            let invalid = RestAppearancePreferences(focalX: value, focalY: value)
            #expect(invalid.focalX == 0.5)
            #expect(invalid.focalY == 0.5)
        }
    }

    @Test("Image references permit owned UUID filenames and reject paths and foreign filenames")
    func ownedImageReferences() throws {
        let identifier = "e1bc5ae6-5666-44c4-9cbb-d86105eaef78"
        for suffix in ["jpg", "png", "heic"] {
            let filename = "\(identifier).\(suffix)"
            let preferences = RestAppearancePreferences(
                background: .image,
                ownedImageFilename: filename
            )
            #expect(preferences.background == .image)
            #expect(preferences.ownedImageFilename == filename)
        }
        for filename in [
            "",
            "../\(identifier).jpg",
            "/tmp/\(identifier).png",
            "file:///tmp/a.jpg",
            "holiday.jpg",
            "\(identifier).svg"
        ] {
            let preferences = RestAppearancePreferences(
                background: .image,
                ownedImageFilename: filename
            )
            #expect(preferences.ownedImageFilename == nil)
            #expect(preferences.background == .atmosphere)
            let data = try JSONEncoder().encode([
                "background": "image",
                "ownedImageFilename": filename
            ])
            #expect(try JSONDecoder()
                .decode(RestAppearancePreferences.self, from: data) == preferences)
        }
        #expect(RestAppearancePreferences(background: .image).background == .atmosphere)
    }

    @Test("Sunrise shares a bounded lead interval without implicitly granting wake or battery use")
    func sunrisePolicy() throws {
        for (input, expected) in [(-1, 5), (0, 5), (5, 5), (30, 30), (60, 60), (61, 60)] {
            let preferences = RestAppearancePreferences(sunriseLeadMinutes: input)
            #expect(preferences.sunriseLeadMinutes == expected)
            #expect(!preferences.sunriseWakeEnabled)
            #expect(!preferences.sunriseOnBatteryEnabled)
            #expect(try decode("{\"sunriseLeadMinutes\":\(input)}").sunriseLeadMinutes == expected)
        }
        #expect(!RestAppearancePreferences(sunriseWakeEnabled: true).sunriseOnBatteryEnabled)
        #expect(!RestAppearancePreferences(sunriseOnBatteryEnabled: true).sunriseWakeEnabled)
        #expect(!RestAppearancePreferences(message: "Private message").saverMessageEnabled)
        #expect(!RestAppearancePreferences(saverMessageEnabled: true).sunriseWakeEnabled)
    }

    @MainActor
    @Test("Local preferences survive recreation of their separate store")
    func storeRoundtrip() throws {
        let suiteName = "RestAppearancePreferencesTests.Roundtrip.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = RestAppearancePreferences(message: "Rest well", sunriseWakeEnabled: true)
        let store = RestAppearancePreferencesStore(defaults: defaults)
        #expect(store.load() == RestAppearancePreferences())
        store.save(preferences)
        #expect(RestAppearancePreferencesStore(defaults: defaults).load() == preferences)
    }

    @MainActor
    @Test("Corrupt local storage falls back without altering synchronized settings")
    func corruptStore() throws {
        let suiteName = "RestAppearancePreferencesTests.Corrupt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("invalid JSON".utf8), forKey: "curfew.restAppearancePreferences.v1")
        #expect(RestAppearancePreferencesStore(defaults: defaults)
            .load() == RestAppearancePreferences())
        defaults.set(
            Data(#"{"message":"Recovered"}"#.utf8),
            forKey: "curfew.restAppearancePreferences.v1"
        )
        #expect(RestAppearancePreferencesStore(defaults: defaults).load().message == "Recovered")
    }
}
