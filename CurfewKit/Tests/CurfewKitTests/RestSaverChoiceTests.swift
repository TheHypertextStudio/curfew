@testable import CurfewKit
import Testing

/// The owner's handoff rule: Curfew's own saver by default and only once it has
/// proven a full-screen render; the Mac's selected saver only by an opt-in that
/// exists only when one is selected; never anything while a saver is running.
struct RestSaverChoiceTests {
    private func decide(
        _ selection: RestSaverChoice.Selection, proven: Bool = false,
        usesSelected: Bool = false, running: Bool = false
    ) -> RestSaverChoice.Decision {
        RestSaverChoice.decide(
            selection: selection, curfewSaverProven: proven,
            usesSelectedSaver: usesSelected, saverRunning: running
        )
    }

    @Test("Curfew's saver, selected and proven, is the default handoff")
    func provenCurfewSaver() {
        #expect(decide(.curfew, proven: true) == .handOff(.curfew))
        #expect(decide(.curfew, proven: true, usesSelected: true) == .handOff(.curfew))
    }

    @Test("Curfew's saver without a full-screen receipt is never launched")
    func unprovenCurfewSaver() {
        #expect(decide(.curfew) == .stay(.curfewSaverNotProven))
        #expect(decide(.curfew, usesSelected: true) == .stay(.curfewSaverNotProven))
    }

    @Test("A foreign saver is launched only when the option is on")
    func foreignSaver() {
        #expect(decide(.other) == .stay(.curfewSaverNotSelected))
        #expect(decide(.other, proven: true) == .stay(.curfewSaverNotSelected))
        #expect(decide(.other, usesSelected: true) == .handOff(.selected))
    }

    @Test("With no saver selected nothing is launched, whatever the option says")
    func noSelection() {
        #expect(decide(.none) == .stay(.curfewSaverNotSelected))
        #expect(decide(.none, proven: true, usesSelected: true) == .stay(.curfewSaverNotSelected))
        #expect(decide(.unknown, proven: true, usesSelected: true) ==
            .stay(.curfewSaverNotSelected))
    }

    @Test("A saver already running means no launch and nothing to set up")
    func alreadyRunning() {
        for selection in [RestSaverChoice.Selection.curfew, .other, .none, .unknown] {
            #expect(decide(selection, proven: true, usesSelected: true, running: true) ==
                .stay(nil))
            #expect(decide(selection, running: true) == .stay(nil))
        }
    }

    @Test("The selected-saver option is offered only when another saver is selected")
    func optionOffered() {
        #expect(RestSaverChoice.offersSelectedSaverOption(selection: .other))
        #expect(!RestSaverChoice.offersSelectedSaverOption(selection: .curfew))
        #expect(!RestSaverChoice.offersSelectedSaverOption(selection: .none))
        #expect(!RestSaverChoice.offersSelectedSaverOption(selection: .unknown))
    }

    @Test("A saver that starts during a launch returns to the lock with no setup prompt")
    func launchFindsSaverRunning() throws {
        var policy = RestHandoffPolicy(monotonicSeconds: 0)
        _ = policy.handle(.reflectionResolved(.skipped), monotonicSeconds: 0)
        _ = policy.handle(.idleCheck, monotonicSeconds: 60)
        let generation = try #require(policy.pendingGeneration)
        _ = policy.handle(.settled(generation), monotonicSeconds: 61)
        _ = policy.handle(
            .launchCompleted(generation, .saverAlreadyRunning), monotonicSeconds: 62
        )
        #expect(policy.phase == .interactive)
        #expect(policy.setupStatus == nil)
    }
}
