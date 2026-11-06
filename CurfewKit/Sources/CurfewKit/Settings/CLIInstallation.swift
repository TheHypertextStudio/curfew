import Darwin
import Foundation

/// Installs the bundled command without requiring a source checkout or administrator access.
public struct CLIInstallation {
    public struct Plan {
        public let commandURL: URL
        public let profileURL: URL?
        public let changes: [String]
    }

    public let sourceURL: URL
    private let home: URL
    private let shell: String
    private let path: String
    private let environment: [String: String]
    private let fileManager = FileManager.default

    public init(
        sourceURL: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: String? = nil,
        path: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.sourceURL = sourceURL.standardizedFileURL
        self.home = home
        self.shell = shell ?? environment["SHELL"] ?? Self.accountShell()
        self.path = path ?? environment["PATH"] ?? ""
        self.environment = environment
    }

    public func plan() throws -> Plan {
        guard fileManager.isExecutableFile(atPath: sourceURL.path) else {
            throw CLIInstallationError(
                "The bundled curfew-ctl executable is missing. Reinstall Curfew from thecurfew.app."
            )
        }
        let command = commandDirectory.appendingPathComponent("curfew-ctl")
        let linked = try commandIsInstalled(at: command)
        let profile = try shellProfile()
        let profileData = try profile.map { try readProfile($0) }
        let hasPath = path.split(separator: ":").contains { String($0) == commandDirectory.path }
        let configured = hasPath || (profileData?.contains(pathBlock) == true)
        var changes = [String]()
        if !linked {
            changes.append("Link \(command.path) to the bundled command.")
        }
        if !configured, let profile {
            changes.append("Add \(commandDirectory.path) to PATH in \(profile.path).")
        }
        return Plan(commandURL: command, profileURL: configured ? nil : profile, changes: changes)
    }

    public func install() throws {
        guard geteuid() != 0 else {
            throw CLIInstallationError(
                "Install the command as your normal Mac account without sudo."
            )
        }
        _ = try plan()
        try fileManager.createDirectory(at: commandDirectory, withIntermediateDirectories: true)
        let lock = commandDirectory.appendingPathComponent(".curfew-cli-install.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1 else {
            throw CLIInstallationError("The CLI installation lock is not a regular private file.")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw CLIInstallationError("Another installation is using the command directory.")
        }
        defer { flock(descriptor, LOCK_UN) }
        let current = try plan()
        if try !commandIsInstalled(at: current.commandURL) {
            try fileManager.createSymbolicLink(
                at: current.commandURL,
                withDestinationURL: sourceURL
            )
        }
        if let profile = current.profileURL {
            let existing = try readProfile(profile)
            let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
            try writeProfile(
                Data((existing + separator + pathBlock).utf8),
                to: profile,
                replacing: Data(existing.utf8)
            )
        }
    }

    private var commandDirectory: URL {
        home.appendingPathComponent(".local/bin", isDirectory: true)
    }

    private func commandIsInstalled(at url: URL) throws -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT {
                return false
            }
            throw Self.posixError()
        }
        guard info.st_mode & S_IFMT == S_IFLNK,
              try fileManager.destinationOfSymbolicLink(atPath: url.path) == sourceURL.path else {
            throw CLIInstallationError(
                "A different command already exists at \(url.path). Move it before installing Curfew's command."
            )
        }
        return true
    }

    private func shellProfile() throws -> URL? {
        if path.split(separator: ":")
            .contains(where: { String($0) == commandDirectory.path }) {
            return nil
        }
        switch URL(fileURLWithPath: shell).lastPathComponent {
        case "zsh":
            let directory = environment["ZDOTDIR"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home
            return directory.appendingPathComponent(".zprofile")
        case "bash":
            return [".bash_profile", ".bash_login", ".profile"]
                .map { home.appendingPathComponent($0) }
                .first { fileManager.fileExists(atPath: $0.path) } ?? home
                .appendingPathComponent(".bash_profile")
        case "fish":
            let base = environment["XDG_CONFIG_HOME"].map { URL(
                fileURLWithPath: $0,
                isDirectory: true
            ) }
                ?? home.appendingPathComponent(".config")
            return base.appendingPathComponent("fish/conf.d/curfew-cli-path.fish")
        default:
            throw CLIInstallationError(
                "Automatic PATH setup supports zsh, bash, and fish. Select one with --shell, or add \(commandDirectory.path) to PATH before installing."
            )
        }
    }

    private var pathBlock: String {
        let quotedPath = commandDirectory.path.replacingOccurrences(of: "'", with: "'\\''")
        let directory = "'" + quotedPath + "'"
        let statement = URL(fileURLWithPath: shell).lastPathComponent == "fish"
            ? "fish_add_path --path \(directory)"
            : "case \":$PATH:\" in *:\(directory):*) ;; *) export PATH=\(directory):\"$PATH\" ;; esac"
        return "# Curfew command line PATH\n\(statement)\n# End Curfew command line PATH\n"
    }

    private func readProfile(_ url: URL) throws -> String {
        let data: Data?
        do {
            data = try BoundedRegularFileReader.read(url, maximumBytes: 1024 * 1024)
        } catch {
            throw CLIInstallationError(
                "The shell profile at \(url.path) is unreadable, linked, or too large. Preserve its contents and configure PATH yourself before installing."
            )
        }
        guard let data else { return "" }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIInstallationError(
                "The shell profile at \(url.path) is not UTF-8. No shell settings were changed."
            )
        }
        if text.contains("# Curfew command line PATH"), !text.contains(pathBlock) {
            throw CLIInstallationError(
                "The Curfew PATH entry in \(url.path) was edited. Preserve or remove that entry before automatic setup."
            )
        }
        return text
    }

    func writeProfile(_ data: Data, to url: URL, replacing expected: Data) throws {
        try CLIProfileWriter.write(data, to: url, replacing: expected)
    }

    private static func accountShell() -> String {
        guard let account = getpwuid(getuid()),
              let value = account.pointee.pw_shell else { return "/bin/zsh" }
        return String(cString: value)
    }

    private static func posixError()
        -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

public struct CLIInstallationError: LocalizedError {
    public let message: String
    init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
