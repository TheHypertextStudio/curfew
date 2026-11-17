import AppKit
@testable import Curfew
import CurfewAtmosphere
@testable import CurfewKit
import Foundation
import Testing

/// The lock's words, the arrival and leaving timeline, the override composer
/// and the evening close-out, as pure values.
/// The move into and out of the lock, and how the lock window and model use
/// it: the arrival waits to be seen, is shared across displays, and leaving
/// fades before windows go.
@MainActor
struct LockTransitionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Arrival and leaving

    @Test("The arrival waits until the screen is seen, then runs about two seconds")
    func arrivalWaitsToBeSeen() {
        var timeline = LockSceneTimeline()
        #expect(timeline.stage(at: now) == .waitingToBeSeen)
        #expect(timeline.arrival(at: now.addingTimeInterval(600)) == 0)
        timeline.seen(at: now, reduceMotion: false)
        #expect(timeline.stage(at: now.addingTimeInterval(1)) == .arriving)
        #expect(timeline.arrival(at: now.addingTimeInterval(1)) > 0)
        #expect(timeline.stage(at: now.addingTimeInterval(2.01)) == .settled)
        #expect(LockSceneTimeline.arrivalDuration(reduceMotion: false) == 2)
    }

    @Test("Seeing the screen again does not restart the arrival")
    func seenTwiceKeepsStart() {
        var timeline = LockSceneTimeline()
        timeline.seen(at: now, reduceMotion: false)
        timeline.seen(at: now.addingTimeInterval(1), reduceMotion: false)
        #expect(timeline.arrival(at: now.addingTimeInterval(2)) == 1)
    }

    @Test("A display attached mid-lock shares the arrival rather than restarting it")
    func sharedTimelineForNewDisplay() {
        let scene = LockScene()
        scene.seen(at: now, reduceMotion: false)
        let later = now.addingTimeInterval(60)
        scene.seen(at: later, reduceMotion: false)
        #expect(scene.timeline.stage(at: later) == .settled)
    }

    @Test("The arrival moves in order: the sky, then the clock, then the words")
    func arrivalOrder() {
        var timeline = LockSceneTimeline()
        timeline.seen(at: now, reduceMotion: false)
        let early = now.addingTimeInterval(0.4)
        #expect(timeline.sky(at: early) > 0)
        #expect(timeline.words(at: early) == 0)
        let late = now.addingTimeInterval(1.9)
        #expect(timeline.sky(at: late) == 1)
        #expect(timeline.words(at: late) > 0)
        #expect(timeline.clock(at: now.addingTimeInterval(1.5)) == 1)
    }

    @Test("Under Reduce Motion the arrival is a short fade with no sky move")
    func reduceMotionArrival() {
        var timeline = LockSceneTimeline()
        timeline.seen(at: now, reduceMotion: true)
        #expect(timeline.sky(at: now) == 1)
        #expect(timeline.clock(at: now) == 1)
        #expect(timeline.stage(at: now.addingTimeInterval(0.31)) == .settled)
    }

    @Test("Leaving fades to the desktop, shorter under Reduce Motion, and a relock cancels it")
    func leaving() {
        var timeline = LockSceneTimeline()
        timeline.seen(at: now, reduceMotion: false)
        timeline.release(at: now.addingTimeInterval(10), reduceMotion: false)
        #expect(timeline.stage(at: now.addingTimeInterval(10.5)) == .leaving)
        #expect(timeline.stage(at: now.addingTimeInterval(11.3)) == .gone)
        #expect(LockSceneTimeline.leavingDuration(reduceMotion: false) == 1.2)
        #expect(LockSceneTimeline.leavingDuration(reduceMotion: true) == 0.3)
        timeline.relock()
        #expect(timeline.stage(at: now.addingTimeInterval(20)) == .settled)
    }

    @Test("Windows leave only after their fade completes")
    func windowStoreFadesBeforeOrderingOut() {
        var completions: [() -> Void] = []
        let store = RestWindowStore(fade: { _, _, done in completions.append(done) })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless,
            backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        store.reconcile(displays: [RestDisplay(id: 1, frame: window.frame)]) { _ in window }
        store.leave(duration: 1.2)
        #expect(store.windows.isEmpty)
        #expect(store.departingCount == 1)
        #expect(completions.count == 1)
        completions.first?()
        #expect(store.departingCount == 0)
    }

    // MARK: Wiring

    @Test("The lock window's sky starts at the sky in view and settles on the lock's night")
    func lockWindowSkyFollowsTheArrival() throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let curfew = try #require(calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day))
        let unlock = try #require(calendar.date(byAdding: .hour, value: 13, to: curfew))
        let model = CurfewAppModel.demoModel()
        model.currentTime = curfew.addingTimeInterval(5)
        model.state = CurfewEvaluation(
            phase: .locked, warningStage: .lockout, minutesRemaining: 0,
            canRequestExtension: false, lockDate: curfew, unlockDate: unlock
        )
        let before = model.horizonFrame
        let scene = LockScene()
        scene.begin(at: model.currentTime, startingFrame: before)
        let view = RestScreenView(model: model, display: RestDisplayPresentation(), scene: scene)
        let fallback = HorizonMoment.restingNight(at: model.currentTime).frame
        #expect(view.lockFrame(fallback: fallback, at: model.currentTime) == before)
        scene.seen(at: model.currentTime, reduceMotion: false)
        let settled = model.currentTime.addingTimeInterval(3)
        var moment = model.horizonMoment()
        moment.now = settled
        #expect(view.lockFrame(fallback: fallback, at: settled) == LockSceneSky.frame(for: moment))
    }

    @Test("A lock that began before its scheduled curfew keeps the sky's curfew at its start")
    func anchoredCurfew() {
        let scene = LockScene()
        scene.begin(at: now, startingFrame: HorizonMoment.restingNight(at: now).frame)
        #expect(scene.anchoredCurfew(now.addingTimeInterval(120)) == now)
        #expect(scene.anchoredCurfew(now.addingTimeInterval(-60)) == now.addingTimeInterval(-60))
    }

    @Test("Saving the close-out stores whether the one thing was done")
    func closeOutRecordsTheAnswer() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "close-out")
        let suite = "studio.hypertext.curfew.tests.closeout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: ActivityRecorder(store: store),
            lockoutDeadlineStore: ModelTestSupport.lockoutDeadlineStore(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        model.currentTime = now
        model.saveEveningCloseOut(
            answers: [],
            closeOut: EveningCloseOut(oneThing: "Ship", oneThingDone: true)
        )
        let answers = try store.events(in: .distantPast ... .distantFuture)
            .compactMap(OneThingOutcome.done(from:))
        #expect(answers == [true])
        model.saveEveningCloseOut(
            answers: [],
            closeOut: EveningCloseOut(oneThing: nil, oneThingDone: true)
        )
        let after = try store.events(in: .distantPast ... .distantFuture)
            .compactMap(OneThingOutcome.done(from:))
        #expect(after == [true])
    }

    @Test("The selected saver is read from the screen saver preferences")
    func selectionReader() {
        #expect(RestSaverSelectionReader.selection(moduleDict: nil) == .none)
        #expect(RestSaverSelectionReader.selection(moduleDict: [
            "path": "/Users/me/Library/Screen Savers/Curfew.saver", "moduleName": "Curfew"
        ]) == .curfew)
        #expect(RestSaverSelectionReader.selection(moduleDict: [
            "path": "/System/Library/Screen Savers/Flurry.saver", "moduleName": "Flurry"
        ]) == .other)
        #expect(RestSaverSelectionReader.selection(moduleDict: [:]) == .unknown)
    }

    @Test("Start the screen saver is offered only when a handoff is allowed")
    func restNowOnlyWhenAllowed() {
        let model = CurfewAppModel.demoModel()
        #expect(!model.canRestNow)
        model.restRuntime.handoff.decision = .stay(.curfewSaverNotProven)
        #expect(!model.canRestNow)
        #expect(model.restSaverMissing == .curfewSaverNotProven)
        model.restRuntime.handoff.decision = .stay(nil)
        #expect(model.restSaverMissing == nil)
    }
}
