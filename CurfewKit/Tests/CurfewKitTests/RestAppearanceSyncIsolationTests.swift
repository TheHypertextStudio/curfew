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
        let before = try JSONEncoder().encode(settingsStore.load())
        let beforeObject = try #require(JSONSerialization.jsonObject(with: before) as? NSDictionary)
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
        let after = try JSONEncoder().encode(settingsStore.load())
        let afterObject = try #require(JSONSerialization.jsonObject(with: after) as? NSDictionary)
        #expect(beforeObject == afterObject)
        for key in ["restAppearance", "restAppearancePreferences", "message", "saverMessageEnabled", "sunriseWakeEnabled", "sunriseLeadMinutes", "sunriseOnBatteryEnabled"] {
            #expect(afterObject[key] == nil)
        }
        #expect(!String(decoding: after, as: UTF8.self).contains(local.message))
        settingsStore.save(.default)
        #expect(RestAppearancePreferencesStore(defaults: defaults).load() == local)
    }

}
