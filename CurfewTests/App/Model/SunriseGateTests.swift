@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// The Sunrise gate on the model: when it appears (including after a cold
/// start), how its pages advance, how answering saves the one thing and
/// releases the Mac, the hold released when there is no gate, and the
/// Shortcut that runs afterwards. No test launches a real Shortcut or touches
/// native power: every effect is injected.
@MainActor
struct SunriseGateTests {
    private nonisolated static func localDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // 2026-10-19 is a Monday. `.tenToSix` works 06:00 to 22:00 on weekdays.
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: day, hour: hour, minute: minute
        ))!
    }

    private func makeModel(
        now: Date = localDate(19, 9),
        reflections: MemoryReflections? = nil
    ) throws -> CurfewAppModel {
        let reflections = reflections ?? MemoryReflections()
        let suite = "SunriseGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.schedule = .tenToSix
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        store.saveAutomaticScheduleConsent(true)
        return CurfewAppModel(
            settingsStore: store, appRouter: AppRouterSpy(), flavor: .production,
            featureFlags: FeatureFlags(
                widgetKitEnabled: false, cloudSyncEnabled: false, mcpServerEnabled: false,
                privilegedHelperEnabled: false, calendarEnabled: false
            ),
            activityRecorder: NullActivityRecording(),
            reflectionState: ReflectionRuntimeState(recorder: reflections),
            licenseGate: LicenseGate(defaults: defaults),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accountWakeLedgerStore: AccountWakeLedgerStore(recordURL: FileManager.default
                .temporaryDirectory.appendingPathComponent("sunrise-gate-\(UUID()).json")),
            runtimeNow: now,
            enforcementClock: { now }
        )
    }

    private func working(_ model: CurfewAppModel) {
        model.state = CurfewEvaluation(
            phase: .working, warningStage: .none, minutesRemaining: 600,
            canRequestExtension: true, lockDate: Self.localDate(19, 22), unlockDate: nil
        )
    }

    private static func evening(at date: Date, left: String) -> Reflection {
        Reflection(timestamp: date, gate: .evening, answers: [ReflectionAnswer(
            promptID: ReflectionDefaults.leftForNextTimePromptID,
            promptTextSnapshot: "What would you like to continue next time?", value: .text(left)
        )])
    }

    // MARK: - Trigger

    @Test("A cold start in the working day with the morning unanswered opens the gate")
    func coldStartOpensGate() throws {
        let model = try makeModel()
        #expect(model.state.phase == .working)
        #expect(model.reflectionState.isDaybreakPresented)
        #expect(!model.sunriseRuntime.pages.isEmpty)
    }

    @Test("A cold start after this morning was answered does not open the gate")
    func coldStartAfterAnswerStaysClosed() throws {
        let reflections = MemoryReflections()
        reflections.record(Reflection(
            timestamp: Self.localDate(19, 7), gate: .morning, answers: []
        ))
        let model = try makeModel(reflections: reflections)
        #expect(!model.reflectionState.isDaybreakPresented)
    }

    @Test("Last night's note is read when the gate opens and leads the first page")
    func noteLeadsFirstPage() throws {
        let reflections = MemoryReflections()
        reflections.record(Self.evening(at: Self.localDate(16, 22), left: "pick up the retry test"))
        let model = try makeModel(reflections: reflections)
        #expect(model.sunriseRuntime.pages.first?.note == "pick up the retry test")
        #expect(model.sunriseRuntime.pages.first?.prompt?.text == "What is today for?")
    }

    @Test("With every step off there is no gate")
    func noStepsNoGate() throws {
        let model = try makeModel()
        model.reflectionState.isDaybreakPresented = false
        model.reflectionState.gatesResolvedToday.removeAll()
        model.updateSunriseSteps(model.sunriseSteps.map {
            SunriseStep(kind: $0.kind, isEnabled: false, isRequired: $0.isRequired)
        })
        working(model)
        model.evaluateReflectionGates(previousPhase: .locked)
        #expect(!model.reflectionState.isDaybreakPresented)
    }

    // MARK: - Pages and release

    @Test("A required step holds until it has an answer; any text will do")
    func requiredStepHolds() throws {
        let model = try makeModel()
        try #require(model.reflectionState.isDaybreakPresented)
        #expect(!model.canAdvanceSunrise)
        model.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] = .text("  ")
        #expect(!model.canAdvanceSunrise)
        model.advanceSunrise()
        #expect(model.sunriseRuntime.pageIndex == 0)
        model.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] = .text("x")
        #expect(model.canAdvanceSunrise)
        #expect(!model.canSkipSunrisePage)
    }

    @Test("Answering saves the one thing for Today and the Journal and releases the Mac")
    func answeringSavesAndReleases() throws {
        let reflections = MemoryReflections()
        let model = try makeModel(reflections: reflections)
        try #require(model.reflectionState.isDaybreakPresented)
        model.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] =
            .text(" Ship the billing migration ")
        model.advanceSunrise()
        #expect(model.reflectionState.isDaybreakPresented)
        #expect(model.sunriseRuntime.pageIndex == 1)
        #expect(model.canSkipSunrisePage)
        model.skipSunrisePage()

        #expect(!model.reflectionState.isDaybreakPresented)
        let saved = try #require(reflections.entries.last)
        #expect(saved.gate == .morning)
        #expect(saved.answers.map(\.promptID) == [JournalPromptIDs.oneThing])
        #expect(saved.answers.first?.promptTextSnapshot == "What is today for?")
        #expect(model.sunriseOneThingToday == "Ship the billing migration")
        #expect(model.isSunriseCompleteToday)
        let record = model.journalDayRecords(in: Self.localDate(19, 0) ... Self.localDate(19, 23))
        #expect(record.first?.oneThing == "Ship the billing migration")
    }

    @Test("A gate whose pages are missing still lets the person start the day")
    func emptyPagesRelease() throws {
        let model = try makeModel()
        model.sunriseRuntime.pages = []
        #expect(model.canAdvanceSunrise)
        model.advanceSunrise()
        #expect(!model.reflectionState.isDaybreakPresented)
    }

    @Test("Unlocking with no gate to show releases the Sunrise display hold")
    func unlockWithoutGateReleasesHold() async throws {
        let model = try makeModel(now: Self.localDate(19, 12))
        model.reflectionState.isDaybreakPresented = false
        model.reflectionState.gatesResolvedToday.insert(.morning)
        model.restAppearance = RestAppearancePreferences(sunriseWakeEnabled: true)
        model.sunriseCalendar = .current
        let effects = SunriseGateEffects()
        model.sunriseWakeCoordinator = effects.coordinator
        model.sunriseOnExternalPower = { true }
        let plan =
            try #require(SunriseWakePlanner(owner: CurfewFlavor.current.daemonLabel + ".sunrise")
                    .presentationPlan(
                        schedule: model.settings.schedule, appearance: model.restAppearance,
                        at: model.currentTime, calendar: .current
                    ))
        model.currentTime = plan.wakeAt
        await model.reconcileSunriseWake()
        try #require(effects.delivery.isActive)

        model.currentTime = plan.holdUntil.addingTimeInterval(-300)
        model.reflectionState.gatesResolvedToday.removeAll()
        model.reflectionState.gatesResolvedToday.insert(.morning)
        working(model)
        model.evaluateReflectionGates(previousPhase: .locked)
        #expect(!model.reflectionState.isDaybreakPresented)
        #expect(!effects.delivery.isActive)
    }

    @Test("Curfew off plans no wake, so the Mac never wakes to an empty desktop")
    func curfewOffPlansNoWake() async throws {
        let model = try makeModel(now: Self.localDate(19, 12))
        model.restAppearance = RestAppearancePreferences(sunriseWakeEnabled: true)
        let effects = SunriseGateEffects()
        model.sunriseWakeCoordinator = effects.coordinator
        model.sunriseOnExternalPower = { true }
        model.automaticScheduleEnabled = false
        await model.reconcileSunriseWake()
        #expect(effects.plans.isEmpty)
        #expect(model.sunriseWakePlan == nil)
        model.automaticScheduleEnabled = true
        await model.reconcileSunriseWake()
        #expect(effects.plans.count == 1)
        #expect(model.sunriseWakePlan == effects.plans.first)
    }

    // MARK: - Steps editing

    @Test("A question added in Sunrise settings becomes a prompt and a skippable step")
    func addQuestion() throws {
        let model = try makeModel()
        model.addSunriseQuestion("Who do I owe a reply?")
        let prompt = try #require(model.reflectionConfiguration.morningPrompts.last)
        #expect(prompt.text == "Who do I owe a reply?")
        #expect(model.sunriseSteps.last == SunriseStep(
            kind: .question(prompt.id), isEnabled: true, isRequired: false
        ))
        model.removeSunriseQuestion(prompt.id)
        #expect(!model.reflectionConfiguration.morningPrompts.contains { $0.id == prompt.id })
        #expect(!model.sunriseSteps.contains { $0.kind == .question(prompt.id) })
    }

    @Test("Edited steps persist on this Mac")
    func stepsPersist() throws {
        let model = try makeModel()
        var steps = model.sunriseSteps
        steps.swapAt(0, 1)
        model.updateSunriseSteps(steps)
        let reloaded = SunrisePreferencesStore(defaults: model.settingsStore.storageDefaults).load()
        #expect(reloaded.steps == steps)
    }

    // MARK: - Shortcut

    @Test("After the gate the picked Shortcut runs with the one thing, without holding release")
    func shortcutRunsAfterRelease() async throws {
        let model = try makeModel()
        let launcher = RecordingShortcutLauncher(status: 0)
        model.sunriseRuntime.shortcutRunner = SunriseShortcutRunner(launcher: launcher)
        model.setSunriseShortcut(SunriseShortcut(identifier: "ID-1", name: "Plan my day"))
        model.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] = .text("Ship it")
        model.advanceSunrise()
        model.skipSunrisePage()
        #expect(!model.reflectionState.isDaybreakPresented)
        await model.sunriseRuntime.shortcutTask?.value
        let call = try #require(await launcher.calls.first)
        #expect(call.arguments.prefix(2) == ["run", "ID-1"])
        #expect(call.input == "Ship it")
        #expect(model.sunriseShortcutNotice == nil)
    }

    @Test("A Shortcut that fails is mentioned quietly, once, on Today")
    func shortcutFailureIsQuiet() async throws {
        let model = try makeModel()
        model.sunriseRuntime.shortcutRunner = SunriseShortcutRunner(
            launcher: RecordingShortcutLauncher(status: 1)
        )
        model.setSunriseShortcut(SunriseShortcut(identifier: "ID-1", name: "Plan my day"))
        model.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] = .text("Ship it")
        model.advanceSunrise()
        model.skipSunrisePage()
        await model.sunriseRuntime.shortcutTask?.value
        #expect(model.sunriseShortcutNotice == "Plan my day didn't run after Sunrise.")
        model.dismissSunriseShortcutNotice()
        #expect(model.sunriseShortcutNotice == nil)
    }

    @Test("Without a picked Shortcut nothing runs")
    func noShortcutNoRun() async throws {
        let model = try makeModel()
        let launcher = RecordingShortcutLauncher(status: 0)
        model.sunriseRuntime.shortcutRunner = SunriseShortcutRunner(launcher: launcher)
        model.reflectionState.morningDraft.values[JournalPromptIDs.oneThing] = .text("Ship it")
        model.advanceSunrise()
        model.skipSunrisePage()
        await model.sunriseRuntime.shortcutTask?.value
        #expect(await launcher.calls.isEmpty)
    }
}

