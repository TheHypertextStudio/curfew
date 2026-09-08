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

public nonisolated enum BrowserDestinationScope: Codable, Equatable, Hashable, Sendable {
    case origin(String)
    case pathPrefix(origin: String, path: String)

    public var origin: String {
        switch self {
        case .origin(let origin), .pathPrefix(let origin, _):
            origin
        }
    }

    public func allows(_ destination: NormalizedHTTPDestination) -> Bool {
        switch self {
        case .origin(let origin):
            return destination.origin == origin
        case .pathPrefix(let origin, let path):
            guard destination.origin == origin else { return false }
            let prefix = Self.normalizedPrefix(path)
            return destination.path == prefix || destination.path.hasPrefix(prefix + "/")
        }
    }

    private static func normalizedPrefix(_ path: String) -> String {
        guard path != "/" else { return "/" }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
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
