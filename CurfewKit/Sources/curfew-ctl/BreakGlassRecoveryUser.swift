import CurfewKit
import Darwin
import Foundation

struct BreakGlassRecoveryUser: Equatable {
    let uid: uid_t
    let gid: gid_t
    let name: String
    let home: URL

    static func resolve(consoleUID: uid_t?, account: (uid_t) -> Self?) throws -> Self {
        guard let consoleUID, consoleUID != 0, let user = account(consoleUID),
              user.uid == consoleUID, !user.name.isEmpty,
              user.home.isFileURL, user.home.path.hasPrefix("/"), user.home.path != "/" else {
            throw BreakGlassCredentialError(
                message: "Emergency recovery needs a signed-in console user. " +
                    "SSH works while that user's display is locked. No recovery files were changed."
            )
        }
        return user
    }

    static func consoleUser() throws -> Self {
        var metadata = stat()
        let consoleUID = stat("/dev/console", &metadata) == 0 ? metadata.st_uid : nil
        return try resolve(consoleUID: consoleUID) { uid in
            guard let entry = getpwuid(uid), let name = entry.pointee.pw_name,
                  let home = entry.pointee.pw_dir else { return nil }
            let homePath = String(cString: home)
            guard homePath.hasPrefix("/"), homePath != "/" else { return nil }
            return Self(
                uid: entry.pointee.pw_uid,
                gid: entry.pointee.pw_gid,
                name: String(cString: name),
                home: URL(fileURLWithPath: homePath, isDirectory: true)
            )
        }
    }

    func supportDirectory(flavor: CurfewFlavor = .current) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("Curfew\(flavor.storageDisplaySuffix)", isDirectory: true)
    }

    func store(flavor: CurfewFlavor = .current) -> BreakGlassStore {
        let directory = supportDirectory(flavor: flavor)
        return BreakGlassStore(
            recordURL: directory.appendingPathComponent("break-glass.json"),
            secretURL: directory.appendingPathComponent(".break-glass-secret")
        )
    }
}

struct BreakGlassCredentialError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}
