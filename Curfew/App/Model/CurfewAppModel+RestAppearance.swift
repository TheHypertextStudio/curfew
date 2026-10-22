import CurfewKit
import Foundation

extension CurfewAppModel {
    var restBackgroundDirectory: URL {
        isDemoSession
            ? FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-demo-rest-backgrounds")
            : SharedPaths.applicationSupport.appendingPathComponent("rest-backgrounds")
    }

    /// A lightweight local-store adapter; appearance never enters synced settings.
    var restAppearanceStore: RestAppearancePreferencesStore {
        RestAppearancePreferencesStore(defaults: settingsStore.storageDefaults)
    }
}
