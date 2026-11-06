import ArgumentParser
import CurfewKit
import Foundation

struct ExtensionCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "extension", abstract: "Request an extension through Curfew's approval policy."
    )
    @Option(name: .long, help: "Why you need more time.")
    var reason: String
    @Option(name: .long, help: "Stable UUID for safely retrying this same request.")
    var id: String?
    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    @Flag(
        name: [.long, .customShort("n")],
        help: "Preview the request without signing or queuing it."
    )
    var dryRun: Bool = false

    mutating func validate() throws {
        _ = try id.map(parseCLIRequestID)
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("--reason must not be empty.")
        }
    }

    func makeRequest() throws -> MCPPendingRequest {
        let data = try JSONSerialization.data(
            withJSONObject: ["reason": reason.trimmingCharacters(in: .whitespacesAndNewlines)],
            options: .sortedKeys
        )
        return try MCPPendingRequest(
            id: id.map(parseCLIRequestID) ?? UUID(),
            tool: .requestExtension,
            argumentsJSON: String(data: data, encoding: .utf8) ?? "{}"
        )
    }

    func run() throws {
        try submitCLIRequest(makeRequest(), json: json, dryRun: dryRun, options: options)
    }
}

struct RequestCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "request",
        abstract: "Inspect approval decisions or clean up resolved records.",
        subcommands: [RequestStatusCommand.self, RequestPruneCommand.self]
    )

    @OptionGroup var options: CLIOptions
}

struct RequestStatusCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show pending, approved, denied, or missing request status."
    )
    @Argument(help: "Request UUID.")
    var id: String
    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    func run() throws {
        try printCLIRequestResult(
            Self.result(id: parseCLIRequestID(id), requests: MCPRequestQueue.loadChecked()),
            json: json, options: options
        )
    }

    static func result(id: UUID, requests: [MCPPendingRequest]) -> [String: Any] {
        guard let request = requests.first(where: { $0.id == id }) else {
            return ["request_id": id.uuidString, "status": "not_found"]
        }
        var object: [String: Any] = [
            "request_id": id.uuidString,
            "status": request.status.rawValue,
            "tool": request.tool.rawValue
        ]
        if let resolvedAt = request
            .resolvedAt {
            object["resolved_at"] = ISO8601DateFormatter().string(from: resolvedAt)
        }
        if let reason = request.denialReason {
            object["denial_reason"] = reason
        }
        return object
    }
}

func submitCLIRequest(
    _ unsignedRequest: MCPPendingRequest,
    json: Bool,
    dryRun: Bool = false,
    options: CLIOptions? = nil,
    settings suppliedSettings: CurfewSettings? = nil,
    queueURL: URL = SharedPaths.mcpRequestQueue,
    sign: (MCPPendingRequest) -> String? = { MCPRequestSigner.sign($0) },
    emit suppliedEmit: (([String: Any], Bool) throws -> Void)? = nil
) throws {
    let emit = suppliedEmit ?? { result, json in
        try printCLIRequestResult(result, json: json, options: options)
    }
    let settings = suppliedSettings ?? loadSettings()
    guard settings.hasCompletedInitialSetup else {
        throw CLIError(
            "state.unavailable",
            "Open Curfew and complete setup before requesting changes.",
            exitStatus: 69
        )
    }
    guard settings.mcpEnabled else {
        throw CLIError(
            "approval.integration_disabled",
            "Turn on ‘Allow assistants on this Mac’ in Curfew Settings → Integrations " +
                "before requesting changes.",
            exitStatus: 69
        )
    }
    if dryRun {
        let preview: [String: Any] = try [
            "dry_run": true, "request_id": unsignedRequest.id.uuidString,
            "tool": unsignedRequest.tool.rawValue, "queue_path": queueURL.path,
            "arguments": JSONSerialization
                .jsonObject(with: Data(unsignedRequest.argumentsJSON.utf8))
        ]
        try emit(preview, json)
        return
    }
    var request = unsignedRequest
    request.signature = sign(request)
    try MCPRequestQueue.append(request, to: queueURL)
    let result = try RequestStatusCommand.result(
        id: request.id,
        requests: MCPRequestQueue.loadChecked(from: queueURL)
    )
    try emit(result, json)
}

func printCLIRequestResult(
    _ result: [String: Any], json: Bool, options suppliedOptions: CLIOptions? = nil
) throws {
    if json {
        try CLIOutput.printJSON(result)
        return
    }
    var lines: [String] = []
    if result["dry_run"] as? Bool == true {
        lines
            .append(
                "Would submit \(result["tool"] ?? "the request") to \(result["queue_path"] ?? "Curfew")."
            )
        lines.append("Curfew's approval policy decides whether to grant it.")
    } else {
        lines.append("Request: \(result["request_id"] ?? "unknown")")
        lines.append("Status: \(result["status"] ?? "unknown")")
        if let reason = result["denial_reason"] {
            lines.append("Reason: \(reason)")
        }
        if result["status"] as? String == "pending" {
            lines.append("Curfew has not reported a final outcome yet.")
            lines.append("Check with curfew-ctl request status <request-id>.")
        }
    }
    let options = try suppliedOptions ?? CLIOptions.parse([])
    try CLIText.print(lines.joined(separator: "\n"), title: "Curfew request", options: options)
}

func parseCLIRequestID(_ text: String) throws -> UUID {
    guard let id = UUID(uuidString: text)
    else { throw ValidationError("Request ID must be a UUID.") }
    return id
}
