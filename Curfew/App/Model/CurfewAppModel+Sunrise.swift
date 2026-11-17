import CurfewKit
import Foundation
import Observation

/// Observable Sunrise state with explicitly injected effects; no live power
/// factory. Holds the wake status and plan, the person's local Sunrise
/// preferences, the open gate's pages and the Shortcut that runs afterwards.
@Observable
@MainActor
final class SunriseModelRuntime {
    @ObservationIgnored var coordinator: SunriseWakeCoordinator?
    @ObservationIgnored var onExternalPower: () -> Bool = { false }
    @ObservationIgnored var calendar: Calendar = .current
    @ObservationIgnored var helperRevision: UInt64?
    var status: SunriseWakeCoordinator.Status = .disabled
    /// The wake the last reconcile resolved, for the settings status line.
    var plan: SunriseWakePlan?
    /// Whether this Mac has a lid and a battery. Read once; tests set it.
    var hardware = SunriseHardware.resolve(IOKitSunriseHardwareProvider())
    /// The step open for editing in Sunrise settings.
    var editingStep: SunriseStepKind?

    var preferences = SunrisePreferences()

    /// The open gate, fixed when it opened so edits elsewhere cannot move it.
    var pages: [SunriseGatePage] = []
    var pageIndex = 0
    @ObservationIgnored var skippedPromptIDs: Set<UUID> = []

    @ObservationIgnored var shortcutRunner: SunriseShortcutRunner = .live
    @ObservationIgnored var shortcutTask: Task<Void, Never>?
    /// Said once, quietly, on Today when the picked Shortcut did not run.
    var shortcutNotice: String?

    @ObservationIgnored var todayCache: SunriseTodayCache?
}

/// Today's reflections, read once per day and write.
struct SunriseTodayCache {
    let day: Date
    let mutations: Int
    let reflections: [Reflection]
}

@MainActor
extension CurfewAppModel {
    var sunriseRuntime: SunriseModelRuntime {
        restRuntime.sunrise
    }

    var sunriseWakeCoordinator: SunriseWakeCoordinator? {
        get { sunriseRuntime.coordinator }
        set { sunriseRuntime.coordinator = newValue }
    }

    var sunriseOnExternalPower: () -> Bool {
        get { sunriseRuntime.onExternalPower }
        set { sunriseRuntime.onExternalPower = newValue }
    }

    var sunriseCalendar: Calendar {
        get { sunriseRuntime.calendar }
        set { sunriseRuntime.calendar = newValue }
    }

    var sunriseStatus: SunriseWakeCoordinator.Status {
        get { sunriseRuntime.status }
        set { sunriseRuntime.status = newValue }
    }

    var sunriseWakePlan: SunriseWakePlan? {
        sunriseRuntime.plan
    }

    /// Sunrise wakes this Mac only while Curfew is on: setup is done and the
    /// automatic schedule is enabled. Otherwise nothing waits at unlock.
    var isCurfewOnForSunrise: Bool {
        automaticScheduleEnabled && settings.hasCompletedInitialSetup
    }

    func dismissSunrisePresentation() {
        guard let coordinator = sunriseWakeCoordinator else { return }
        do {
            try coordinator.dismissCurrentOccurrence(at: currentTime)
            sunriseStatus = coordinator.status
        } catch {
            sunriseStatus = .requestRejected
            NSLog("Curfew Sunrise dismissal cleanup failed: %@", error.localizedDescription)
        }
    }

    /// Uses the configured local schedule, never restriction authority. Test/demo
    /// models have no live runtime unless a test explicitly supplies fake effects.
    /// No wake is planned while Curfew is off, and the planner passes over a
    /// night that unlocks into a day off.
    func reconcileSunriseWake() async {
        guard !isDemoSession, let coordinator = sunriseWakeCoordinator else {
            sunriseStatus = .disabled
            return
        }
        let helperRevision = privilegedHelperManager.sunriseOwnershipRevision
        if let previous = sunriseRuntime.helperRevision, previous != helperRevision {
            coordinator.invalidateHelperAcceptance()
        }
        sunriseRuntime.helperRevision = helperRevision
        let preferences = restAppearance
        let plan = SunriseWakePlanner(owner: CurfewFlavor.current.daemonLabel + ".sunrise")
            .presentationPlan(
                schedule: isCurfewOnForSunrise ? settings.schedule : .allDaysOff,
                appearance: preferences, at: currentTime, calendar: sunriseCalendar
            )
        if sunriseRuntime.plan != plan {
            sunriseRuntime.plan = plan
        }
        await coordinator.reconcile(
            plan: plan, enabled: preferences.sunriseWakeEnabled,
            batteryOptIn: preferences.sunriseOnBatteryEnabled,
            // A Mac without a battery is always on power.
            onExternalPower: !sunriseRuntime.hardware.hasBattery || sunriseOnExternalPower(),
            now: currentTime
        )
        guard sunriseWakeCoordinator === coordinator, !isDemoSession else { return }
        if sunriseStatus != coordinator.status {
            sunriseStatus = coordinator.status
        }
    }

