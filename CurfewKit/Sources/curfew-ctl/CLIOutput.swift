import Foundation

enum CLIOutput {
    static func durationSeconds(_ minutes: Int) throws -> Int {
        let (seconds, overflow) = minutes.multipliedReportingOverflow(by: 60)
        guard !overflow else {
            throw CLIError(
                "data.invalid_state",
                "A saved duration is outside the supported range.",
                exitStatus: 65
            )
        }
        return seconds
    }

    static func data(_ object: [String: Any], status: String = "ok") throws -> Data {
        var payload = object
        payload.removeValue(forKey: "schema_version")
        if let value = payload.removeValue(forKey: "status") {
            payload["request_status"] = value
        }
        let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let body = String(bytes: encoded, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let statusData = try JSONSerialization.data(withJSONObject: [status])
        guard let encodedStatus = String(bytes: statusData, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let statusJSON = encodedStatus.dropFirst().dropLast()
        let fields = body.dropFirst().dropLast()
        let suffix = fields.isEmpty ? "}" : ",\(fields)}"
        return Data("{\"schema_version\":1,\"status\":\(statusJSON)\(suffix)".utf8)
    }

    static func printJSON(_ object: [String: Any], status: String = "ok") throws {
        guard let result = try String(bytes: data(object, status: status), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        print(result)
    }
}
