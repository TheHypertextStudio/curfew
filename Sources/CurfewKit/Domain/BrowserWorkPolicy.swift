import Foundation

public nonisolated struct NormalizedHTTPDestination: Codable, Equatable, Hashable, Sendable {
    public nonisolated enum Error: Swift.Error, Equatable {
        case invalidURL
        case unsupportedScheme
        case missingHost
    }

    public let origin: String
    public let path: String

    public init(_ rawValue: String) throws {
        guard var components = URLComponents(string: rawValue) else {
            throw Error.invalidURL
        }
        guard let rawScheme = components.scheme else {
            throw Error.invalidURL
        }
        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw Error.unsupportedScheme
        }
        guard let rawHost = components.host, !rawHost.isEmpty else {
            throw Error.missingHost
        }

        components.scheme = scheme
        components.host = rawHost.lowercased()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        if (scheme == "https" && components.port == 443) ||
            (scheme == "http" && components.port == 80) {
            components.port = nil
        }

        components.percentEncodedPath = components.percentEncodedPath.isEmpty
            ? "/"
            : components.percentEncodedPath
        guard let standardizedURL = components.url?.standardized,
              let normalizedComponents = URLComponents(
                  url: standardizedURL,
                  resolvingAgainstBaseURL: false
              ),
              let host = normalizedComponents.host
        else {
            throw Error.missingHost
        }
        let normalizedPath = normalizedComponents.percentEncodedPath.isEmpty
            ? "/"
            : normalizedComponents.percentEncodedPath
        let port = normalizedComponents.port.map { ":\($0)" } ?? ""
        self.origin = "\(scheme)://\(host)\(port)"
        self.path = normalizedPath
    }

    public var reviewURL: URL {
        guard let url = URL(string: origin + path) else {
            preconditionFailure("A normalized destination must remain a valid URL")
        }
        return url
    }
}

public nonisolated struct BrowserDestinationScope: Codable, Equatable, Hashable, Sendable {
    public nonisolated enum Kind: String, Codable, Equatable, Sendable {
        case origin
        case pathPrefix = "path_prefix"
    }

    public nonisolated enum ValidationError: Error, Equatable {
        case invalidOrigin
        case invalidPathPrefix
    }

    public let kind: Kind
    public let origin: String
    public let path: String?

    private init(kind: Kind, origin: String, path: String?) {
        self.kind = kind
        self.origin = origin
        self.path = path
    }

    public static func validatedOrigin(_ value: String) throws -> Self {
        guard let components = URLComponents(string: value),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath.isEmpty,
              let destination = try? NormalizedHTTPDestination(value),
              value == destination.origin
        else { throw ValidationError.invalidOrigin }
        return Self(kind: .origin, origin: destination.origin, path: nil)
    }

    public static func validatedPathPrefix(_ value: String) throws -> Self {
        guard let components = URLComponents(string: value),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !components.percentEncodedPath.isEmpty,
              components.percentEncodedPath.hasPrefix("/"),
              let destination = try? NormalizedHTTPDestination(value),
              value == destination.origin + destination.path
        else { throw ValidationError.invalidPathPrefix }
        return Self(
            kind: .pathPrefix,
            origin: destination.origin,
            path: destination.path
        )
    }

    public static func validatedPathPrefix(origin: String, path: String) throws -> Self {
        guard !path.isEmpty, path.hasPrefix("/") else {
            throw ValidationError.invalidPathPrefix
        }
        return try validatedPathPrefix(origin + path)
    }

    public func allows(_ destination: NormalizedHTTPDestination) -> Bool {
        guard destination.origin == origin else { return false }
        guard kind == .pathPrefix, let path else { return true }
        if path == "/" {
            return true
        }
        let prefix = path.hasSuffix("/") ? String(path.dropLast()) : path
        return destination.path == prefix || destination.path.hasPrefix(prefix + "/")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let origin = try container.decode(String.self, forKey: .origin)
        switch kind {
        case .origin:
            guard !container.contains(.path) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: "An origin scope cannot contain a path"
                )
            }
            self = try Self.validatedOrigin(origin)
        case .pathPrefix:
            let path = try container.decode(String.self, forKey: .path)
            self = try Self.validatedPathPrefix(origin: origin, path: path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(origin, forKey: .origin)
        try container.encodeIfPresent(path, forKey: .path)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, origin, path
    }
}

