import Foundation

// TEMPORARY TDD scaffold: deliberately does not persist preferences.
@MainActor
public final class RestAppearancePreferencesStore {
    public init(defaults: UserDefaults) {}

    public func load() -> RestAppearancePreferences {
        RestAppearancePreferences()
    }

    public func save(_ preferences: RestAppearancePreferences) {}
}
