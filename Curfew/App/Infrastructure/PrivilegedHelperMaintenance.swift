import CurfewKit
import Darwin
import Foundation

enum HelperMaintenanceError: LocalizedError {
    case unsafeState, unsupportedRegistration, commandFailed, oversizedOutput, changedState

    var errorDescription: String? {
        switch self {
        case .unsafeState:
            "Curfew could not verify that background protection can be replaced safely. "
                + "No saved state was removed."
        case .unsupportedRegistration:
            "This background-protection registration needs manual repair. Curfew left it running."
        case .commandFailed:
            "Background-protection verification did not finish. "
                + "Try again and approve the macOS prompt if shown."
        case .oversizedOutput:
            "Background-protection verification returned unexpected data. "
                + "Curfew left the installation unchanged."
        case .changedState: "Protection changed during verification. Try the repair again."
        }
    }
}

/// Read-only admission for the one shipped Studio Dev registration predating XPC.
/// An unavailable connection alone is never sufficient to enable this fallback.
@MainActor
final class PrivilegedHelperMaintenance {
    private let authorization = HelperReadAuthorization()
    func admitLegacy(deviceID: UUID, requireLegacyRegistration: Bool = true) async throws {
        let flavor = CurfewFlavor.current
        let label = "studio.hypertext.curfew.studio.dev.daemon"
        guard flavor == .studioDevelopment,
              Bundle.main.bundleIdentifier == "studio.hypertext.curfew.studio.dev" else {
            throw HelperMaintenanceError.unsupportedRegistration
        }
        if requireLegacyRegistration {
            let output = try await MaintenanceCommand.read(
                executable: "/bin/launchctl", arguments: ["print", "system/\(label)"], limit: 65536
            )
            guard let job = String(data: output, encoding: .utf8),
                  job.hasPrefix("system/\(label) = {"),
                  job.contains("managed_by = com.apple.xpc.ServiceManagement"),
                  job.contains("parent bundle identifier = studio.hypertext.curfew.studio.dev\n"),
                  job.contains("parent bundle version = 1\n"),
                  !job.contains("endpoints ="), !job.contains("MachServices") else {
                throw HelperMaintenanceError.unsupportedRegistration
            }
        }
        try requireEmptyInbox()
        let root = SharedPaths.privilegedApplicationSupport
        _ = try identity(root, owner: 0, directory: true, required: true)
        guard let remote = try await read(SharedPaths.remoteCommandState, owner: 0) else {
            throw HelperMaintenanceError.unsafeState
        }
        let control = try await read(root.appendingPathComponent("lockout-state.json"), owner: 0)
        let shadow = try await read(SharedPaths.lockoutDeadlineShadow, owner: 0)
        let user = try await read(SharedPaths.lockoutDeadline, owner: geteuid())
        try DaemonMaintenanceAdmission.validate(
            remote: remote, control: control, user: user, shadow: shadow,
            deviceID: deviceID, now: Date()
        )
        try Task.checkCancellation()
        try requireEmptyInbox()
    }

    private func requireEmptyInbox() throws {
        let inbox = SharedPaths.remoteCommandInbox
        guard try identity(inbox, owner: geteuid(), directory: true) != nil else { return }
        guard try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty else {
            throw HelperMaintenanceError.unsafeState
        }
    }

    private func read(_ url: URL, owner: uid_t) async throws -> Data? {
        guard let before = try identity(url, owner: owner) else { return nil }
        let data: Data
        do {
            guard let direct = try BoundedRegularFileReader.read(url, maximumBytes: 1_048_576)
            else {
                throw HelperMaintenanceError.changedState
            }
            data = direct
        } catch {
            // Only root-owned, positively inspected records may request this
            // narrow read-only right. No shell, root job, or write flag is used.
            guard owner == 0 else { throw error }
            data = try await MaintenanceCommand.read(
                executable: "/usr/libexec/authopen", arguments: ["-extauth", url.path],
                limit: 1_048_576, authorization: authorization
            )
        }
        guard try identity(url, owner: owner, required: true) == before else {
            throw HelperMaintenanceError.changedState
        }
        return data
    }

    private func identity(
        _ url: URL, owner: uid_t, directory: Bool = false, required: Bool = false
    ) throws -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT, !required {
                return nil
            }
            throw HelperMaintenanceError.unsafeState
        }
        guard info.st_uid == owner,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              info.st_mode & 0o022 == 0,
              directory || (info.st_nlink == 1 && info.st_size <= 1_048_576) else {
            throw HelperMaintenanceError.unsafeState
        }
        return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
    }
}

/// Runs only the fixed read-only utilities above, off the main actor. Output,
/// duration, cancellation, and exit status are bounded before any data is trusted.
private final nonisolated class MaintenanceCommand: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false

    static func read(
        executable: String, arguments: [String], limit: Int,
        authorization: HelperReadAuthorization? = nil
    ) async throws -> Data {
        let command = MaintenanceCommand()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                try command.execute(
                    executable: executable, arguments: arguments, limit: limit,
                    authorization: authorization
                )
            }.value
        } onCancel: {
            command.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func execute(
        executable: String, arguments: [String], limit: Int,
        authorization: HelperReadAuthorization?
    ) throws -> Data {
        let pipe = Pipe()
        let input = Pipe()
        let external = try authorization.map {
            try $0.externalForm(for: arguments.last ?? "")
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = external == nil ? FileHandle.nullDevice : input
        lock.lock()
        do {
            guard !cancelled else { throw CancellationError() }
            try process.run()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        let timeout = DispatchWorkItem { [self] in cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeout)
        defer { timeout.cancel() }
        if let external {
            try input.fileHandleForWriting.write(contentsOf: external)
            try input.fileHandleForWriting.close()
        }
        var output = Data()
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 16384)
            if chunk.isEmpty {
                break
            }
            guard output.count + chunk.count <= limit else {
                cancel()
                process.waitUntilExit()
                throw HelperMaintenanceError.oversizedOutput
            }
            output.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw HelperMaintenanceError.commandFailed }
        return output
    }
}
