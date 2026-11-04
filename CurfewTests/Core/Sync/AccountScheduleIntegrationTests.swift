@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testFirstAccountPullQueuesRemoteScheduleWithoutReplacingDeviceIdentity() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let keys = try XCTUnwrap(AccountDeviceKeyStore(secretStore: fixture.secrets)
            .load(deviceID: fixture.deviceID))
        let enrollment = CurfewKit.AccountDeviceEnrollment(
            deviceID: fixture.deviceID, keyEpoch: 1,
            enrolledAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let (records, peers) = try Self.integrationRecords(deviceID: fixture.deviceID, keys: keys)
        NativeTransportURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/sync/records" {
                return (200, records)
            }
            if request.httpMethod == "GET", request.url?.path == "/sync/devices" {
                return (200, peers)
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)
        let suite = "Curfew.AccountScheduleIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = Self.integrationModel(
            defaults: defaults,
            enrollment: enrollment,
            transport: transport
        )
        let original = model.settings.schedule

        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertEqual(model.settings.accountSync.enrollment, enrollment)
        XCTAssertEqual(model.settings.schedule, original)
        XCTAssertEqual(
            model.settings.pendingScheduleChange?.proposedSchedule,
            Self.integrationSchedule(unlockMinutes: 300, weekendsOff: false)
        )
        XCTAssertEqual(model.settings.pendingScheduleChange?.classification, .weaker)
        transport.disconnect()
    }

    private static func integrationRecords(
        deviceID: UUID, keys: AccountDeviceKeyMaterial
    ) throws -> (Data, Data) {
        let recordID = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36"))
        let record = try AccountRecordCrypto().seal(
            IntegrationScheduleFixture(), namespace: .accountSettings, recordID: recordID,
            version: 1, writerCounter: 1, writerDeviceID: deviceID, keyEpoch: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000), keys: keys
        )
        let key = CurfewProtocols.AccountPublicKeyJWK(
            crv: .p256, kty: .ec, x: keys.signingPublicKey.x, y: keys.signingPublicKey.y
        )
        let agreement = CurfewProtocols.AccountPublicKeyJWK(
            crv: .p256, kty: .ec, x: keys.encryptionPublicKey.x, y: keys.encryptionPublicKey.y
        )
        let peer = CurfewProtocols.AccountDeviceEnrollment(
            deviceID: deviceID.uuidString.lowercased(), encryptionPublicKeyJwk: agreement,
            enrolledAt: "2026-08-10T14:00:00Z", keyEpoch: 1, protocolVersion: "0.0",
            signingPublicKeyJwk: key
        )
        return try (JSONEncoder().encode([record]), JSONEncoder().encode([peer]))
    }

    private static func integrationModel(
        defaults: UserDefaults, enrollment: CurfewKit.AccountDeviceEnrollment,
        transport: NativeAccountSyncTransport
    ) -> CurfewAppModel {
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.accountSync = AccountSyncConfiguration(enrollment: enrollment, releasePolicy: nil)
        settings.schedule = Self.integrationSchedule(unlockMinutes: 330, weekendsOff: true)
        store.save(settings)
        store.saveAutomaticScheduleConsent(true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CurfewAppModel(
            settingsStore: store, appRouter: AppRouterSpy(), flavor: .production,
            featureFlags: FeatureFlags(
                widgetKitEnabled: false,
                cloudSyncEnabled: false,
                mcpServerEnabled: false,
                privilegedHelperEnabled: false,
                calendarEnabled: false
            ),
            activityRecorder: NullActivityRecording(),
            accountSyncEngine: AccountSyncEngine(transport: transport),
            lockoutDeadlineStore: .ephemeralForTesting(), enforcementClock: { now }
        )
    }

    private static func integrationSchedule(
        unlockMinutes: Int, weekendsOff: Bool
    ) -> WeeklySchedule {
        WeeklySchedule(rules: Dictionary(uniqueKeysWithValues: Weekday.allCases.map { day in
            (day, DayRule(
                isDayOff: weekendsOff && (day == .saturday || day == .sunday),
                lockMinutes: 1320,
                unlockMinutes: unlockMinutes
            ))
        }))
    }
}

private struct IntegrationScheduleFixture: Encodable {
    private struct Day: Encodable {
        let isDayOff = false
        let lockTime = "22:00"
        let mode = "time"
        let unlockTime = "05:00"
    }

    private let schemaVersion = 1
    private let days = Dictionary(uniqueKeysWithValues: [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ].map { ($0, Day()) })
}
