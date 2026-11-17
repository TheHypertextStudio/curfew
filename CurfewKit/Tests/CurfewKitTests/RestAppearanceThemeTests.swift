@testable import CurfewKit
import Foundation
import Testing

/// The theme's voice and the person's own words: validated, decoded field by
/// field, and carried over from records saved before the theme editor.
struct RestAppearanceThemeTests {
    private func decode(_ json: String) throws -> RestAppearancePreferences {
        try JSONDecoder().decode(RestAppearancePreferences.self, from: Data(json.utf8))
    }

    @Test("Own words trim, stay on one line and truncate by extended grapheme Character")
    func customLineNormalization() throws {
        let limit = VoiceCustomLines.maximumLength
        let grapheme = "👨‍👩‍👧‍👦"
        let expected = String(repeating: grapheme, count: limit)
        let input = " \n" + expected + "e\u{301}end\t "
        func lock(_ text: String) -> RestAppearancePreferences {
            RestAppearancePreferences(customLines: VoiceCustomLines([.lockedHeadline: text]))
        }
        #expect(lock(input).message == expected)
        #expect(lock(input).message.count == limit)
        let exactly = String(repeating: "e\u{301}", count: limit)
        #expect(lock(exactly).message == exactly)
        #expect(lock(" \n\t ").message.isEmpty)
        #expect(lock(" \n\t ").customLines.isEmpty)
        #expect(lock("Go home.\nNow.").message == "Go home. Now.")
        let encoded = try JSONEncoder().encode(["customLines": ["lockedHeadline": input]])
        #expect(try JSONDecoder().decode(RestAppearancePreferences.self, from: encoded)
            .message == expected)
    }

    @Test("A record saved before the theme editor loads with its message as the lock's words")
    func legacyRecordMigrates() throws {
        let legacy = try decode(
            #"""
            {
              "background": "solid",
              "palette": "coolTwilight",
              "solidRed": 0.2, "solidGreen": 0.3, "solidBlue": 0.4,
              "clockStyle": "serif",
              "clockPosition": "lowerLeft",
              "staticBackground": true,
              "message": "  Go see the kids.  ",
              "focalX": 0.5, "focalY": 0.5,
              "saverMessageEnabled": true,
              "sunriseWakeEnabled": true,
              "sunriseLeadMinutes": 20,
              "sunriseOnBatteryEnabled": false
            }
            """#
        )
        #expect(legacy.background == .solid)
        #expect(legacy.palette == .coolTwilight)
        #expect(legacy.clockStyle == .serif)
        #expect(legacy.clockPosition == .lowerLeft)
        #expect(legacy.staticBackground)
        #expect(legacy.voice == .standard)
        #expect(legacy.customLines[.lockedHeadline] == "Go see the kids.")
        #expect(legacy.message == "Go see the kids.")
        #expect(legacy.voicePack.lockedHeadline == "Go see the kids.")
        #expect(legacy.saverMessageEnabled)
        #expect(legacy.sunriseWakeEnabled)
        #expect(legacy.sunriseLeadMinutes == 20)
        // Saved again, it reads back the same, with no message key left behind.
        let data = try JSONEncoder().encode(legacy)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["message"] == nil)
        #expect(try JSONDecoder().decode(RestAppearancePreferences.self, from: data) == legacy)
        // A long message keeps its first sixty characters.
        let long = String(repeating: "a", count: 140)
        #expect(try decode("{\"message\":\"\(long)\"}").message.count == 60)
        // Words written in the editor win over an older message.
        let both = try decode(
            #"{"message":"Old","customLines":{"lockedHeadline":"New"}}"#
        )
        #expect(both.message == "New")
    }

    @Test("The voice and the own words decode on their own and drop what they cannot read")
    func voiceDecoding() throws {
        #expect(try decode(#"{"voice":"gentle"}"#).voice == .gentle)
        #expect(try decode(#"{"voice":"playful"}"#).voicePack == .playful)
        #expect(try decode(#"{"voice":"default"}"#).voice == .standard)
        #expect(try decode(#"{"voice":"shouty","palette":"warmAmber"}"#).voice == .standard)
        #expect(try decode(#"{"voice":"shouty","palette":"warmAmber"}"#).palette == .warmAmber)
        let damaged = try decode(
            #"""
            {"customLines": {"lastMinute": "Off you go.", "unknownLine": "x", "thirtyMinutes": 3}}
            """#
        )
        #expect(damaged.customLines == VoiceCustomLines([.lastMinute: "Off you go."]))
        #expect(try decode(#"{"customLines": "nope"}"#).customLines.isEmpty)
        let gentle = try decode(
            #"{"voice":"gentle","customLines":{"sunriseGreeting":"Hello, you."}}"#
        )
        #expect(gentle.voicePack.gateHeadline == "Hello, you.")
        #expect(gentle.voicePack.gateQuestion == VoicePack.gentle.gateQuestion)
    }
}
