@testable import Curfew
import Foundation
import Testing

/// The *store-level* consent fallbacks for camera presence detection.
///
/// ``PresenceDetectionPolicyTests`` covers the decoder itself — the factory
/// default, a payload predating the feature, a partial presence object. This
/// suite covers the paths that go through ``CurfewSettingsStore/load()``,
/// which is where `PresenceDetectionPolicy`'s doc comment makes its broadest
/// promise: that a fresh install *and a corrupted preferences file* both
/// resolve to a camera that does not turn on.
///
/// The corrupt-blob case is the one worth having. `load()` swallows a decode
/// failure and substitutes `CurfewSettings.default`, so the safety of that
/// path rests entirely on the default being camera-off — a fact no test
/// asserted before this one.
@MainActor
struct PresenceStoreFallbackTests {
    /// The key `CurfewSettingsStore` persists under. Duplicated from the
    /// store's private `Key` enum on purpose: it is an on-disk contract, and a
    /// test that plants a corrupt value has to plant it where `load()` looks.
    private static let settingsDefaultsKey = "curfew.settings.v1"

    private func makeStore() -> (store: CurfewSettingsStore, defaults: UserDefaults) {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return (CurfewSettingsStore(defaults: defaults), defaults)
    }

    @Test("A fresh install — no persisted settings at all — reads back camera-off")
    func absentSettingsReadBackCameraOff() {
        let (store, _) = makeStore()

        #expect(store.load() == .default)
        #expect(!store.load().presence.cameraEnabled)
    }

    @Test("A corrupt preferences value falls back to camera-off, not to a running camera")
    func corruptSettingsBlobIsCameraOff() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not json".utf8), forKey: Self.settingsDefaultsKey)

        #expect(store.load() == .default)
        #expect(!store.load().presence.cameraEnabled)
    }

    @Test("A settings blob whose presence value is the wrong type reads back camera-off")
    func malformedPresenceValueIsCameraOff() throws {
        let (store, defaults) = makeStore()
        var enabled = CurfewSettings.default
        enabled.presence.cameraEnabled = true
        let encoded = try JSONEncoder().encode(enabled)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        // Hand-edited into nonsense. The whole blob now fails to decode, so
        // `load()` falls back — and the fallback must not inherit the `true`
        // that was sitting in the file a moment ago.
        object["presence"] = "camera-please"
        defaults.set(
            try JSONSerialization.data(withJSONObject: object),
            forKey: Self.settingsDefaultsKey
        )

        #expect(!store.load().presence.cameraEnabled)
    }

    @Test("An explicit stored consent still survives the store, so the fallbacks are not vacuous")
    func explicitConsentSurvivesTheStore() {
        let (store, _) = makeStore()
        var settings = CurfewSettings.default
        settings.presence.cameraEnabled = true
        store.save(settings)

        #expect(store.load().presence.cameraEnabled)
    }
}
