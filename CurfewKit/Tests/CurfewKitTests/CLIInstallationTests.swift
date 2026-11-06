@testable import CurfewKit
import Darwin
import Foundation
import Testing

struct CLIInstallationTests {
    @Test("Installing PATH preserves profile extended attributes, ACL and group")
    func profileMetadata() throws {
        try withInstaller { installer, home in
            let profile = home.appendingPathComponent(".zprofile")
            try Data("export EDITOR=vim\n".utf8).write(to: profile)
            let key = "studio.hypertext.curfew.fixture"
            _ = try tool("/usr/bin/xattr", ["-w", key, "preserve-me", profile.path])
            _ = try tool(
                "/bin/chmod",
                ["+a", "user:\(NSUserName()) allow read,write", profile.path]
            )
            let count = getgroups(0, nil)
            try #require(count >= 0)
            var groups = [gid_t](repeating: 0, count: Int(count))
            try #require(getgroups(count, &groups) == count)
            if let alternate = groups.first(where: { $0 != getgid() }) {
                try #require(chown(profile.path, uid_t.max, alternate) == 0)
            }
            let acl = try tool("/bin/ls", ["-le", profile.path]).split(separator: "\n").dropFirst()
            let group = try FileManager.default
                .attributesOfItem(atPath: profile.path)[.groupOwnerAccountID] as? Int
            try installer.install()
            #expect(try tool("/usr/bin/xattr", ["-p", key, profile.path]) == "preserve-me\n")
            #expect(try tool("/bin/ls", ["-le", profile.path]).split(separator: "\n")
                .dropFirst() == acl)
            #expect(try FileManager.default
                .attributesOfItem(atPath: profile.path)[.groupOwnerAccountID] as? Int == group)
        }
    }

    @Test("Publishing a profile refuses to overwrite a concurrent edit")
    func concurrentProfileEdit() throws {
        try withInstaller { installer, home in
            let profile = home.appendingPathComponent(".zprofile")
            let captured = Data("export EDITOR=vim\n".utf8)
            try captured.write(to: profile)
            let edited = Data("export EDITOR=nano\nexport LANG=en_US.UTF-8\n".utf8)
            try edited.write(to: profile, options: .atomic)
            #expect(throws: (any Error).self) {
                try installer.writeProfile(
                    Data("old snapshot with PATH\n".utf8),
                    to: profile,
                    replacing: captured
                )
            }
            #expect(try Data(contentsOf: profile) == edited)
        }
    }

    @Test("A busy installer lock cannot block Settings or enforcement")
    func busyLock() throws {
        try withInstaller { installer, home in
            let directory = home.appendingPathComponent(".local/bin")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let descriptor = open(
                directory.appendingPathComponent(".curfew-cli-install.lock").path,
                O_CREAT | O_RDWR,
                0o600
            )
            try #require(descriptor >= 0)
            defer { close(descriptor) }
            try #require(flock(descriptor, LOCK_EX) == 0)
            let started = DispatchSemaphore(value: 0)
            let completed = DispatchSemaphore(value: 0)
            let attempt = CLIInstallationAttempt()
            DispatchQueue.global(qos: .userInitiated).async {
                started.signal()
                do { try installer.install() } catch { attempt.failed = true }
                completed.signal()
            }
            let didStart = started.wait(timeout: .now() + 5)
            let finished = didStart == .success ? completed.wait(timeout: .now() + 5) : .timedOut
            flock(descriptor, LOCK_UN)
            if finished == .timedOut {
                completed.wait()
            }
            #expect(finished == .success)
            #expect(attempt.failed)
            #expect(!FileManager.default
                .fileExists(atPath: home.appendingPathComponent(".zprofile").path))
        }
    }

    @Test("CLI setup previews without writing and repeated applies preserve files")
    func repeatableInstallation() throws {
        try withInstaller { installer, home in
            let plan = try installer.plan()
            #expect(plan.changes.count == 2)
            #expect(!FileManager.default
                .fileExists(atPath: home.appendingPathComponent(".local").path))
            try installer.install()
            let target = home.appendingPathComponent(".local/bin/curfew-ctl")
            let profile = home.appendingPathComponent(".zprofile")
            #expect(try FileManager.default
                .destinationOfSymbolicLink(atPath: target.path) == installer.sourceURL.path)
            let before = try Data(contentsOf: profile)
            let attributes = try FileManager.default.attributesOfItem(atPath: profile.path)
            try installer.install()
            #expect(try Data(contentsOf: profile) == before)
            #expect(try FileManager.default
                .attributesOfItem(atPath: profile.path)[.modificationDate] as? Date ==
                attributes[.modificationDate] as? Date)
            #expect(try installer.plan().changes.isEmpty)
        }
    }

    @Test("CLI installation preserves other commands and dotfiles")
    func conflicts() throws {
        try withInstaller { installer, home in
            let directory = home.appendingPathComponent(".local/bin")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let target = directory.appendingPathComponent("curfew-ctl")
            try Data("unrelated command".utf8).write(to: target)
            #expect(throws: (any Error).self) { try installer.install() }
            #expect(try String(contentsOf: target, encoding: .utf8) == "unrelated command")
            #expect(!FileManager.default
                .fileExists(atPath: home.appendingPathComponent(".zprofile").path))
        }
        try withInstaller { installer, home in
            let profile = home.appendingPathComponent(".zprofile")
            let original = "export EDITOR=vim\n"
            try Data(original.utf8).write(to: profile)
            try installer.install()
            #expect(try String(contentsOf: profile, encoding: .utf8).hasPrefix(original))
        }
    }

    @Test("Interrupted setup resumes from the existing link")
    func resume() throws {
        try withInstaller { installer, home in
            let directory = home.appendingPathComponent(".local/bin")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("curfew-ctl"),
                withDestinationURL: installer.sourceURL
            )
            #expect(try installer.plan().changes.count == 1)
            try installer.install()
            #expect(try installer.plan().changes.isEmpty)
        }
    }

    @Test("Setup preserves a linked shell profile and leaves unsupported shells untouched")
    func unsafeProfile() throws {
        try withInstaller { installer, home in
            let actual = home.appendingPathComponent("dotfiles")
            try Data("preserve".utf8).write(to: actual)
            try FileManager.default.createSymbolicLink(
                at: home.appendingPathComponent(".zprofile"),
                withDestinationURL: actual
            )
            #expect(throws: (any Error).self) { try installer.install() }
            #expect(try String(contentsOf: actual, encoding: .utf8) == "preserve")
            #expect(!FileManager.default
                .fileExists(atPath: home.appendingPathComponent(".local").path))
        }
        try withInstaller(shell: "/bin/unknown") { installer, home in
            #expect(throws: (any Error).self) { try installer.install() }
            #expect(!FileManager.default
                .fileExists(atPath: home.appendingPathComponent(".local").path))
        }
    }

    @Test("A configured PATH needs no shell changes")
    func configuredPath() throws {
        try withInstaller(pathIncludesTarget: true) { installer, home in
            #expect(try installer.plan().changes.count == 1)
            try installer.install()
            #expect(!FileManager.default
                .fileExists(atPath: home.appendingPathComponent(".zprofile").path))
        }
    }

    @Test("Explicit shell directories stay inside their selected fixture")
    func explicitShellDirectories() throws {
        for (shell, variable, relative) in [
            ("/bin/zsh", "ZDOTDIR", ".zprofile"),
            ("/bin/fish", "XDG_CONFIG_HOME", "fish/conf.d/curfew-cli-path.fish")
        ] {
            try withInstaller { installer, home in
                let directory = home.appendingPathComponent("shell-config")
                let custom = CLIInstallation(
                    sourceURL: installer.sourceURL, home: home, shell: shell, path: "/usr/bin:/bin",
                    environment: [variable: directory.path]
                )
                try custom.install()
                #expect(FileManager.default
                    .fileExists(atPath: directory.appendingPathComponent(relative).path))
                #expect(!FileManager.default
                    .fileExists(atPath: home.appendingPathComponent(".zprofile").path))
                #expect(try custom.plan().changes.isEmpty)
            }
        }
    }

    @Test("Installed zsh and bash profiles keep one PATH entry when loaded repeatedly")
    func shellProfiles() throws {
        for shell in ["/bin/zsh", "/bin/bash"] {
            try withInstaller(shell: shell) { installer, home in
                try installer.install()
                let name = shell.hasSuffix("zsh") ? ".zprofile" : ".bash_profile"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = [
                    "-c",
                    "source \"$1\"; source \"$1\"; printf '%s' \"$PATH\"",
                    "curfew-install-test",
                    home.appendingPathComponent(name).path
                ]
                process.environment = ["PATH": "/usr/bin:/bin", "HOME": home.path]
                let output = Pipe()
                process.standardOutput = output
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                #expect(process.terminationStatus == 0)
                let entries = try #require(String(data: data, encoding: .utf8))
                    .split(separator: ":")
                #expect(entries.filter { $0 == home.appendingPathComponent(".local/bin").path }
                    .count == 1)
            }
        }
    }
}

private extension CLIInstallationTests {
    func withInstaller(
        shell: String = "/bin/zsh", pathIncludesTarget: Bool = false,
        body: (CLIInstallation, URL) throws -> Void
    ) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent("Curfew.app/Contents/Resources/curfew-ctl")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let searchPath = pathIncludesTarget
            ? home.appendingPathComponent(".local/bin").path : "/usr/bin:/bin"
        try body(CLIInstallation(
            sourceURL: source, home: home, shell: shell,
            path: searchPath,
            environment: [:]
        ), home)
    }

    func tool(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return try #require(String(data: bytes, encoding: .utf8))
    }
}

private final class CLIInstallationAttempt: @unchecked Sendable {
    var failed = false
}
