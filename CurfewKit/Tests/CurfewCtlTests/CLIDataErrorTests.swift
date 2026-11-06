@testable import curfew_ctl
import Foundation
import Testing

struct CLIDataErrorTests {
    @Test("Invalid runtime records report data failure rather than an operation failure")
    func invalidRuntimeRecord() {
        let error = CLIError.classify(CocoaError(.coderReadCorrupt), parsing: false)
        #expect(error.code == "data.invalid_state")
        #expect(error.exitStatus == 65)
    }
}
