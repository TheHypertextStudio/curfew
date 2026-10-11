import Foundation

public nonisolated struct BrowserIntegrationSettings: Codable, Equatable, Sendable {
    public private(set) var docketConnectedOnce: Bool
    public private(set) var chromeConnectedOnce: Bool
    public private(set) var enforcementEnabled: Bool
    public private(set) var mappings: [WorkDestinationMapping]

    public init(
        docketConnectedOnce: Bool = false,
        chromeConnectedOnce: Bool = false,
        enforcementEnabled: Bool = false,
        mappings: [WorkDestinationMapping] = []
    ) {
        self.docketConnectedOnce = docketConnectedOnce
        self.chromeConnectedOnce = chromeConnectedOnce
        self.enforcementEnabled = enforcementEnabled && docketConnectedOnce && chromeConnectedOnce
        self.mappings = mappings.compactMap {
            try? WorkDestinationMapping.validated(
                id: $0.id,
                selector: $0.selector,
                scope: $0.scope
            )
        }
    }

    public var setupIsComplete: Bool {
        docketConnectedOnce && chromeConnectedOnce
    }

    public mutating func recordDocketConnection() {
        docketConnectedOnce = true
    }

    public mutating func recordChromeConnection() {
        chromeConnectedOnce = true
    }

    @discardableResult
    public mutating func setEnforcementEnabled(_ enabled: Bool) -> Bool {
        guard !enabled || setupIsComplete else {
            enforcementEnabled = false
            return false
        }
        enforcementEnabled = enabled
        return true
    }

    @discardableResult
    public mutating func addMapping(
        selector: WorkDestinationSelector,
        destination: String,
        scopeKind: BrowserDestinationScope.Kind,
        id: String = UUID().uuidString.lowercased()
    ) throws -> WorkDestinationMapping {
        let mapping = try WorkDestinationMapping.validated(
            id: id,
            selector: selector,
            destination: destination,
            scopeKind: scopeKind
        )
        mappings.append(mapping)
        return mapping
    }

    public mutating func removeMapping(id: String) {
        mappings.removeAll { $0.id == id }
    }
}

@MainActor
public final class BrowserIntegrationSettingsStore {
    private static let key = "curfew.browserIntegrationSettings.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> BrowserIntegrationSettings {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? decoder.decode(BrowserIntegrationSettings.self, from: data)
        else { return BrowserIntegrationSettings() }
        return BrowserIntegrationSettings(
            docketConnectedOnce: decoded.docketConnectedOnce,
            chromeConnectedOnce: decoded.chromeConnectedOnce,
            enforcementEnabled: decoded.enforcementEnabled,
            mappings: decoded.mappings
        )
    }

    public func save(_ settings: BrowserIntegrationSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
