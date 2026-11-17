import CurfewKit
import Foundation
import ServiceManagement
import UserNotifications

/// Live state of an optional permission on setup step 2.
enum SetupPermissionStatus: Equatable {
    case notAsked
    case allowed
    case off
}

/// Reads and requests notification permission. Requests happen only from
/// setup step 2, when the person presses Allow.
@MainActor
protocol NotificationPermissionProviding {
    func status() async -> SetupPermissionStatus
    func request() async -> SetupPermissionStatus
}

struct SystemNotificationPermission: NotificationPermissionProviding {
    func status() async -> SetupPermissionStatus {
        guard !RuntimeEnvironment.isUnitTestHost else { return .notAsked }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.status(for: settings.authorizationStatus)
    }

    func request() async -> SetupPermissionStatus {
        guard !RuntimeEnvironment.isUnitTestHost else { return .notAsked }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        return await status()
    }

    nonisolated static func status(for authorization: UNAuthorizationStatus)
        -> SetupPermissionStatus {
        switch authorization {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .off
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }
}

/// Fixed answers for previews and snapshots.
struct FixedNotificationPermission: NotificationPermissionProviding {
    var value: SetupPermissionStatus

    func status() async -> SetupPermissionStatus {
        value
    }

    func request() async -> SetupPermissionStatus {
        value
    }
}

/// The Curfew helper's state as setup describes it.
enum SetupHelperStatus: Equatable {
    case notInstalled
    case installing
    case needsApproval
    case installed
    case failed

    static func resolve(
        daemon: SMAppService.Status,
        connection: PrivilegedHelperManager.ConnectionState,
        isInstalling: Bool
    ) -> SetupHelperStatus {
        if isInstalling {
            return .installing
        }
        switch daemon {
        case .enabled: return .installed
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound:
            return connection == .registrationFailed ? .failed : .notInstalled
        @unknown default: return .notInstalled
        }
    }
}
