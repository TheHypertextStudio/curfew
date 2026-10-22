import CurfewKit
import Foundation

extension CurfewAppModel {
    /// Companion-only schedule presentation; never a source of restriction authority.
    /// Neutral until the native configured-occurrence contracts execute.
    var restCompanionSnapshot: RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1, expiresAt: .distantPast, appearance: restAppearance,
            lockDate: nil, unlockDate: nil
        )
    }

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
