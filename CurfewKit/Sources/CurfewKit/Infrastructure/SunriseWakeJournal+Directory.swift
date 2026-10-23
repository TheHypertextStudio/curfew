import Darwin
import Foundation

public extension SunriseWakeJournal {
    /// Prepares the helper's private cancellation journal beneath a trusted base.
    /// Walks from the filesystem root without following symbolic links. Existing
    /// directories must already satisfy the ownership and permission contract.
    static func prepareDirectory(
        in trustedBase: URL,
        namespace: String,
        requiredOwnerUserID: uid_t
    ) throws -> URL {
        let components = try validatedBaseComponents(
            trustedBase,
            namespace: namespace,
            owner: requiredOwnerUserID
        )
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        let root = open("/", flags)
        guard root >= 0 else { throw Failure.unavailable }
        var descriptors = [root]
        defer { for descriptor in descriptors.reversed() {
            close(descriptor)
        } }

        try validateDirectory(root, owner: requiredOwnerUserID, exactOwner: components.isEmpty)
        for component in components {
            let descriptor = openat(descriptors[descriptors.count - 1], String(component), flags)
            guard descriptor >= 0 else { throw Failure.unavailable }
            descriptors.append(descriptor)
            try validateDirectory(
                descriptor, owner: requiredOwnerUserID,
                exactOwner: descriptors.count == components.count + 1
            )
        }

        let base = descriptors[descriptors.count - 1]
        if mkdirat(base, namespace, mode_t(0o700)) != 0 {
            guard errno == EEXIST else { throw Failure.unavailable }
        }
        let privateDirectory = openat(base, namespace, flags)
        guard privateDirectory >= 0 else { throw Failure.unavailable }
        descriptors.append(privateDirectory)
        try validateDirectory(
            privateDirectory,
            owner: requiredOwnerUserID,
            exactOwner: true,
            privateMode: true
        )

        try revalidateDirectoryEdges(
            descriptors, names: components + [namespace], owner: requiredOwnerUserID
        )
        try validateDirectory(
            privateDirectory,
            owner: requiredOwnerUserID,
            exactOwner: true,
            privateMode: true
        )
        return trustedBase.appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent("sunrise.json")
    }

    private static func validatedBaseComponents(
        _ base: URL,
        namespace: String,
        owner: uid_t
    ) throws -> [String] {
        guard owner == geteuid(), base.isFileURL,
              base.host == nil || base.host == "" || base.host == "localhost",
              base.query == nil, base.fragment == nil,
              base.path.hasPrefix("/"), !base.path.contains("\0"),
              validNamespace(namespace)
        else { throw Failure.unavailable }
        let components = base.path.split(separator: "/")
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw Failure.unavailable
        }
        return components.map(String.init)
    }

    private static func revalidateDirectoryEdges(
        _ descriptors: [Int32],
        names: [String],
        owner: uid_t
    ) throws {
        // A held descriptor alone does not establish that the returned pathname
        // still names it. Recheck every edge, including the namespace, without
        // following links; fail closed if an entry was replaced during the walk.
        for (index, name) in names.enumerated() {
            try validateDirectory(
                descriptors[index], owner: owner,
                exactOwner: index == names.count - 1
            )
            var held = stat()
            var linked = stat()
            guard fstat(descriptors[index + 1], &held) == 0,
                  fstatat(descriptors[index], name, &linked, AT_SYMLINK_NOFOLLOW) == 0,
                  linked.st_mode & S_IFMT == S_IFDIR,
                  linked.st_dev == held.st_dev, linked.st_ino == held.st_ino
            else { throw Failure.unavailable }
        }
    }

    private static func validNamespace(_ namespace: String) -> Bool {
        let bytes = Array(namespace.utf8)
        guard !bytes.isEmpty, bytes.count <= 255,
              bytes.allSatisfy({
                  (0x41 ... 0x5A).contains($0) || (0x61 ... 0x7A).contains($0)
                      || (0x30 ... 0x39).contains($0) || $0 == 0x2D || $0 == 0x5F || $0 == 0x2E
              })
        else { return false }
        return !namespace.split(separator: ".", omittingEmptySubsequences: false)
            .contains(where: \.isEmpty)
    }

    private static func validateDirectory(
        _ descriptor: Int32,
        owner: uid_t,
        exactOwner: Bool,
        privateMode: Bool = false
    ) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == owner || (!exactOwner && metadata.st_uid == 0),
              metadata.st_mode & 0o022 == 0,
              !privateMode || metadata.st_mode & 0o7777 == 0o700
        else { throw Failure.unavailable }
    }
}
