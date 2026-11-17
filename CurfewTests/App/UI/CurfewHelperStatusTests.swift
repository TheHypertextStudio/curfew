@testable import Curfew
import ServiceManagement
import Testing

struct CurfewHelperStatusTests {
    typealias Inputs = CurfewHelperStatus.Inputs

    @Test("A healthy helper says so plainly and offers nothing to press")
    func ready() {
        let status = CurfewHelperStatus(Inputs())
        #expect(status.tone == .ready)
        #expect(status.sentence == CurfewHelperStatus.readySentence)
        #expect(status.action == nil)
    }

    @Test("Every state that needs attention outside a lock offers an action")
    func everyProblemHasAWayForward() {
        let cases: [Inputs] = [
            Inputs(restartStatus: .requiresApproval),
            Inputs(helperStatus: .requiresApproval),
            Inputs(loginItemStatus: .requiresApproval),
            Inputs(restartStatus: .notRegistered),
            Inputs(helperStatus: .notFound),
            Inputs(connection: .registrationFailed),
            Inputs(connection: .stale),
            Inputs(connection: .unauthorized),
            Inputs(connection: .unavailable),
            Inputs(maintenancePaused: true),
            Inputs(connection: .stale, canReconnectInPlace: false),
            Inputs(restartProblem: true)
        ]
        for inputs in cases {
            let status = CurfewHelperStatus(inputs)
            #expect(status.tone == .attention, "\(inputs)")
            #expect(status.action != nil, "\(inputs)")
        }
    }

    @Test("Approval comes before setup, and setup names the helper")
    func actions() {
        #expect(CurfewHelperStatus(Inputs(helperStatus: .requiresApproval)).action
            == .allowInSystemSettings)
        #expect(CurfewHelperStatus(Inputs(restartStatus: .notRegistered)).action == .setUp)
        #expect(CurfewHelperStatus(Inputs(connection: .stale)).action == .reconnect)
        #expect(CurfewHelperStatus(Inputs(connection: .stale, canReconnectInPlace: false))
            .action == .reopenCurfew)
    }

    @Test("The helper is never repaired during a lock, and the row says when it can be")
    func lockedRefusesRepair() {
        let status = CurfewHelperStatus(Inputs(connection: .stale, isLocked: true))
        #expect(status.action == nil)
        #expect(status.sentence.hasSuffix("You can fix this once curfew lifts."))
    }

    @Test("Builds without the privileged helper ignore its registration")
    func helperNotRequired() {
        let status = CurfewHelperStatus(Inputs(helperRequired: false, helperStatus: .notRegistered))
        #expect(status.tone == .ready)
    }

    @Test("Helper copy uses one name and no implementation words")
    func vocabulary() {
        let all: [Inputs] = [
            Inputs(), Inputs(inProgress: true), Inputs(restartStatus: .requiresApproval),
            Inputs(restartStatus: .notRegistered), Inputs(connection: .registrationFailed),
            Inputs(connection: .stale), Inputs(connection: .unauthorized),
            Inputs(restartProblem: true), Inputs(restartHealthy: false)
        ]
        for inputs in all {
            let sentence = CurfewHelperStatus(inputs).sentence
            #expect(sentence.contains("Curfew helper"), "\(sentence)")
            for banned in ["daemon", "supervisor", "background", "enforce", "recovery"] {
                #expect(!sentence.lowercased().contains(banned), "\(sentence)")
            }
        }
    }
}
