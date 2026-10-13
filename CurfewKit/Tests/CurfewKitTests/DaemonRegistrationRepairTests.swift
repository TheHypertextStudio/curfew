@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct DaemonRegistrationRepairTests {
    private enum Failure: Error { case blocked }

    @Test("Cancellation during removal still replaces the helper but never resumes commands")
    func cancellationDuringRemoval() async {
        var registered = false
        var resumed = false
        let repair = DaemonRegistrationRepair()
        let operation = Task { @MainActor in
            try await repair.run(
                quiesce: {}, admit: {},
                unregister: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    await Task.yield()
                },
                register: { registered = true }, verify: {},
                resume: { resumed = true }
            )
        }
        do {
            try await operation.value
            Issue.record("Cancelled maintenance resumed commands")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected repair error: \(error)")
        }
        #expect(registered)
        #expect(!resumed)
        #expect(repair.state == .failed)
    }

    @Test("Cancellation during authentication cannot activate producers")
    func cancellationDuringVerification() async {
        var resumed = false
        let repair = DaemonRegistrationRepair()
        let operation = Task { @MainActor in
            try await repair.run(
                quiesce: {}, admit: {}, unregister: {}, register: {},
                verify: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    await Task.yield()
                },
                resume: { resumed = true }
            )
        }
        do {
            try await operation.value
            Issue.record("Cancelled verification resumed commands")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected repair error: \(error)")
        }
        #expect(!resumed)
        #expect(repair.state == .failed)
    }

    @Test("A second repair cannot enter maintenance while the first is paused")
    func concurrentRepairIsRejected() async throws {
        var rejected = false
        var secondQuiesced = false
        let repair = DaemonRegistrationRepair()
        try await repair.run(
            quiesce: {
                let overlapping = Task { @MainActor in
                    try await repair.run(
                        quiesce: { secondQuiesced = true }, admit: {},
                        unregister: {}, register: {}, verify: {}, resume: {}
                    )
                }
                do {
                    try await overlapping.value
                    Issue.record("Overlapping repair entered maintenance")
                } catch DaemonRegistrationRepair.RepairError.alreadyRepairing {
                    rejected = true
                }
            },
            admit: {}, unregister: {}, register: {}, verify: {}, resume: {}
        )
        #expect(rejected)
        #expect(!secondQuiesced)
        #expect(repair.state == .ready)
    }

    @Test("Repair cannot register or resume until unregister has completed")
    func orderedRepair() async throws {
        var events: [String] = []
        let repair = DaemonRegistrationRepair()
        try await repair.run(
            quiesce: { events.append("paused") },
            admit: { events.append("inactive") },
            unregister: {
                events.append("unregister-start")
                await Task.yield()
                events.append("unregister-complete")
            },
            register: { events.append("registered") },
            verify: { events.append("authenticated") },
            resume: { events.append("resumed") }
        )
        #expect(events == [
            "paused",
            "inactive",
            "unregister-start",
            "unregister-complete",
            "registered",
            "authenticated",
            "resumed"
        ])
        #expect(repair.state == .ready)
    }

    @Test("An active or unreadable deadline prevents helper removal")
    func admissionFailure() async {
        var removed = false
        var resumed = false
        let repair = DaemonRegistrationRepair()
        do {
            try await repair.run(
                quiesce: {}, admit: { throw Failure.blocked },
                unregister: { removed = true }, register: {}, verify: {},
                resume: { resumed = true }
            )
            Issue.record("Unsafe maintenance was admitted")
        } catch {}
        #expect(!removed)
        #expect(!resumed)
        #expect(repair.state == .failed)
    }

    @Test("Failed replacement leaves producers paused and protection unavailable")
    func registrationFailure() async {
        var authenticated = false
        var resumed = false
        let repair = DaemonRegistrationRepair()
        do {
            try await repair.run(
                quiesce: {}, admit: {}, unregister: {},
                register: { throw Failure.blocked },
                verify: { authenticated = true }, resume: { resumed = true }
            )
            Issue.record("Failed replacement was reported ready")
        } catch {}
        #expect(!authenticated)
        #expect(!resumed)
        #expect(repair.state == .failed)
    }

    @Test("Registration without authenticated health never resumes commands")
    func authenticationFailure() async {
        var resumed = false
        let repair = DaemonRegistrationRepair()
        do {
            try await repair.run(
                quiesce: {}, admit: {}, unregister: {}, register: {},
                verify: { throw Failure.blocked }, resume: { resumed = true }
            )
            Issue.record("Unauthenticated helper was reported ready")
        } catch {}
        #expect(!resumed)
        #expect(repair.state == .failed)
    }
}
