import ArgumentParser
import CurfewKit
import Foundation

/// Declares that delegated work is in flight so enforcement postpones the
/// destructive half of lockout.
///
/// The shell-script face of the same signal the `curfew_declare_work` MCP tool
/// files. A wrapper that shells out to a long-running agent claims before it
/// starts, renews while it runs, and releases when it finishes; the claim
/// expires on its own if the wrapper dies, so nothing has to notice.
struct WorkCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "work",
        abstract: "Declare, renew, list, or release protected background work.",
        subcommands: [
            WorkClaimCommand.self,
            WorkListCommand.self,
            WorkReleaseCommand.self
        ],
        defaultSubcommand: WorkListCommand.self
    )

    @OptionGroup var options: CLIOptions
}

struct WorkClaimCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "claim",
        abstract: "File or renew a protected-work claim.",
        discussion: """
        A claim postpones graceful termination and the daemon's shutdown while \
        it is live, up to the policy's maximum deferral. It never unlocks the \
        display and never moves the curfew.
        """
    )

    @Option(name: .shortAndLong, help: "What the work is, shown to the user.")
    var label: String

    @Option(
        name: .shortAndLong,
        help: "Lease length in minutes. Clamped to the configured ceiling."
    )
    var minutes: Int?

    @Option(name: .long, help: "Existing claim UUID to renew instead of filing a new one.")
    var id: String?

    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    @Flag(name: [.long, .customShort("n")], help: "Preview the change without writing files.")
    var dryRun: Bool = false

    func run() throws {
        try CLIText.print(output(
            store: ProtectedWorkStore(),
            policy: loadSettings().protectedWork,
            now: Date()
        ), title: "Protected work", options: options)
    }

    func output(
        store: ProtectedWorkStore,
        policy: ProtectedWorkPolicy,
        now: Date
    ) throws -> String {
        var claimID: UUID?
        if let id {
            guard let parsed = UUID(uuidString: id) else {
                throw ValidationError("--id must be a UUID.")
            }
            claimID = parsed
        }

        if dryRun {
            _ = try store.loadThrowing()
            let granted = policy.leaseMinutes(requested: minutes)
            if json {
                return try workJSON([
                    "dry_run": true, "action": claimID == nil ? "claim" : "renew",
                    "label": label, "lease_seconds": granted * 60,
                    "path": store.recordURL.path
                ])
            }
            return "Would \(claimID == nil ? "create" : "renew") a protected-work claim in \(store.recordURL.path) for \(granted) minutes."
        }

        let claim = try store.claim(
            id: claimID,
            label: label,
            source: .cli,
            leaseMinutes: minutes,
            now: now,
            policy: policy
        )
        if json {
            var object = workClaimObject(claim)
            object["maximum_deferral_seconds"] = try CLIOutput
                .durationSeconds(policy.maximumDeferralMinutes)
            return try workJSON(object)
        }
        let formatter = ISO8601DateFormatter()
        return """
        \(claim.id.uuidString)
        expires: \(formatter.string(from: claim.expiresAt))
        max deferral: \(policy.maximumDeferralMinutes) min from when a shutdown first comes due
        """
    }
}

struct WorkListCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show live protected-work claims."
    )

    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    func run() throws {
        try CLIText.print(
            output(store: ProtectedWorkStore(), now: Date()),
            title: "Protected work",
            options: options,
            page: true
        )
    }

    func output(store: ProtectedWorkStore, now: Date) throws -> String {
        let claims = try store.loadThrowing().filter { $0.isActive(at: now) }
        if json {
            return try workJSON(["claims": claims.map(workClaimObject)])
        }
        guard !claims.isEmpty else {
            return "No active protected-work claims."
        }
        let formatter = ISO8601DateFormatter()
        return claims.map { claim in
            let remaining = max(0, Int(claim.expiresAt.timeIntervalSince(now)) / 60)
            return """
            \(claim.id.uuidString)  \(claim.source.rawValue)  \(remaining)m left  \(claim.label)
                started \(formatter.string(from: claim.startedAt))
            """
        }.joined(separator: "\n")
    }
}

struct WorkReleaseCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Release a protected-work claim before its lease expires."
    )

    @Argument(help: "Claim UUID.")
    var id: String

    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    @Flag(name: [.long, .customShort("n")], help: "Preview the change without writing files.")
    var dryRun: Bool = false

    func run() throws {
        try CLIText.print(
            output(store: ProtectedWorkStore()),
            title: "Protected work",
            options: options
        )
    }

    func output(store: ProtectedWorkStore) throws -> String {
        guard let parsed = UUID(uuidString: id) else {
            throw ValidationError("id must be a UUID.")
        }
        if dryRun {
            _ = try store.loadThrowing()
            return json
                ? try workJSON([
                    "id": parsed.uuidString,
                    "dry_run": true,
                    "action": "release",
                    "path": store.recordURL.path
                ])
                : "Would release claim \(parsed.uuidString) from \(store.recordURL.path)."
        }
        try store.release(id: parsed)
        if json {
            return try workJSON(["id": parsed.uuidString, "released": true])
        }
        return "Released \(parsed.uuidString)."
    }
}

private func workClaimObject(_ claim: ProtectedWorkClaim) -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    return [
        "id": claim.id.uuidString,
        "label": claim.label,
        "source": claim.source.rawValue,
        "started_at": formatter.string(from: claim.startedAt),
        "expires_at": formatter.string(from: claim.expiresAt)
    ]
}

private func workJSON(_ object: [String: Any]) throws -> String {
    let data = try CLIOutput.data(object)
    guard let output = String(bytes: data, encoding: .utf8) else {
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return output
}