public nonisolated enum WorkDestinationSelector: Codable, Equatable, Hashable, Sendable {
    case task(String)
    case project(String)
    case label(String)
}

public nonisolated struct WorkDestinationMapping: Codable, Equatable, Hashable, Identifiable,
    Sendable {
    public let id: String
    public let selector: WorkDestinationSelector
    public let scope: BrowserDestinationScope

    public init(id: String, selector: WorkDestinationSelector, scope: BrowserDestinationScope) {
        self.id = id
        self.selector = selector
        self.scope = scope
    }

    func matches(_ task: DocketActiveWorkTask) -> Bool {
        switch selector {
        case .task(let id):
            task.id == id
        case .project(let id):
            task.project?.id == id
        case .label(let id):
            task.labels.contains { $0.id == id }
        }
    }
}

public nonisolated enum DocketTrackingState: String, Codable, Equatable, Sendable {
    case running
    case paused
    case idle
}

public nonisolated struct DocketActiveWork: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let observedAt: Date
    public let tracking: DocketTrackingState
    public let recordID: String?
    public let task: DocketActiveWorkTask?

    public init(
        schemaVersion: String = "active-work/1",
        observedAt: Date,
        tracking: DocketTrackingState,
        recordID: String?,
        task: DocketActiveWorkTask?
    ) {
        self.schemaVersion = schemaVersion
        self.observedAt = observedAt
        self.tracking = tracking
        self.recordID = recordID
        self.task = task
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, observedAt, tracking, task
        case recordID = "recordId"
    }
}

public nonisolated enum DocketWorkReferenceSource: String, Codable, Equatable, Sendable {
    case taskAttachment = "task_attachment"
    case taskDescription = "task_description"
    case taskProvenance = "task_provenance"
    case projectResource = "project_resource"
}

public nonisolated struct DocketActiveWorkTask: Codable, Equatable, Sendable {
    public nonisolated struct Workspace: Codable, Equatable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public nonisolated struct Project: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let summary: String?

        public init(id: String, name: String, summary: String?) {
            self.id = id
            self.name = name
            self.summary = summary
        }
    }

    public nonisolated struct Label: Codable, Equatable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public nonisolated struct Reference: Codable, Equatable, Sendable {
        public let source: DocketWorkReferenceSource
        public let title: String?
        public let url: String

        public init(source: DocketWorkReferenceSource, title: String?, url: String) {
            self.source = source
            self.title = title
            self.url = url
        }
    }

    public let id: String
    public let organizationID: String
    public let title: String
    public let description: String?
    public let stateType: String
    public let workspace: Workspace
    public let project: Project?
    public let labels: [Label]
    public let references: [Reference]

    public init(
        id: String,
        organizationID: String,
        title: String,
        description: String?,
        stateType: String,
        workspace: Workspace,
        project: Project?,
        labels: [Label],
        references: [Reference]
    ) {
        self.id = id
        self.organizationID = organizationID
        self.title = title
        self.description = description
        self.stateType = stateType
        self.workspace = workspace
        self.project = project
        self.labels = labels
        self.references = references
    }

    public var isTerminal: Bool {
        Self.isTerminal(stateType)
    }

    static func isTerminal(_ stateType: String) -> Bool {
        let normalized = stateType.lowercased().replacingOccurrences(of: "_", with: "-")
        return ["complete", "completed", "canceled", "cancelled", "archived"].contains(normalized)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, stateType, workspace, project, labels, references
        case organizationID = "organizationId"
    }
}
