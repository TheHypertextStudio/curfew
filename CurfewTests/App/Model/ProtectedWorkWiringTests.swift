@testable import Curfew
import Foundation
import Testing

/// Wiring tests proving the glue between `CurfewAppModel` and the carve-out.
///
/// Every other test in this area calls `ShutdownWorkflow.update` directly with
/// hand-supplied booleans, which proves the state machine and nothing about
/// whether the model ever hands it the truth. These drive the model itself:
/// the user's policy, the live claims file, and the emergency release all have
/// to arrive at `protectedWorkContext()`, the release has to be scoped to the
/// window in `lockoutDeadlineStore`, and the rollover cleanup has to fire.
@MainActor
struct ProtectedWorkWiringTests {
    private let goodReason = "daemon fired during an agent run"

    // MARK: - Settings reach the context

    @Test("The user's policy reaches the shutdown workflow's inputs")
    func policyReachesTheContext() {
        let scratch = Scratch()
        defer { scratch.clean() }
        let model = scratch.makeModel()

        var policy = ProtectedWorkPolicy.default
        policy.protectedProcessNames = ["my-agent"]
        policy.maximumDeferralMinutes = 45
        model.settings.protectedWork = policy

        let context = model.protectedWorkContext()
        #expect(context.policy.protectedProcessNames == ["my-agent"])
        #expect(context.policy.maximumDeferralMinutes == 45)
        #expect(context.policy.protectsApplication(
            bundleIdentifier: nil,
            executableName: "my-agent"
        ))
    }

    // MARK: - Live claims reach the context

    @Test("A live claim on disk reaches the shutdown workflow's inputs")
    func liveClaimReachesTheContext() throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let model = scratch.makeModel()
        model.currentTime = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(model.protectedWorkContext().hasActiveWork == false)

        try model.protectedWork.claims.claim(
            label: "delegate: build athena",
            source: .cli,
            leaseMinutes: 5,
            now: model.currentTime,
            policy: .default
        )
        #expect(model.protectedWorkContext().hasActiveWork)

        // And it lapses on its own once the lease runs out.
        model.currentTime = model.currentTime.addingTimeInterval(6 * 60)
        #expect(model.protectedWorkContext().hasActiveWork == false)
    }

    // MARK: - Break-glass reaches the context, scoped to the window

    @Test("A release issued inside the current window reaches the inputs")
    func breakGlassReachesTheContext() throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let model = scratch.makeModel()
        let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)
        model.currentTime = lockoutStart.addingTimeInterval(600)

        model.lockoutDeadlineStore.save(
            LockoutDeadlineRecord(
                lockoutStartedAt: lockoutStart,
                scheduledUnlockAt: lockoutStart.addingTimeInterval(10 * 60 * 60),
                kind: .scheduledTime
            )
        )
        #expect(model.protectedWorkContext().isBreakGlassActive == false)

        try model.protectedWork.breakGlass.issue(
            reason: goodReason,
            issuedBy: "willie@mac",
            now: lockoutStart.addingTimeInterval(300)
        )
        #expect(model.protectedWorkContext().isBreakGlassActive)
        #expect(model.isBreakGlassActive())
    }

    @Test("A release from an earlier window does not reach the inputs")
    func staleReleaseIsScopedOut() throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let model = scratch.makeModel()
        // The gap is deliberately shorter than `BreakGlassStore.defaultValidity`.
        // With a 20-hour gap the record would age out on its own and this
        // would pass even with the window scoping removed — it has to be the
        // scoping doing the work, not the clock.
        let earlierWindow = Date(timeIntervalSince1970: 1_800_000_000)
        let tonight = earlierWindow.addingTimeInterval(2 * 60 * 60)
        model.currentTime = tonight.addingTimeInterval(600)

        try model.protectedWork.breakGlass.issue(
            reason: goodReason,
            issuedBy: "willie@mac",
            now: earlierWindow
        )
        model.lockoutDeadlineStore.save(
            LockoutDeadlineRecord(
                lockoutStartedAt: tonight,
                scheduledUnlockAt: tonight.addingTimeInterval(10 * 60 * 60),
                kind: .scheduledTime
            )
        )

        // The record verifies and is well inside its validity; it simply
        // belongs to a window that has passed.
        #expect(model.protectedWork.breakGlass.load() != nil)
        #expect(model.protectedWork.breakGlass.activeRelease(now: model.currentTime) != nil)
        #expect(model.protectedWorkContext().isBreakGlassActive == false)
    }

    // MARK: - Rollover cleanup

    @Test("A window ending naturally clears the release and the claims")
    func naturalUnlockClearsCarveOutState() throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let model = scratch.makeModel()
        let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)
        let unlock = lockoutStart.addingTimeInterval(8 * 60 * 60)

        model.lockoutDeadlineStore.save(
            LockoutDeadlineRecord(
                lockoutStartedAt: lockoutStart,
                scheduledUnlockAt: unlock,
                kind: .scheduledTime
            )
        )
        try model.protectedWork.breakGlass.issue(
            reason: goodReason,
            issuedBy: "willie@mac",
            now: lockoutStart.addingTimeInterval(60)
        )
        try model.protectedWork.claims.claim(
            label: "overnight job",
            source: .cli,
            now: lockoutStart.addingTimeInterval(60),
            policy: .default
        )

        // Still inside the window: nothing is cleared.
        model.currentTime = unlock.addingTimeInterval(-60)
        model.clearDurableDeadlineIfNaturalUnlock()
        #expect(model.protectedWork.breakGlass.load() != nil)
        #expect(model.protectedWork.claims.load().isEmpty == false)

        // Window over: tonight's emergency must not disarm tomorrow.
        model.currentTime = unlock.addingTimeInterval(1)
        model.clearDurableDeadlineIfNaturalUnlock()
        #expect(model.lockoutDeadlineStore.load() == nil)
        #expect(model.protectedWork.breakGlass.load() == nil)
        #expect(model.protectedWork.claims.load().isEmpty)
    }

    // MARK: - Support

    /// A temporary directory plus a model wired to it, so no test touches the
    /// real Application Support directory.
    private final class Scratch {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        @MainActor
        func makeModel() -> CurfewAppModel {
            let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)

            let model = CurfewAppModel(
                settingsStore: CurfewSettingsStore(defaults: defaults),
                appRouter: AppRouterSpy(),
                gettingStartedPresenter: GettingStartedPresenterSpy(),
                activityRecorder: NullActivityRecording(),
                lockoutDeadlineStore: LockoutDeadlineStore(
                    recordURL: directory.appendingPathComponent("lockout-deadline.json")
                ),
                accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
            )
            model.protectedWork = ProtectedWorkStores(
                claims: ProtectedWorkStore(
                    recordURL: directory.appendingPathComponent("protected-work.json")
                ),
                breakGlass: BreakGlassStore(
                    recordURL: directory.appendingPathComponent("break-glass.json"),
                    secretURL: directory.appendingPathComponent(".break-glass-secret")
                )
            )
            return model
        }

        func clean() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
