import ArgumentParser
import CurfewKit
import Darwin
import Foundation

struct CLIError: Error {
    let code: String
    let message: String
    let action: String?
    let exitStatus: Int32

    init(_ code: String, _ message: String, action: String? = nil, exitStatus: Int32) {
        self.code = code
        self.message = message
        self.action = action
        self.exitStatus = exitStatus
    }

    var object: [String: Any] {
        var result: [String: Any] = [
            "code": code, "message": message, "exit_status": Int(exitStatus)
        ]
        if let action {
            result["action"] = action
        }
        return result
    }

    var text: String {
        let label = [69, 77].contains(exitStatus) ? "Blocked" : "Error"
        return (["\(label): \(message)"] + [action].compactMap(\.self) + ["Code: \(code)"])
            .joined(separator: "\n")
    }

    static func classify(_ error: any Error, parsing: Bool) -> Self {
        if let error = error as? Self {
            return error
        }
        if let queueError = error as? MCPRequestQueueError {
            return queueFailure(queueError)
        }
        if parsing || error is ValidationError {
            let message = CurfewCLI.message(for: error)
            return Self(
                "usage.invalid_arguments",
                message,
                action: CLISuggestions.parserAction(for: message),
                exitStatus: 64
            )
        }
        let numeric = error as NSError
        if (numeric.domain == NSPOSIXErrorDomain && [EACCES, EPERM]
            .contains(Int32(numeric.code))) ||
            (numeric.domain == NSCocoaErrorDomain &&
                [NSFileReadNoPermissionError, NSFileWriteNoPermissionError]
                .contains(numeric.code)) {
            return Self(
                "permission.denied",
                "Curfew could not access the requested file.",
                action: "Check that your account can access Curfew's files.",
                exitStatus: 77
            )
        }
        if error is DecodingError || error is BoundedRegularFileReadError ||
            error is ActivityStoreError || error is ReflectionStoreError ||
            (numeric.domain == NSCocoaErrorDomain && numeric.code == CocoaError.Code
                .coderReadCorrupt.rawValue) {
            return Self(
                "data.invalid_state",
                "Curfew could not read the saved state.",
                action: "Open Curfew to inspect its status. Existing files were preserved.",
                exitStatus: 65
            )
        }
        if let localized = error as? any LocalizedError, let message = localized.errorDescription {
            return Self("state.operation_failed", message, exitStatus: 1)
        }
        return Self(
            "internal.unexpected",
            "Curfew encountered an unexpected problem.",
            exitStatus: 70
        )
    }

    private static func queueFailure(_ error: MCPRequestQueueError) -> Self {
        switch error {
        case .conflictingIdentity:
            Self(
                "request.identity_conflict", "The request ID belongs to a different action.",
                action: "Use a different request ID for a different action.", exitStatus: 64
            )
        case .full:
            Self(
                "request.queue_full", "The request queue is full.",
                action: "Preview cleanup with curfew-ctl request prune --all-resolved.",
                exitStatus: 69
            )
        }
    }

    static let explanations: [String: (String, Int32)] = [
        "request.identity_conflict": (
            "A request ID belongs to another action. " +
                "Use a different request ID for a different action.",
            64
        ),
        "request.queue_full": (
            "The saved request queue reached its size limit. " +
                "Preview cleanup with curfew-ctl request prune --all-resolved.",
            69
        ),
        "usage.invalid_arguments": (
            "A command, option, or value is invalid. Use --help to see accepted values.",
            64
        ),
        "permission.denied": (
            "Your account cannot access a required file. Check ownership and access permissions.",
            77
        ),
        "data.invalid_state": (
            "Saved Curfew state is invalid or unsafe to read. Preserve the original files.",
            65
        ),
        "state.operation_failed": (
            "Curfew could not complete the operation. Read the error for the required action.",
            1
        ),
        "state.unavailable": (
            "Curfew has no saved authority for this operation. Open Curfew and complete setup.",
            69
        ),
        "approval.integration_disabled": (
            "Local requests are disabled. Enable Allow assistants on this Mac in Integrations.",
            69
        ),
        "internal.unexpected": (
            "The command failed unexpectedly. Include the private support file in the report.",
            70
        )
    ]
}

struct ExplainCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "explain", abstract: "Explain a CLI error code and its exit status."
    )
    @Argument(help: "Error code, such as data.invalid_state.") var code: String
    @OptionGroup var options: CLIOptions

    func run() throws {
        guard let (description, exitStatus) = CLIError.explanations[code] else {
            let suggestion = CLISuggestions.closest(code, in: Array(CLIError.explanations.keys))
            throw CLIError(
                "usage.invalid_arguments",
                "Unknown error code '\(code)'.",
                action: suggestion.map { "Did you mean '\($0)'?" },
                exitStatus: 64
            )
        }
        if options.json {
            try CLIOutput.printJSON([
                "code": code,
                "description": description,
                "exit_status": Int(exitStatus)
            ])
        } else {
            print("\(code)\n\(description)\nExit status: \(exitStatus).")
        }
    }
}
