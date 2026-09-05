@testable import Curfew
import Foundation
import Testing

@MainActor
struct AccountLifecycleWiringTests {
    @Test("Curfew Account enrollment makes account sync canonical over CloudKit")
    func accountEnrollmentSuppressesCloudKit() throws {
        let cloud = CloudKitSyncEngine()
        let account = try configuration(releasePolicy: .wakeCampaign(
            campaignTemplateID: UUID(),
            timeZone: "America/Los_Angeles",
            localStartTime: "07:30"
        ))
        let model = makeModel(accountSync: account, cloudKitSyncEngine: cloud)
        model.licenseGate.testInjectActivatedKey(LicenseKey(
            email: "tester@example.com",
            product: "curfew-pro",
            orderID: "account-sync-canonical",
            issuedAt: Date()
        ))

        model.reconcileProGatedModules()

        #expect(model.accountSyncEngine.isActive)
        #expect(!cloud.isActive)
    }

    @Test("Authenticated daemon result immediately presents the enrolled device lockout")
    func authenticatedRemoteResultPresentsLockout() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deviceID = try #require(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let account = try configuration(
            deviceID: deviceID,
            enrolledAt: now.addingTimeInterval(-300)
        )
        let transport = RemoteResultTransportSpy()
        let model = makeModel(
            accountSync: account,
            accountSyncEngine: AccountSyncEngine(transport: transport)
        )
        model.currentTime = now
        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.licenseGate.testInjectActivatedKey(LicenseKey(
            email: "tester@example.com",
            product: "curfew-pro",
            orderID: "remote-result-lockout",
            issuedAt: now
        ))
        model.reconcileProGatedModules()

        transport.receive(RemoteCommandResult(
            commandID: UUID(),
            deviceID: deviceID,
            sequence: 1,
            stage: .applied,
            resolvedAt: now,
            appliedDeadline: now.addingTimeInterval(1800)
        ))

        #expect(model.state.phase == .locked)
        #expect(model.state.unlockDate == now.addingTimeInterval(1800))
        #expect(model.lockoutDeadlineStore.load()?.kind == .remoteCommand)
    }

    @Test("A daemon-applied remote deadline supersedes a local Convince Me override")
    func remoteDeadlineSupersedesLocalOverride() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = try makeModel(accountSync: configuration())
        model.currentTime = now
        model.overrideUntil = now.addingTimeInterval(3600)
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 60,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.lockoutDeadlineStore.save(LockoutDeadlineRecord(
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(1800),
            kind: .remoteCommand
        ))

        model.enforceDurableDeadlineIfActive()

        #expect(model.state.phase == .locked)
        #expect(model.state.unlockDate == now.addingTimeInterval(1800))
    }

    @Test("A schedule edit immediately publishes a new remote eligibility snapshot")
    func scheduleEditImmediatelyInvalidatesRemoteEligibility() throws {
        let transport = RemoteResultTransportSpy()
        let account = try configuration()
        let model = makeModel(
            accountSync: account,
            accountSyncEngine: AccountSyncEngine(transport: transport)
        )
        model.licenseGate.testInjectActivatedKey(LicenseKey(
            email: "tester@example.com",
            product: "curfew-pro",
            orderID: "schedule-eligibility",
            issuedAt: model.currentTime
        ))
        model.reconcileProGatedModules()
        let publicationCountBeforeEdit = transport.publishedReports.count
        model.settings.schedule.rules[.monday] = .weekendDefault

        #expect(transport.publishedReports.count == publicationCountBeforeEdit + 1)
        #expect(
            transport.publishedReports.last?.scheduleDigest
                == DeviceStatusReport.scheduleDigest(for: model.settings.schedule)
        )
    }

    private func configuration(
        deviceID: UUID = UUID(),
        enrolledAt: Date = Date(),
        releasePolicy: MorningReleasePolicy? = nil
    ) throws -> AccountSyncConfiguration {
        try AccountSyncConfiguration(
            enrollment: AccountDeviceEnrollment(
                deviceID: deviceID,
                keyEpoch: 1,
                enrolledAt: enrolledAt
            ),
            releasePolicy: releasePolicy
        )
    }

    private func makeModel(
        accountSync: AccountSyncConfiguration,
        accountSyncEngine: AccountSyncEngine? = nil,
        cloudKitSyncEngine: CloudKitSyncEngine = CloudKitSyncEngine()
    ) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.accountSync = accountSync
        let store = CurfewSettingsStore(defaults: defaults)
        store.save(settings)
        let deadlineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-deadline-\(UUID().uuidString).json")
        return CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            featureFlags: FeatureFlags(
                widgetKitEnabled: false,
                cloudSyncEnabled: true,
                mcpServerEnabled: false,
                privilegedHelperEnabled: false,
                calendarEnabled: false
            ),
            activityRecorder: NullActivityRecording(),
            cloudKitSyncEngine: cloudKitSyncEngine,
            accountSyncEngine: accountSyncEngine,
            idleWatcher: IdleWatcher(source: StubAccountIdleSource(), idleThresholdSeconds: 300),
            lockoutDeadlineStore: LockoutDeadlineStore(recordURL: deadlineURL),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
    }
}

@MainActor
private final class RemoteResultTransportSpy: AccountSyncTransporting {
    private var onRemoteCommandResult: ((RemoteCommandResult) -> Void)?
    private(set) var publishedReports: [DeviceStatusReport] = []

    func connect(
        deviceID _: UUID,
        onWakeStatus _: @escaping (AccountWakeStatusUpdate) -> Void,
        onRemoteOverride _: @escaping (AccountRemoteOverride) -> Void,
        onRemoteCommandResult: @escaping (RemoteCommandResult) -> Void,
        onFailure _: @escaping (String) -> Void
    ) {
        self.onRemoteCommandResult = onRemoteCommandResult
    }

    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID _: UUID) {
        publishedReports.append(report)
    }

    func disconnect() {
        onRemoteCommandResult = nil
    }

    func receive(_ result: RemoteCommandResult) {
        onRemoteCommandResult?(result)
    }
}

private final class StubAccountIdleSource: IdleTimeSource {
    func secondsSinceLastInput() -> TimeInterval {
        0
    }
}
