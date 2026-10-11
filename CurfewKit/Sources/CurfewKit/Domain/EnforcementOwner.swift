import Foundation

/// Flavor-neutral record shared by the app and its privileged daemon.
public nonisolated struct EnforcementOwner: Codable, Equatable, Sendable {
    public let flavor: String
    public let bundleIdentifier: String
    public let displayName: String
    public let processIdentifier: Int32
    public let acquiredAt: Date

    public init(
        flavor: String,
        bundleIdentifier: String,
        displayName: String,
        processIdentifier: Int32,
        acquiredAt: Date
    ) {
        self.flavor = flavor
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.processIdentifier = processIdentifier
        self.acquiredAt = acquiredAt
    }

    public var enforcementPriority: Int {
        CurfewFlavor(rawValue: flavor)?.enforcementPriority ?? Int.min
    }

    /// A forged owner must not gain another flavor's priority by changing a
    /// string in the shared user-writable record.
    public var hasRecognizedIdentity: Bool {
        guard let flavor = CurfewFlavor(rawValue: flavor) else { return false }
        return bundleIdentifier == SharedPaths.defaultsSuiteName(for: flavor)
    }
}

public nonisolated enum EnforcementOwnerStore {
    public static func load(from url: URL) -> EnforcementOwner? {
        guard let data = try? BoundedRegularFileReader.read(url, maximumBytes: 4096) else {
            return nil
        }
        return try? JSONDecoder().decode(EnforcementOwner.self, from: data)
    }
}