/// In-memory reflections for model tests.
@MainActor
final class MemoryReflections: ReflectionRecording {
    private(set) var entries: [Reflection] = []
    private(set) var mutationCount = 0

    func record(_ reflection: Reflection) {
        entries.append(reflection)
        mutationCount += 1
    }

    func reflections(in range: ClosedRange<Date>) -> [Reflection] {
        entries.filter { range.contains($0.timestamp) }.sorted { $0.timestamp < $1.timestamp }
    }

    func trim(olderThan _: TimeInterval, now _: Date) {}
}

/// A Shortcut launcher that records each call and the text input it was given.
actor RecordingShortcutLauncher: SunriseShortcutLaunching {
    struct Call: Equatable {
        let arguments: [String]
        let input: String?
    }

    private let status: Int32
    private let output: String
    private(set) var calls: [Call] = []

    init(status: Int32, output: String = "") {
        self.status = status
        self.output = output
    }

    func run(arguments: [String]) async -> SunriseShortcutLaunchResult {
        var input: String?
        if let flag = arguments.firstIndex(of: "--input-path"), flag + 1 < arguments.count {
            input = try? String(contentsOfFile: arguments[flag + 1], encoding: .utf8)
        }
        calls.append(Call(arguments: arguments, input: input))
        return SunriseShortcutLaunchResult(status: status, output: output)
    }
}

/// Injected wake coordinator effects; never native power or XPC.
@MainActor
final class SunriseGateEffects {
    var plans: [SunriseWakePlan] = []
    lazy var delivery = SunriseDisplayDelivery(
        declareUserActivity: {},
        acquireDisplayAssertion: { _ in .init(rawValue: 1) },
        releaseDisplayAssertion: { _ in }
    )
    lazy var coordinator = SunriseWakeCoordinator(
        operations: .init(
            replace: { self.plans.append($0) },
            cancel: {}
        ),
        displayDelivery: delivery,
        cleanupNativeAssertions: {}
    )
}
