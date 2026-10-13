import Foundation

/// Validates strictly decoded maintenance evidence; only an absent file may
/// become nil. The caller must establish file trust and quiesce producers first.
public enum DaemonMaintenanceAdmission {
    public enum AdmissionError: Error, Equatable {
        case activeDeadline, invalidState, wrongDevice
    }

    public static func validate(
        remote: Data, control: Data?, user: Data?, shadow: Data?, deviceID: UUID, now: Date
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteState = try decoder.decode(DaemonRemoteCommandState.self, from: remote)
        guard remoteState.enrolledDeviceID == deviceID else { throw AdmissionError.wrongDevice }
        guard remoteState.highestSequence >= 0,
              let userID = remoteState.enrolledUserID, !userID.isEmpty,
              now.timeIntervalSinceReferenceDate.isFinite else {
            throw AdmissionError.invalidState
        }
        try requireExpired(remoteState.activeLockout, now: now)
        for data in [user, shadow].compactMap(\.self) {
            try requireExpired(decoder.decode(LockoutDeadlineRecord.self, from: data), now: now)
        }
        if let control {
            guard let fields = try JSONSerialization.jsonObject(with: control) as? [String: Any]
            else {
                throw AdmissionError.invalidState
            }
            let status: PrivilegedDaemonStatus
            let legacyKeys: Set = ["activeRecord", "lastHeartbeatAt", "shutdownIssued"]
            let authenticatedKeys: Set = [
                "localStatus", "authenticatedHeartbeatLockoutID", "releasedLocalDeadlines"
            ]
            if fields.keys.contains("localStatus") {
                guard Set(fields.keys).isSubset(of: authenticatedKeys) else {
                    throw AdmissionError.invalidState
                }
                status = try decoder.decode(AuthenticatedDaemonControl.self, from: control)
                    .localStatus
            } else {
                guard Set(fields.keys).isSubset(of: legacyKeys) else {
                    throw AdmissionError.invalidState
                }
                status = try decoder.decode(PrivilegedDaemonStatus.self, from: control)
            }
            guard !status.shutdownIssued else { throw AdmissionError.invalidState }
            try requireExpired(status.activeRecord, now: now)
        }
    }

    private static func requireExpired(_ record: LockoutDeadlineRecord?, now: Date) throws {
        guard let record else { return }
        guard record.lockoutStartedAt <= record.scheduledUnlockAt else {
            throw AdmissionError.invalidState
        }
        guard record.scheduledUnlockAt <= now else { throw AdmissionError.activeDeadline }
    }
}
