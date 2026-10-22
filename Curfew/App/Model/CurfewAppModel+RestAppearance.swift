import CurfewKit

extension CurfewAppModel {
    /// A lightweight local-store adapter; appearance never enters synced settings.
    var restAppearanceStore: RestAppearancePreferencesStore {
        RestAppearancePreferencesStore(defaults: settingsStore.storageDefaults)
    }
}
