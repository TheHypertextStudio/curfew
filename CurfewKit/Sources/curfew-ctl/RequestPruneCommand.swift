import ArgumentParser
import CurfewKit
import Darwin
import Foundation

struct RequestPruneCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Preview or remove old resolved approval records (beta).",
        discussion: "Pending requests and records needed for recovery stay in the queue."
    )

    @Option(help: "Select outcomes resolved before this ISO 8601 timestamp.")
    var before: String?
    @Flag(help: "Select all completed outcomes, including undated records.")
    var allResolved = false
    @Flag(help: "Remove the selected records after confirmation.")
    var apply = false
    @Flag(help: "Confirm removal without a prompt. Requires --apply.")
    var yes = false
    @Flag(name: [.long, .customShort("n")], help: "Preview cleanup even when --apply is set.")
    var dryRun = false
    @OptionGroup var options: CLIOptions

    mutating func validate() throws {
        guard !allResolved || before == nil else {
            throw ValidationError("Use either --before or --all-resolved.")
        }
        if let before, AuditCommand.date(before) == nil {
            throw ValidationError("--before must be an ISO 8601 timestamp with a timezone.")
        }
        guard !yes || apply else { throw ValidationError("--yes requires --apply.") }
    }

    func run() throws {
        let cutoff = allResolved ? nil : before.flatMap(AuditCommand.date)
            ?? Date().addingTimeInterval(-30 * 86400)
        let plan = try MCPRequestQueue.previewResolvedPrune(before: cutoff)
        let result = try apply && !dryRun && !plan.candidateIDs.isEmpty
            ? confirmAndPrune(plan) : nil
        try report(plan, result: result, cutoff: cutoff)
    }

    private func confirmAndPrune(_ plan: MCPRequestQueue.PrunePlan) throws
        -> MCPRequestQueue.PruneResult? {
        if !yes {
            guard !options.json, !options.noInput, isatty(STDIN_FILENO) == 1,
                  isatty(STDERR_FILENO) == 1 else {
                throw ValidationError(
                    "Use --apply --yes to remove records without a terminal prompt."
                )
            }
            CLIText.diagnostic("Remove \(plan.candidateIDs.count) resolved approval records? [y/N]")
            guard ["y", "yes"].contains(readLine()?.lowercased() ?? "") else { return nil }
        }
        return try MCPRequestQueue.pruneResolved(plan)
    }

    private func report(
        _ plan: MCPRequestQueue.PrunePlan, result: MCPRequestQueue.PruneResult?, cutoff: Date?
    ) throws {
        let candidates = plan.candidateIDs
        if options.json {
            var report: [String: Any] = [
                "dry_run": result == nil, "candidate_ids": candidates.map(\.uuidString),
                "removed_ids": result?.removedIDs.map(\.uuidString) ?? [],
                "pending_count": plan.pendingCount,
                "protected_resolved_count": plan.protectedResolvedCount,
                "retained_count": result?.retainedCount ?? plan.queuedCount
            ]
            if let cutoff {
                report["before"] = ISO8601DateFormatter().string(from: cutoff)
            }
            try CLIOutput.printJSON(report)
            return
        }
        let summary = if let result {
            "Removed \(result.removedIDs.count) resolved approval records."
        } else {
            "\(candidates.count) resolved approval records match."
        }
        var lines = [summary, "Pending requests and recovery records stay in the queue."]
        if result == nil, !candidates.isEmpty {
            lines.append("Use --apply to remove matching records.")
        }
        try CLIText.print(lines.joined(separator: "\n"), title: "Request cleanup", options: options)
    }
}
