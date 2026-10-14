@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct FirstRunSafetyFlowTests {
    @Test("Opening the schedule editor alone cannot authorize automatic lockout")
    func openingScheduleDoesNotConfirmIt() {
        var flow = FirstRunFlow()
        flow.advance()

        flow.markScheduleReviewed()

        #expect(!flow.canAdvance)
        flow.advance()
        #expect(flow.currentStep == .schedule)
    }
}

@MainActor
struct FirstRunSafetyModelTests {
    @Test("First-run schedule edits replace the draft immediately without cooldown")
    func firstRunScheduleEditIsImmediate() {
        let suiteName = "CurfewSettingsStoreTests.InitialSchedule.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        var proposed = model.settings.schedule
        proposed.rules[.monday]?.lockMinutes = 22 * 60

        model.queueScheduleUpdate(proposed)

        #expect(model.settings.schedule.rule(for: .monday).lockMinutes == 22 * 60)
        #expect(model.settings.pendingScheduleChange == nil)
    }
}
