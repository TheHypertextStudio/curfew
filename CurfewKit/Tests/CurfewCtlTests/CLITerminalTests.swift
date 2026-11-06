@testable import curfew_ctl
import Foundation
import Testing

struct CLITerminalTests {
    @Test("Terminal prose wraps within its margin while paths stay intact")
    func terminalWrapping() {
        let path = "/a/long/path/that/must/not/be/split/inside/a/token"
        let text = "This prose explains a recorded event without losing its words.\n\(path)"
        let result = CLIText.render(
            text,
            title: "Activity",
            terminal: true,
            width: 40,
            color: false
        )
        #expect(result.hasPrefix("Activity\n\n  This prose"))
        #expect(result.contains("  \(path)"))
        for line in result.split(separator: "\n") where !line.contains(path) {
            #expect(line.count <= 40)
        }
        #expect(CLIText
            .render(text, title: "Activity", terminal: false, width: 40, color: false) == text)
    }

    @Test("Pagers run only for long interactive output")
    func pagerGating() {
        let text = Array(repeating: "A recorded event.", count: 20).joined(separator: "\n")
        #expect(CLIText.shouldPage(
            text,
            streams: (stdout: true, stdin: true),
            rows: 10,
            noPager: false,
            environment: [:]
        ))
        #expect(!CLIText.shouldPage(
            text,
            streams: (stdout: false, stdin: true),
            rows: 10,
            noPager: false,
            environment: [:]
        ))
        #expect(!CLIText.shouldPage(
            text,
            streams: (stdout: true, stdin: false),
            rows: 10,
            noPager: false,
            environment: [:]
        ))
        #expect(!CLIText.shouldPage(
            text,
            streams: (stdout: true, stdin: true),
            rows: 10,
            noPager: true,
            environment: [:]
        ))
        #expect(!CLIText.shouldPage(
            text,
            streams: (stdout: true, stdin: true),
            rows: 10,
            noPager: false,
            environment: ["CI": "true"]
        ))
        #expect(!CLIText.shouldPage(
            text,
            streams: (stdout: true, stdin: true),
            rows: 10,
            noPager: false,
            environment: ["PAGER": ""]
        ))
    }

    @Test("Color control follows NO_COLOR before forced color")
    func colorControl() {
        #expect(!CLIText.colorEnabled(
            terminal: true,
            noColor: false,
            environment: ["NO_COLOR": "1", "FORCE_COLOR": "1"]
        ))
        #expect(!CLIText.colorEnabled(
            terminal: true,
            noColor: true,
            environment: ["FORCE_COLOR": "1"]
        ))
        #expect(!CLIText.colorEnabled(
            terminal: true,
            noColor: false,
            environment: ["TERM": "dumb"]
        ))
        #expect(CLIText.colorEnabled(
            terminal: false,
            noColor: false,
            environment: ["FORCE_COLOR": "1"]
        ))
    }

    @Test("First interruption waits for the protected step and the second stops immediately")
    func interruptionState() {
        var messages: [String] = []
        var forced: [Int32] = []
        let interrupts = CLIInterrupts(
            message: { messages.append($0) },
            forceExit: { forced.append($0) }
        )
        interrupts.receive(SIGINT)
        #expect(interrupts.exitStatus == 130)
        #expect(forced.isEmpty)
        #expect(messages.count == 1)
        interrupts.receive(SIGINT)
        #expect(forced == [130])
        let terminated = CLIInterrupts(message: { _ in }, forceExit: { _ in })
        terminated.receive(SIGTERM)
        #expect(terminated.exitStatus == 143)
    }
}
