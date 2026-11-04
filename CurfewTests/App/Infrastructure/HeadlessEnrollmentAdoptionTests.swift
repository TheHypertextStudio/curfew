import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import XCTest

@MainActor
final class HeadlessEnrollmentAdoptionTests: XCTestCase {
    func testForgedNotificationCannotAdoptAnotherIdentity() throws {
        let store = AdoptionCallbackRouter()
        let pending = AccountEnrollmentPendingStore(secretStore: store)
        let ready = AccountDeviceEnrollment(deviceID: UUID(), keyEpoch: 1, enrolledAt: Date())
        let other = AccountDeviceEnrollment(deviceID: UUID(), keyEpoch: 1, enrolledAt: Date())
        try pending.markReady(ready)
        try store.save(JSONEncoder().encode(other), for: "headless-account-activation")
        let model = makeModel()
        let delegate = AppDelegate(callbackRouter: store)
        delegate.model = model

        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )
        XCTAssertNil(model.settings.accountSync.enrollment)
        try store.save(JSONEncoder().encode(ready), for: "headless-account-activation")
        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )

        XCTAssertEqual(model.settings.accountSync.enrollment, ready)
        XCTAssertEqual(model.settingsStore.load().accountSync.enrollment, ready)
        XCTAssertNil(try store.data(for: "headless-account-activation"))
    }

    func testInterruptedCleanupConsumesMarkerWithoutReplacingAnEnrolledDevice() throws {
        let store = AdoptionCallbackRouter()
        let pending = AccountEnrollmentPendingStore(secretStore: store)
        let ready = AccountDeviceEnrollment(deviceID: UUID(), keyEpoch: 1, enrolledAt: Date())
        try pending.markReady(ready)
        try store.save(JSONEncoder().encode(ready), for: "headless-account-activation")
        let model = makeModel()
        let other = AccountDeviceEnrollment(deviceID: UUID(), keyEpoch: 1, enrolledAt: Date())
        model.settings.accountSync.enrollment = other
        let delegate = AppDelegate(callbackRouter: store)
        delegate.model = model

        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )
        XCTAssertEqual(model.settings.accountSync.enrollment, other)
        XCTAssertNotNil(try store.data(for: "headless-account-activation"))
        model.settings.accountSync.enrollment = ready
        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )
        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )

        XCTAssertEqual(model.settings.accountSync.enrollment, ready)
        XCTAssertNil(try store.data(for: "headless-account-activation"))
    }

    private func makeModel() -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            flavor: .production,
            featureFlags: FeatureFlags(
                widgetKitEnabled: false,
                cloudSyncEnabled: false,
                mcpServerEnabled: false,
                privilegedHelperEnabled: false,
                calendarEnabled: false
            ),
            activityRecorder: NullActivityRecording(),
            accountSyncEngine: AccountSyncEngine(transport: NoOpAccountSyncTransport()),
            lockoutDeadlineStore: LockoutDeadlineStore(
                recordURL: root.appendingPathComponent("deadline")
            ),
            accountWakeLedgerStore: AccountWakeLedgerStore(
                recordURL: root.appendingPathComponent("wake")
            ),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true),
            runtimeStateStore: EnforcementRuntimeStateStore()
        )
    }
}

private final nonisolated class AdoptionCallbackRouter:
    AccountOAuthCallbackRouting, AccountSecretStoring {
    private let store = EnrollmentRecoveryMemorySecretStore()

    @MainActor
    func register(
        expectedState _: String,
        expectedRedirectURI _: String,
        handler _: @escaping @MainActor (URL) -> Void
    ) throws -> UUID {
        UUID()
    }

    @MainActor
    func unregister(_: UUID) {}

    @MainActor
    func route(_: URL) -> Bool {
        false
    }

    func data(for account: String) throws -> Data? {
        try store.data(for: account)
    }

    func save(_ data: Data, for account: String) throws {
        try store.save(data, for: account)
    }

    func delete(_ account: String) throws {
        try store.delete(account)
    }
}
