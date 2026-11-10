import Foundation

/// Persists local rest preferences separately from account-synchronized settings.
@MainActor
public final class RestAppearancePreferencesStore {
    private static let key = "curfew.restAppearancePreferences.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Missing and corrupt records use the migration defaults.
    public func load() -> RestAppearancePreferences {
        guard let data = defaults.data(forKey: Self.key),
              let preferences = try? JSONDecoder().decode(
                  RestAppearancePreferences.self,
                  from: data
              )
        else { return RestAppearancePreferences() }
        return preferences
    }

    public func save(_ preferences: RestAppearancePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
