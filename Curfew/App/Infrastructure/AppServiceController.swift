import ServiceManagement

protocol AppServiceControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func unregisterAndWait() async throws
}

extension AppServiceControlling {
    func unregisterAndWait() async throws {
        try unregister()
    }
}

struct SystemAppServiceController: AppServiceControlling {
    let service: SMAppService

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func unregisterAndWait() async throws {
        try await service.unregister()
    }
}

extension SMAppService.Status {
    /// Short human-readable description used for log messages.
    var debugDescription: String {
        switch self {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}
