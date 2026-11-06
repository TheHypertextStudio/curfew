import CurfewKit
import Darwin
import Foundation

/// Pins the expected user-owned directory before repairing legacy root ownership.
/// All privileged ownership changes use validated descriptors, never a pathname.
enum BreakGlassOwnershipRepair {
    static func repair(user: BreakGlassRecoveryUser, flavor: CurfewFlavor) throws {
        let home = open(user.home.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard home >= 0 else { throw unsafeEntry() }
        var descriptors = [home]
        defer { for descriptor in descriptors {
            close(descriptor)
        } }
        var metadata = stat()
        guard fstat(home, &metadata) == 0, metadata.st_uid == user.uid, user.uid != 0 else {
            throw unsafeEntry()
        }
        let components = ["Library", "Application Support", "Curfew\(flavor.storageDisplaySuffix)"]
        var parent = home
        var complete = true
        for component in components {
            guard let descriptor = try openEntry(
                component,
                in: parent,
                directory: true,
                user: user
            ) else {
                complete = false
                break
            }
            descriptors.append(descriptor)
            parent = descriptor
        }
        if complete {
            for name in ["break-glass.json", ".break-glass-secret"] {
                if let descriptor = try openEntry(name, in: parent, directory: false, user: user) {
                    descriptors.append(descriptor)
                }
            }
        }
        for descriptor in descriptors.dropFirst() {
            let entry = try validate(descriptor, user: user)
            if entry.st_uid == 0, fchown(descriptor, user.uid, user.gid) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    private static func openEntry(
        _ name: String,
        in directory: Int32,
        directory isDirectory: Bool,
        user: BreakGlassRecoveryUser
    ) throws -> Int32? {
        let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (isDirectory ? O_DIRECTORY : 0)
        let descriptor = openat(directory, name, flags)
        if descriptor < 0, errno == ENOENT {
            return nil
        }
        guard descriptor >= 0 else { throw unsafeEntry() }
        do {
            let entry = try validate(descriptor, user: user)
            guard isDirectory == (entry.st_mode & S_IFMT == S_IFDIR) else { throw unsafeEntry() }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func validate(_ descriptor: Int32, user: BreakGlassRecoveryUser) throws -> stat {
        var entry = stat()
        guard fstat(descriptor, &entry) == 0,
              entry.st_uid == 0 || entry.st_uid == user.uid else { throw unsafeEntry() }
        let isDirectory = entry.st_mode & S_IFMT == S_IFDIR
        guard isDirectory || (entry.st_mode & S_IFMT == S_IFREG && entry.st_nlink == 1)
        else { throw unsafeEntry() }
        return entry
    }

    private static func unsafeEntry() -> BreakGlassCredentialError {
        BreakGlassCredentialError(
            message: "Recovery state contains an unsafe entry. Expected the console user's home, " +
                "root- or user-owned support directories, and single-link files. " +
                "Symlinks were not followed, and no release was issued."
        )
    }
}
