@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct LockPreviewSafetyTests {
    @MainActor
    private final class PreviewPresenterSpy: LockPreviewPresenting {
        private(set) var shown: [LockPreviewContent] = []
        private(set) var hideCount = 0

        func show(_ content: LockPreviewContent, onEnd _: @escaping () -> Void) {
            shown.append(content)
        }

        func hide() {
            hideCount += 1
        }
    }

    @Test("Previewing the lock never arms, records or sets a deadline, and always ends")
    func previewIsInert() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lock-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try ActivityRecorder(store: ActivityStore(directory: directory))
        let deadlines = LockoutDeadlineStore.ephemeralForTesting()
        let store = SetupModelFactory.store {
            $0.hasCompletedInitialSetup = false
            $0
                .schedule =
                WeeklySchedule(rules: Dictionary(uniqueKeysWithValues: Weekday.allCases.map {
                    ($0, DayRule(isDayOff: false, lockMinutes: 18 * 60, unlockMinutes: 7 * 60))
                }))
        }
        let model = SetupModelFactory.model(
            store: store, trusted: true, activity: recorder, deadlines: deadlines
        )
        let phaseBefore = model.state.phase
        let started = Date()
        let presenter = PreviewPresenterSpy()
        let preview = LockPreviewController(
            presenter: presenter,
            duration: .milliseconds(1),
            sleep: { _ in }
        )

        preview.present(model.lockPreviewContent(now: started, usesWeeklySchedule: true))
        await preview.waitUntilEnded()

        #expect(presenter.shown.count == 1)
        #expect(presenter.hideCount == 1)
        #expect(!preview.isPresenting)
        #expect(!model.started)
        #expect(!model.settings.hasCompletedInitialSetup)
        #expect(model.state.phase == phaseBefore)
        #expect(deadlines.load() == nil)
        #expect(recorder.events(in: started.addingTimeInterval(-86400) ... Date()).isEmpty)
    }

    @Test("The preview can be ended at once and ending twice is harmless")
    func previewEndsOnRequest() {
        let presenter = PreviewPresenterSpy()
        let preview = LockPreviewController(presenter: presenter, duration: .seconds(60))
        let curfew = Date()
        preview.present(LockPreviewContent(curfew: curfew, unlock: curfew.addingTimeInterval(3600)))
        #expect(preview.isPresenting)

        preview.dismiss()
        preview.dismiss()

        #expect(!preview.isPresenting)
        #expect(presenter.hideCount == 1)
    }
}
