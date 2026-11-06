import CurfewKit
import Foundation

enum CLIHelp {
    private struct Example {
        let command: String
        let description: String
    }

    private static let examples: [String: [Example]] = [
        "": [
            Example(command: "curfew-ctl status", description: "Show the current state."),
            Example(
                command: "curfew-ctl schedule show --json",
                description: "Read saved rules as JSON."
            ),
            Example(command: "curfew-ctl setup", description: "Preview command installation.")
        ],
        "status": [
            Example(command: "curfew-ctl status", description: "Show the current state."),
            Example(
                command: "curfew-ctl status --json",
                description: "Read the state in a script."
            )
        ],
        "setup": [
            Example(command: "curfew-ctl setup", description: "Preview installation."),
            Example(
                command: "curfew-ctl setup --apply",
                description: "Install the bundled command."
            )
        ],
        "completion": [
            Example(
                command: "curfew-ctl completion zsh > ~/.zfunc/_curfew-ctl",
                description: "Print zsh completion."
            ),
            Example(command: "curfew-ctl completion fish", description: "Print fish completion.")
        ],
        "schedule": [
            Example(command: "curfew-ctl schedule show", description: "Inspect saved rules."),
            Example(
                command: "curfew-ctl schedule show --json",
                description: "Export saved rules and pending changes."
            ),
            Example(
                command: "curfew-ctl schedule set monday --lock 22:00 --dry-run",
                description: "Preview a beta schedule change."
            )
        ],
        "activity": [
            Example(
                command: "curfew-ctl activity --days 7",
                description: "Read seven days of activity."
            ),
            Example(
                command: "curfew-ctl activity --today --json",
                description: "Export today's activity."
            )
        ],
        "reflections": [
            Example(
                command: "curfew-ctl reflections --days 7",
                description: "Read recent reflections."
            ),
            Example(
                command: "curfew-ctl reflections --days 365 --json",
                description: "Export a year of reflections."
            )
        ],
        "budget": [
            Example(command: "curfew-ctl budget", description: "Read remaining grants."),
            Example(
                command: "curfew-ctl budget --json",
                description: "Read grant counts in a script."
            )
        ],
        "audit": [
            Example(command: "curfew-ctl audit --days 7", description: "Read retained app events."),
            Example(
                command: "curfew-ctl audit --days 7 --json",
                description: "Export retained app events."
            )
        ],
        "extension": [
            Example(
                command: "curfew-ctl extension --reason 'Finish saving' --dry-run",
                description: "Preview an extension request."
            ),
            Example(
                command: "curfew-ctl extension --reason 'Finish saving' --json",
                description: "Submit an extension request."
            )
        ],
        "request": [
            Example(
                command: "curfew-ctl request status <request-id>",
                description: "Read a request's decision."
            ),
            Example(
                command: "curfew-ctl request status <request-id> --json",
                description: "Read the decision in a script."
            ),
            Example(
                command: "curfew-ctl request prune",
                description: "Preview cleanup of old outcomes."
            )
        ],
        "work": [
            Example(command: "curfew-ctl work list", description: "List live work claims."),
            Example(
                command: "curfew-ctl work claim --label 'Nightly build' --dry-run",
                description: "Preview a protected-work claim."
            )
        ],
        "work claim": [
            Example(
                command: "curfew-ctl work claim --label 'Nightly build' --dry-run",
                description: "Preview a protected-work claim."
            ),
            Example(
                command: "curfew-ctl work claim --label 'Nightly build' --json",
                description: "Create a protected-work claim."
            )
        ],
        "work release": [
            Example(
                command: "curfew-ctl work release <claim-id> --dry-run",
                description: "Preview claim removal."
            ),
            Example(
                command: "curfew-ctl work release <claim-id> --json",
                description: "Release the claim."
            )
        ],
        "break-glass": [
            Example(
                command: "curfew-ctl break-glass --dry-run --reason 'Recover a pending shutdown'",
                description: "Preview emergency recovery."
            ),
            Example(
                command: "curfew-ctl break-glass --revoke --dry-run",
                description: "Preview release revocation."
            )
        ],
        "explain": [
            Example(
                command: "curfew-ctl explain data.invalid_state",
                description: "Explain an unreadable-state error."
            ),
            Example(
                command: "curfew-ctl explain permission.denied --json",
                description: "Read the remedy in a script."
            )
        ]
    ]

    static func render(_ generated: String) -> String {
        guard let usageRange = generated.range(of: "USAGE:") else { return generated }
        let usage = String(generated[usageRange.lowerBound...])
        let firstLine = usage.components(separatedBy: .newlines).first ?? ""
        let words = firstLine.split(separator: " ").dropFirst(2)
        let path = words.prefix { !$0.hasPrefix("[") && !$0.hasPrefix("<") && !$0.hasPrefix("-") }
            .joined(separator: " ")
        let key = examples[path] != nil ? path : path.split(separator: " ").first
            .map(String.init) ?? ""
        let rows = (examples[key] ?? examples[""] ?? []).map {
            "  \($0.description)\n  \($0.command)"
        }
        let defaults = [
            "": "Run without a command to show current status.\n\n",
            "work": "Run work without a subcommand to list active claims.\n\n",
            "schedule": "Run schedule without a subcommand to show saved rules.\n\n"
        ]
        let guide = CurfewServiceEndpoints.production.siteOrigin.appending(path: "docs/cli")
        return "EXAMPLES\n" + rows.joined(separator: "\n\n") +
            "\n\nCurfew command line (beta).\n\n" + (defaults[path] ?? "") +
            usage.replacingOccurrences(of: "SUBCOMMANDS:", with: "COMMANDS:") +
            "\nLEARN MORE\n  \(guide.absoluteString)\n"
    }
}
