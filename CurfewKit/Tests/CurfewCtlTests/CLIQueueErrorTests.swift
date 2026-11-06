@testable import curfew_ctl
import CurfewKit
import Testing

struct CLIQueueErrorTests {
    @Test("A reused request ID reports a usage error with an exact remedy")
    func identityConflict() {
        let error = CLIError.classify(MCPRequestQueueError.conflictingIdentity, parsing: false)
        #expect(error.code == "request.identity_conflict")
        #expect(error.exitStatus == 64)
        #expect(error.action?.contains("different request ID") == true)
        #expect(CLIError.explanations[error.code]?.1 == error.exitStatus)
    }

    @Test("A full request queue reports a blocked result rather than an internal failure")
    func fullQueue() {
        let error = CLIError.classify(MCPRequestQueueError.full, parsing: false)
        #expect(error.code == "request.queue_full")
        #expect(error.exitStatus == 69)
        #expect(error.action?.contains("curfew-ctl request prune") == true)
        #expect(CLIError.explanations[error.code]?.1 == error.exitStatus)
    }
}
