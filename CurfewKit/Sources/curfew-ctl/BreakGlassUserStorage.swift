import Darwin
import Foundation

struct BreakGlassCredentialState: Equatable {
    var uid: uid_t
    var gid: gid_t
    var groups: [gid_t]
}

protocol BreakGlassCredentials {
    func capture() throws -> BreakGlassCredentialState
    func setEffectiveUser(_ uid: uid_t) throws
    func setEffectiveGroup(_ gid: gid_t) throws
    func setGroups(_ groups: [gid_t]) throws
}

struct SystemBreakGlassCredentials: BreakGlassCredentials {
    func capture() throws -> BreakGlassCredentialState {
        let count = getgroups(0, nil)
        guard count >= 0 else { throw currentPOSIXError() }
        var groups = [gid_t](repeating: 0, count: Int(count))
        let loaded = groups.withUnsafeMutableBufferPointer { getgroups(count, $0.baseAddress) }
        guard loaded >= 0 else { throw currentPOSIXError() }
        return BreakGlassCredentialState(
            uid: geteuid(),
            gid: getegid(),
            groups: Array(groups.prefix(Int(loaded)))
        )
    }

    func setEffectiveUser(_ uid: uid_t) throws {
        guard seteuid(uid) == 0 else { throw currentPOSIXError() }
    }

    func setEffectiveGroup(_ gid: gid_t) throws {
        guard setegid(gid) == 0 else { throw currentPOSIXError() }
    }

    func setGroups(_ groups: [gid_t]) throws {
        let result = groups.withUnsafeBufferPointer { setgroups(Int32($0.count), $0.baseAddress) }
        guard result == 0 else { throw currentPOSIXError() }
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

struct BreakGlassUserStorage {
    let user: BreakGlassRecoveryUser?
    let credentials: any BreakGlassCredentials

    static var currentUser: Self {
        Self(user: nil, credentials: SystemBreakGlassCredentials())
    }

    func perform<T>(_ operation: () throws -> T) throws -> T {
        let original = try credentials.capture()
        guard let user else {
            guard original.uid != 0 else {
                throw BreakGlassCredentialError(
                    message: "Root recovery requires an explicit console-user storage context."
                )
            }
            return try operation()
        }
        guard original.uid == 0 else {
            throw BreakGlassCredentialError(
                message: "Changing recovery storage identity requires root."
            )
        }
        let result: Result<T, Error>
        do {
            // Remove root's group privileges before entering user-controlled paths.
            try credentials.setGroups([])
            try credentials.setEffectiveGroup(user.gid)
            try credentials.setEffectiveUser(user.uid)
            result = Result(catching: operation)
        } catch {
            result = .failure(error)
        }
        try restore(original)
        return try result.get()
    }

    private func restore(_ original: BreakGlassCredentialState) throws {
        var failures: [String] = []
        do {
            try credentials.setEffectiveUser(original.uid)
        } catch {
            failures.append("User: \(error.localizedDescription)")
        }
        do {
            try credentials.setEffectiveGroup(original.gid)
        } catch {
            failures.append("Group: \(error.localizedDescription)")
        }
        do {
            try credentials.setGroups(original.groups)
        } catch {
            failures.append("Supplementary groups: \(error.localizedDescription)")
        }
        guard failures.isEmpty else {
            throw BreakGlassCredentialError(message:
                "Could not restore privileged recovery credentials. " +
                    "Recovery files may already have changed. " +
                    "Shutdown cancellation was not attempted. " + failures.joined(separator: " ")
            )
        }
    }
}
