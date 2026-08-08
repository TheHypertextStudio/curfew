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

    func run() throws {
        let settings = loadSettings()
        let policy = settings.protectedWork
        var claimID: UUID?
        if let id {
            guard let parsed = UUID(uuidString: id) else {
                throw ValidationError("--id must be a UUID.")
            }
            claimID = parsed
        }

        let claim = try ProtectedWorkStore().claim(
            id: claimID,
            label: label,
            source: .cli,
            leaseMinutes: minutes,
            now: Date(),
            policy: policy
        )
        print(claim.id.uuidString)
        let formatter = ISO8601DateFormatter()
        print("expires: \(formatter.string(from: claim.expiresAt))")
        print(
            "max deferral: \(policy.maximumDeferralMinutes) min from when a shutdown first comes due"
        )
    }
}

struct WorkListCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show live protected-work claims."
    )

    func run() {
        let now = Date()
        let claims = ProtectedWorkStore().activeClaims(now: now)
        guard !claims.isEmpty else {
            print("no active protected-work claims")
            return
        }
        let formatter = ISO8601DateFormatter()
        for claim in claims {
            let remaining = max(0, Int(claim.expiresAt.timeIntervalSince(now)) / 60)
            print(
                "\(claim.id.uuidString)  \(claim.source.rawValue)  \(remaining)m left  \(claim.label)"
            )
            print("    started \(formatter.string(from: claim.startedAt))")
        }
    }
}

struct WorkReleaseCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Drop a protected-work claim before its lease expires."
    )

    @Argument(help: "Claim UUID.")
    var id: String

    func run() throws {
        guard let parsed = UUID(uuidString: id) else {
            throw ValidationError("id must be a UUID.")
        }
        try ProtectedWorkStore().release(id: parsed)
        print("released \(parsed.uuidString)")
    }
}
