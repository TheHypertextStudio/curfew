import AppKit
import CurfewKit
import Foundation

@MainActor
extension AccountEnrollmentController {
    static func settingsController() -> AccountEnrollmentController {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CURFEW_DEMO_FIXTURE"] == "1" {
                let services = DemoAccountServices()
                return AccountEnrollmentController(
                    secretStore: DemoAccountSecretStore(), oauth: services, devices: services
                )
            }
        #endif
        return AccountEnrollmentController()
    }
}

#if DEBUG
    /// Capture controls cannot read Keychain checkpoints or contact account services.
    private final class DemoAccountSecretStore: AccountSecretStoring {
        private var values: [String: Data] = [:]
        func data(for account: String) throws -> Data? {
            values[account]
        }

        func save(_ data: Data, for account: String) throws {
            values[account] = data
        }

        func delete(_ account: String) throws {
            values.removeValue(forKey: account)
        }
    }

    @MainActor
    private final class DemoAccountServices: AccountOAuthEnrolling, AccountDeviceEnrolling {
        func signIn(
            presentationWindow _: NSWindow?,
            authorizationURLHandler _: @escaping @MainActor (URL) -> Void
        ) async throws -> AccountOAuthGrant {
            throw CancellationError()
        }

        func cancelSignIn() {}
        func enroll(grant _: AccountOAuthGrant, deviceID _: UUID) async throws
            -> NativeAccountEnrollmentState {
            throw CancellationError()
        }

        func resumeRecoverySetup(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
            async throws -> NativeAccountEnrollmentState {
            throw CancellationError()
        }

        func resumeDeviceRegistration(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
            async throws -> NativeAccountEnrollmentState {
            throw CancellationError()
        }

        func restore(recoveryKey _: String, enrollment _: AccountDeviceEnrollment)
            async throws -> AccountDeviceEnrollment {
            throw CancellationError()
        }
    }

    @MainActor
    final class DemoPresenceSensor: PersonPresenceSensing {
        var authorization: CameraAuthorization = .notDetermined
        var isRunning = false
        var latestObservation: PersonObservation {
            .never
        }

        func start() {
            isRunning = authorization.permitsCapture
        }

        func stop() {
            isRunning = false
        }

        func requestAuthorization(completion: @escaping @MainActor (CameraAuthorization) -> Void) {
            authorization = .authorized
            completion(authorization)
        }
    }
#endif
