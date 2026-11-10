@testable import CurfewKit
import Foundation
import Testing

struct RestAppearanceSyncIsolationTests {
    @MainActor
    @Test("A separate local store survives recreation without changing synchronized settings")
    func storeIsolationAndRecreation() throws {
        let suiteName = "RestAppearancePreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = CurfewSettingsStore(defaults: defaults)
        settingsStore.save(.default)
        let beforeSettings = settingsStore.load()
        let before = try #require(defaults.data(forKey: "curfew.settings.v1"))
        let local = RestAppearancePreferences(
            message: "Local private message",
            saverMessageEnabled: true,
            sunriseWakeEnabled: true,
            sunriseLeadMinutes: 15,
            sunriseOnBatteryEnabled: true
        )
        let store = RestAppearancePreferencesStore(defaults: defaults)
        #expect(store.load() == RestAppearancePreferences())
        store.save(local)
        #expect(RestAppearancePreferencesStore(defaults: defaults).load() == local)
        let after = try #require(defaults.data(forKey: "curfew.settings.v1"))
        #expect(after == before)
        #expect(settingsStore.load() == beforeSettings)
        let afterObject = try #require(JSONSerialization.jsonObject(with: after) as? NSDictionary)
        for key in [
            "restAppearance",
            "restAppearancePreferences",
            "message",
            "saverMessageEnabled",
            "sunriseWakeEnabled",
            "sunriseLeadMinutes",
            "sunriseOnBatteryEnabled"
        ] {
            #expect(afterObject[key] == nil)
        }
        let encodedSettings = try #require(String(bytes: after, encoding: .utf8))
        #expect(!encodedSettings.contains(local.message))
        settingsStore.save(.default)
        #expect(RestAppearancePreferencesStore(defaults: defaults).load() == local)
    }
}
