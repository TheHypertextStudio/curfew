@testable import CurfewKit
import Foundation
import Testing

struct DaemonMaintenanceAdmissionTests {
    private let deviceID = UUID(uuidString: "DFDDE4C3-CFFC-4C76-9E6A-BA2568B8F89C")!
    private let now = ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")!
    private let expiredRemote = Data(
        #"{"enrolledDeviceID":"DFDDE4C3-CFFC-4C76-9E6A-BA2568B8F89C","enrolledUserID":"account-one","highestSequence":2,"pendingResults":[],"resultsByIdempotencyKey":{},"activeLockout":{"kind":"remote_command","lockoutStartedAt":"2026-10-12T07:00:55Z","scheduledUnlockAt":"2026-10-12T07:05:55Z"}}"#
            .utf8
    )
    private let active = Data(
        #"{"kind":"scheduled_time","lockoutStartedAt":"2026-10-12T23:00:00Z","scheduledUnlockAt":"2026-10-13T08:00:00Z"}"#
            .utf8
    )

    @Test("An expired remote deadline does not block maintenance")
    func expiredRemoteIsAccepted() throws {
        try DaemonMaintenanceAdmission.validate(
            remote: expiredRemote, control: nil, user: nil, shadow: nil,
            deviceID: deviceID, now: now
        )
    }

    @Test(
        "Each local deadline source independently blocks helper replacement",
        arguments: [false, true]
    )
    func localDeadlineBlocks(shadow: Bool) {
        #expect(throws: DaemonMaintenanceAdmission.AdmissionError.activeDeadline) {
            try DaemonMaintenanceAdmission.validate(
                remote: expiredRemote, control: nil,
                user: shadow ? nil : active, shadow: shadow ? active : nil,
                deviceID: deviceID, now: now
            )
        }
    }

    @Test("Malformed existing state is not treated as a missing deadline")
    func malformedStateBlocks() {
        #expect(throws: (any Error).self) {
            try DaemonMaintenanceAdmission.validate(
                remote: expiredRemote, control: Data("{}".utf8), user: nil, shadow: nil,
                deviceID: deviceID, now: now
            )
        }
    }

    @Test("A different enrolled device cannot authorize legacy maintenance")
    func differentDeviceBlocks() throws {
        #expect(throws: DaemonMaintenanceAdmission.AdmissionError.wrongDevice) {
            try DaemonMaintenanceAdmission.validate(
                remote: expiredRemote, control: nil, user: nil, shadow: nil,
                deviceID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                now: now
            )
        }
    }

    @Test("Malformed authenticated state cannot downgrade to an inactive legacy record")
    func mixedControlFormatBlocks() {
        let mixed = Data(
            #"{"localStatus":{"activeRecord":{"kind":"scheduled_time","lockoutStartedAt":"2026-10-12T23:00:00Z","scheduledUnlockAt":"2026-10-13T08:00:00Z"},"shutdownIssued":false},"releasedLocalDeadlines":"corrupt","shutdownIssued":false}"#
                .utf8
        )
        #expect(throws: (any Error).self) {
            try DaemonMaintenanceAdmission.validate(
                remote: expiredRemote, control: mixed, user: nil, shadow: nil,
                deviceID: deviceID, now: now
            )
        }
    }

    @Test("Both supported control formats preserve active enforcement", arguments: [false, true])
    func activeControlBlocks(authenticated: Bool) {
        let legacy = #"{"activeRecord":{"kind":"scheduled_time","lockoutStartedAt":"2026-10-12T23:00:00Z","scheduledUnlockAt":"2026-10-13T08:00:00Z"},"shutdownIssued":false}"#
        let raw = authenticated
            ? #"{"localStatus":\#(legacy),"releasedLocalDeadlines":[]}"# : legacy
        #expect(throws: DaemonMaintenanceAdmission.AdmissionError.activeDeadline) {
            try DaemonMaintenanceAdmission.validate(
                remote: expiredRemote, control: Data(raw.utf8), user: nil, shadow: nil,
                deviceID: deviceID, now: now
            )
        }
    }
}