    /// Writes the three wake choices, which live with this Mac's rest
    /// appearance, leaving every other appearance choice as it is.
    func updateSunriseWake(enabled: Bool? = nil, leadMinutes: Int? = nil, onBattery: Bool? = nil) {
        var draft = RestAppearanceDraft(restAppearance)
        draft.sunriseWakeEnabled = enabled ?? draft.sunriseWakeEnabled
        draft.sunriseLeadMinutes = leadMinutes ?? draft.sunriseLeadMinutes
        draft.sunriseOnBatteryEnabled = onBattery ?? draft.sunriseOnBatteryEnabled
        restAppearance = draft.preferences
    }
}

// MARK: - Steps and preferences

@MainActor
extension CurfewAppModel {
    private var sunrisePreferencesStore: SunrisePreferencesStore {
        SunrisePreferencesStore(defaults: settingsStore.storageDefaults)
    }

    /// Called once at startup, before the first gate evaluation.
    func loadSunrisePreferences() {
        sunriseRuntime.preferences = sunrisePreferencesStore.load()
    }

    var sunrisePreferences: SunrisePreferences {
        sunriseRuntime.preferences
    }

    /// The ordered steps, migrated from the morning prompts until first edited.
    var sunriseSteps: [SunriseStep] {
        SunriseSteps.resolve(
            stored: sunrisePreferences.steps,
            morningPrompts: reflectionConfiguration.morningPrompts
        )
    }

    /// Whether Sunrise appears at unlock at all.
    var isSunriseEnabled: Bool {
        reflectionConfiguration.morningEnabled
    }

    func setSunriseEnabled(_ enabled: Bool) {
        var configuration = reflectionConfiguration
        configuration.morningEnabled = enabled
        updateReflectionConfiguration(configuration)
    }

    func updateSunriseSteps(_ steps: [SunriseStep]) {
        sunriseRuntime.preferences.steps = SunriseSteps.resolve(
            stored: steps, morningPrompts: reflectionConfiguration.morningPrompts
        )
        sunrisePreferencesStore.save(sunriseRuntime.preferences)
    }

    func setSunriseShortcut(_ shortcut: SunriseShortcut?) {
        sunriseRuntime.preferences.shortcut = shortcut
        sunrisePreferencesStore.save(sunriseRuntime.preferences)
    }

    /// Adds one of the person's own questions: a morning prompt (so answers
    /// keep their identity in the Journal) and a skippable step at the end.
    @discardableResult
    func addSunriseQuestion(_ text: String) -> UUID {
        var configuration = reflectionConfiguration
        let prompt = ReflectionPrompt(text: text, kind: .text)
        configuration.morningPrompts.append(prompt)
        updateReflectionConfiguration(configuration)
        updateSunriseSteps(sunriseSteps)
        return prompt.id
    }

    func renameSunriseQuestion(_ id: UUID, to text: String) {
        var configuration = reflectionConfiguration
        guard let index = configuration.morningPrompts.firstIndex(where: { $0.id == id })
        else { return }
        configuration.morningPrompts[index].text = text
        updateReflectionConfiguration(configuration)
    }

    func removeSunriseQuestion(_ id: UUID) {
        if sunriseRuntime.editingStep == .question(id) {
            sunriseRuntime.editingStep = nil
        }
        var configuration = reflectionConfiguration
        configuration.morningPrompts.removeAll { $0.id == id }
        updateReflectionConfiguration(configuration)
        updateSunriseSteps(sunriseSteps)
    }
}

// MARK: - The gate

@MainActor
extension CurfewAppModel {
    /// Last night's "left for next time" answer, if one is recent enough.
    var sunriseLastNightNote: String? {
        let from = currentTime.addingTimeInterval(-SunriseNote.maximumAge)
        guard from <= currentTime else { return nil }
        return SunriseNote.lastNight(
            in: reflectionState.recorder.reflections(in: from ... currentTime), now: currentTime
        )
    }

    /// The pages the gate would show right now.
    func currentSunrisePages() -> [SunriseGatePage] {
        SunriseGate.pages(
            steps: sunriseSteps, morningPrompts: reflectionConfiguration.morningPrompts,
            lastNightNote: sunriseLastNightNote, question: voice.gateQuestion
        )
    }

    /// Fixes the pages and a fresh draft for a gate about to open.
    func prepareSunriseGate(pages: [SunriseGatePage]) {
        sunriseRuntime.pages = pages
        sunriseRuntime.pageIndex = 0
        sunriseRuntime.skippedPromptIDs = []
        reflectionState.morningDraft = ReflectionDraft(prompts: pages.compactMap(\.prompt))
    }

