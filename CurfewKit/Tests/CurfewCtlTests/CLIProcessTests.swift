@testable import curfew_ctl
import Foundation
import Testing

struct CLIProcessTests {
    @Test(
        "The executable follows pipe, terminal, pager, completion, and signal contracts"
    )
    func nativeAcceptance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = root.appendingPathComponent("CurfewKit/.build/debug/curfew-ctl")
        let script = root.appendingPathComponent("Tests/CLI/standards_acceptance.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, executable.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
        #expect(
            process.terminationStatus == 0,
            "\(String(bytes: diagnostic, encoding: .utf8) ?? "No diagnostic was returned.")"
        )
        if process.terminationStatus == 0 {
            let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect((result["checks"] as? Int ?? 0) >= 40)
        }
    }
}
