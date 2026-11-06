import ArgumentParser
@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct CLIStandardsTests {
    @Test("Combined short flags keep JSON error output")
    func combinedJSONFlags() throws {
        var output = ""
        #expect(CLIRuntime.run(
            arguments: ["activity", "--days", "0", "-jv"],
            output: { output = $0 },
            diagnostic: { _ in }
        ) == 64)
        let object = try #require(JSONSerialization
            .jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect(object["status"] as? String == "error")
    }

    @Test("Near-miss commands and error codes suggest their exact replacement")
    func suggestions() throws {
        for (arguments, expected) in [
            (["stauts", "--json"], "status"),
            (
                ["explain", "data.invalid_stat", "--json"],
                "data.invalid_state"
            )
        ] {
            var output = ""
            #expect(CLIRuntime.run(
                arguments: arguments,
                output: { output = $0 },
                diagnostic: { _ in }
            ) == 64)
            let object = try #require(JSONSerialization
                .jsonObject(with: Data(output.utf8)) as? [String: Any])
            let error = try #require(object["error"] as? [String: Any])
            #expect((error["action"] as? String)?.contains(expected) == true)
        }
    }

    @Test("Read commands wrap named collections in versioned result objects")
    func versionedCollections() throws {
        for data in try [
            ActivityCommand.jsonData(events: []),
            ReflectionCommand.jsonData(reflections: []),
            ScheduleCommand.jsonData(settings: .default, automaticScheduleEnabled: false)
        ] {
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["schema_version"] as? Int == 1)
            #expect(object["status"] as? String == "ok")
        }
    }

    @Test("The root command declares a semantic build version")
    func declaredVersion() {
        #expect(!CurfewCLI.configuration.version.isEmpty)
    }

    @Test("Completion is discoverable as a standard command")
    func declaredCompletion() {
        #expect(CurfewCLI.configuration.subcommands.contains {
            $0.configuration.commandName == "completion"
        })
    }

    @Test("Request status occupies a domain field inside the successful envelope")
    func requestStatusEnvelope() throws {
        let bytes = try CLIOutput.data(["request_id": "example", "status": "pending"])
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["status"] as? String == "ok")
        #expect(object["request_status"] as? String == "pending")
        #expect(try #require(String(bytes: bytes, encoding: .utf8))
            .hasPrefix("{\"schema_version\":1,\"status\":\"ok\""))
    }

    @Test("JSON usage failures have matching stable error codes and exit statuses")
    func jsonFailure() throws {
        var output: [String] = []
        var diagnostics: [String] = []
        let status = CLIRuntime.run(
            arguments: ["activity", "--days", "0", "--json"],
            output: { output.append($0) },
            diagnostic: { diagnostics.append($0) }
        )
        #expect(status == 64)
        #expect(output.count == 1)
        let object = try #require(JSONSerialization
            .jsonObject(with: Data(output.joined().utf8)) as? [String: Any])
        #expect(object["status"] as? String == "error")
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "usage.invalid_arguments")
        #expect(error["exit_status"] as? Int == 64)
        #expect(diagnostics.joined().contains("Code: usage.invalid_arguments"))
    }

    @Test("An empty command argument returns a usage error")
    func emptyArgument() {
        let status = CLIRuntime.run(arguments: [""], output: { _ in }, diagnostic: { _ in })
        #expect(status == 64)
    }

    @Test("Repeated scalar options fail before command execution")
    func repeatedOptions() {
        for arguments in [
            ["activity", "--days", "1", "--days=2"],
            ["work", "claim", "-m", "1", "--minutes", "2"]
        ] {
            #expect(throws: (any Error).self) { try CLIArguments.validate(arguments) }
        }
        #expect(throws: Never.self) { try CLIArguments.validate([
            "activity",
            "--days=1",
            "--",
            "--days=2"
        ]) }
    }

    @Test("Every public command path remains available and identifies the beta", arguments: [
        "", "status", "setup", "completion", "explain", "schedule", "schedule show", "schedule set",
        "budget", "activity", "audit", "reflections", "override", "extension",
        "request", "request status", "request prune", "work", "work claim", "work list",
        "work release", "break-glass"
    ])
    func betaHelp(path: String) {
        let arguments = path.split(separator: " ").map(String.init)
        var output = ""
        #expect(CLIRuntime.run(
            arguments: arguments + ["--help"],
            output: { output = $0 }, diagnostic: { _ in }
        ) == 0)
        #expect(output.contains("Curfew command line (beta)."))
    }

    @Test("Help leads with examples and help aliases agree")
    func helpParity() {
        var first = ""
        var second = ""
        #expect(CLIRuntime.run(
            arguments: ["schedule", "--help"],
            output: { first = $0 },
            diagnostic: { _ in }
        ) == 0)
        #expect(CLIRuntime.run(
            arguments: ["help", "schedule"],
            output: { second = $0 },
            diagnostic: { _ in }
        ) == 0)
        #expect(first.hasPrefix("EXAMPLES"))
        #expect(first == second)
    }

    @Test("A containing app supplies the exact packaged CLI version")
    func packagedVersion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = directory.appendingPathComponent("Curfew.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "0.0.99"],
            format: .xml,
            options: 0
        )
        try bytes.write(to: contents.appendingPathComponent("Info.plist"))
        #expect(CLIVersion
            .resolve(executableURL: contents.appendingPathComponent("Resources/curfew-ctl")) ==
            "0.0.99")
    }

    @Test("All supported shells use parser-generated completion")
    func completionScripts() throws {
        for shell in ["bash", "zsh", "fish"] {
            let script = try CompletionCommand.script(for: shell)
            #expect(script.contains("curfew-ctl"))
            #expect(script.contains("schedule"))
            #expect(script.contains("break-glass"))
        }
    }

    @Test("Changing request commands offer a read-only preview")
    func requestPreviews() throws {
        _ = try ExtensionCommand.parse(["--reason", "Finish saving", "--dry-run"])
    }

    @Test("Protected-work previews leave both claims and sidecar locks absent")
    func workPreviews() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProtectedWorkStore(recordURL: directory.appendingPathComponent("claims.json"))
        let claim = try WorkClaimCommand.parse(["--label", "Preview only", "--dry-run", "--json"])
        let release = try WorkReleaseCommand.parse([UUID().uuidString, "--dry-run", "--json"])
        let claimObject = try JSONSerialization.jsonObject(with: Data(claim.output(
            store: store,
            policy: .default,
            now: Date()
        ).utf8)) as? [String: Any]
        let releaseObject = try JSONSerialization
            .jsonObject(with: Data(release.output(store: store).utf8)) as? [String: Any]
        #expect(claimObject?["dry_run"] as? Bool == true)
        #expect(releaseObject?["dry_run"] as? Bool == true)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