    var currentSunrisePage: SunriseGatePage? {
        let pages = sunriseRuntime.pages
        return pages.indices.contains(sunriseRuntime.pageIndex)
            ? pages[sunriseRuntime.pageIndex] : nil
    }

    var isLastSunrisePage: Bool {
        sunriseRuntime.pageIndex >= sunriseRuntime.pages.count - 1
    }

    /// A page that cannot be read never traps the person: with no page, the
    /// gate can always be finished.
    var canAdvanceSunrise: Bool {
        guard let page = currentSunrisePage else { return true }
        return page
            .canAdvance(with: page.prompt.flatMap { reflectionState.morningDraft.values[$0.id] })
    }

    var canSkipSunrisePage: Bool {
        guard let page = currentSunrisePage, page.prompt != nil else { return false }
        return !page.isRequired
    }

    /// Return and the primary button: the next page, or start the day.
    func advanceSunrise() {
        guard reflectionState.isDaybreakPresented, canAdvanceSunrise else { return }
        nextSunrisePage()
    }

    func skipSunrisePage() {
        guard reflectionState.isDaybreakPresented, canSkipSunrisePage,
              let id = currentSunrisePage?.prompt?.id else { return }
        sunriseRuntime.skippedPromptIDs.insert(id)
        nextSunrisePage()
    }

    private func nextSunrisePage() {
        if sunriseRuntime.pageIndex + 1 < sunriseRuntime.pages.count {
            sunriseRuntime.pageIndex += 1
        } else {
            completeSunrise()
        }
    }

    /// Saves the answers through the morning reflection path (so Today and
    /// the Journal read the one thing), releases the Mac, then starts the
    /// picked Shortcut without waiting for it.
    private func completeSunrise() {
        let values = reflectionState.morningDraft.values
        let answers = sunriseRuntime.pages.compactMap { page -> ReflectionAnswer? in
            guard let prompt = page.prompt,
                  !sunriseRuntime.skippedPromptIDs.contains(prompt.id),
                  let value = values[prompt.id].map(Self.trimmed), Self.isMeaningful(value)
            else { return nil }
            return ReflectionAnswer(
                promptID: prompt.id,
                promptTextSnapshot: prompt.text,
                value: value
            )
        }
        saveReflection(gate: .morning, answers: answers)
        let oneThing = answers.first { $0.promptID == JournalPromptIDs.oneThing }
            .flatMap { answer -> String? in
                if case .text(let text) = answer.value {
                    return text
                }
                return nil
            }
        runSunriseShortcut(oneThing: oneThing ?? "")
    }

    private static func trimmed(_ value: ReflectionValue) -> ReflectionValue {
        if case .text(let text) = value {
            return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return value
    }

    private static func isMeaningful(_ value: ReflectionValue) -> Bool {
        switch value {
        case .text(let text): !text.isEmpty
        case .rating(let rating, _): rating >= 1
        case .mood: true
        }
    }

    private func runSunriseShortcut(oneThing: String) {
        guard !isDemoSession, let shortcut = sunrisePreferences.shortcut else { return }
        let runner = sunriseRuntime.shortcutRunner
        sunriseRuntime.shortcutTask = Task { [weak self] in
            let ran = await runner.run(shortcut, input: oneThing)
            guard !ran, let self else { return }
            sunriseRuntime.shortcutNotice = "\(shortcut.name) didn't run after Sunrise."
        }
    }

    var sunriseShortcutNotice: String? {
        sunriseRuntime.shortcutNotice
    }

    func dismissSunriseShortcutNotice() {
        sunriseRuntime.shortcutNotice = nil
    }
}

// MARK: - Today's Sunrise

@MainActor
extension CurfewAppModel {
    private var todaysReflections: [Reflection] {
        let day = Calendar.current.startOfDay(for: currentTime)
        let recorder = reflectionState.recorder
        if let cache = sunriseRuntime.todayCache, cache.day == day,
           cache.mutations == recorder.mutationCount {
            return cache.reflections
        }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? currentTime
        let reflections = recorder.reflections(in: day ... end)
        sunriseRuntime.todayCache = SunriseTodayCache(
            day: day, mutations: recorder.mutationCount, reflections: reflections
        )
        return reflections
    }

    /// Today's one thing, as answered at Sunrise. Today and intents read it.
    var sunriseOneThingToday: String? {
        SunriseDay.oneThing(in: todaysReflections, now: currentTime, calendar: .current)
    }

    var isSunriseCompleteToday: Bool {
        SunriseDay.isComplete(in: todaysReflections, now: currentTime, calendar: .current)
    }
}
