import CurfewKit
import Foundation

/// The reflection-gate runtime held by `CurfewAppModel`, bundled into one value
/// so the model carries a single new stored property rather than several loose
/// ones (which the file-length budget will not absorb).
///
/// - `recorder` is the content store, injected so tests get the null object and
///   production gets the SQLite-backed ``ReflectionRecorder`` (set in the Setup
///   convenience init). Declared first so the memberwise init can take it alone.
/// - `configuration` is the user-editable prompts + per-gate toggles (loaded
///   from the settings store on init, persisted on edit).
/// - `isEveningReflectionPending` drives the evening card inside
///   ``LockoutScreenView`` — true from `→ locked` until the user saves or skips.
/// - `isDaybreakPresented` drives the full-screen morning overlay — true from
///   the day's first session until Start/Skip.
/// - `gatesResolvedToday` records which gates have been handled today so
///   neither re-prompts; reset on day rollover and seeded at init.
struct ReflectionRuntimeState {
    var recorder: any ReflectionRecording = NullReflectionRecording()
    var configuration: ReflectionConfiguration = .default
    var isEveningReflectionPending = false
    var isDaybreakPresented = false
    var gatesResolvedToday: Set<ReflectionGate> = []
}

/// Reflection-gate behaviour for `CurfewAppModel`: deciding when the morning
/// (sunrise) and evening (sundown) gates appear, persisting answers, and
/// keeping each gate to at most one prompt per day.
///
/// The gates are driven off the same phase transitions the tick loop already
/// computes (`→ working` for morning, `→ locked` for evening) rather than a
/// separate timer, so reflection state always agrees with enforcement state.
@MainActor
extension CurfewAppModel {
    /// Seeds ``ReflectionRuntimeState/gatesResolvedToday`` from the store at startup so a
    /// reflection already saved earlier today (before an app relaunch) does
    /// not re-prompt. Called from `completeInitialization`. One fetch covers
    /// both gates.
    func seedReflectionGatesResolvedToday() {
        let dayStart = Calendar.current.startOfDay(for: currentTime)
        for reflection in reflectionState.recorder.reflections(in: dayStart ... currentTime) {
            reflectionState.gatesResolvedToday.insert(reflection.gate)
        }
    }

    /// Read-only convenience over ``ReflectionRuntimeState/configuration`` so
    /// surfaces (settings panel, prompt lookups) can read the config without
    /// reaching through `reflectionState`. Writes go through
    /// ``updateReflectionConfiguration(_:)``.
    var reflectionConfiguration: ReflectionConfiguration {
        reflectionState.configuration
    }

    /// A Markdown journal of the reflections in the week containing `date`,
    /// ready to write to disk or share. Delegates to ``ReflectionExport``.
    func exportReflectionsMarkdown(inWeekOf date: Date) -> String {
        ReflectionExport.markdown(reflections(inWeekOf: date))
    }

    /// Structured JSON of the reflections in the week containing `date`.
    func exportReflectionsJSON(inWeekOf date: Date) -> String {
        ReflectionExport.json(reflections(inWeekOf: date))
    }

    /// All reflections recorded in the calendar week containing `date`
    /// (first-weekday-aligned, matching ``thisWeekRollup()``). Ordered
    /// ascending by timestamp. Feeds the Journal's reflections section.
    func reflections(inWeekOf date: Date) -> [Reflection] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysBack, to: startOfDay)
            ?? startOfDay
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return reflectionState.recorder.reflections(in: weekStart ... weekEnd)
    }

    /// Decides whether either gate should appear, given the phase we just
    /// transitioned from. Invoked from `propagatePhaseTransition` so it runs
    /// exactly on transitions, not every tick.
    ///
    /// - Morning fires when we cross into `.working` (the day's unlock / first
    ///   session), the morning gate is enabled, and it is unresolved today.
    /// - Evening fires when we cross into `.locked` (sundown), the evening gate
    ///   is enabled, and it is unresolved today.
    func evaluateReflectionGates(previousPhase: EnforcementPhase) {
        if reflectionConfiguration.morningEnabled,
           previousPhase != .working, state.phase == .working,
           !reflectionState.gatesResolvedToday.contains(.morning) {
            reflectionState.isDaybreakPresented = true
        }

        if reflectionConfiguration.eveningEnabled,
           previousPhase != .locked, state.phase == .locked,
           !reflectionState.gatesResolvedToday.contains(.evening) {
            reflectionState.isEveningReflectionPending = true
        }

        // Leaving the working window with the sunrise overlay still up (e.g.
        // the user never touched it before curfew) — dismiss it so it never
        // lingers into a warning or lockout screen, and mark it resolved so it
        // cannot resurrect later today. Without this, a "Convince Me" override
        // granted from lockout flips the phase back to `.working`, which the
        // check above reads as a fresh `→ working` transition and re-raises
        // the full-screen morning overlay hours into the night.
        if state.phase != .working, reflectionState.isDaybreakPresented {
            reflectionState.isDaybreakPresented = false
            reflectionState.gatesResolvedToday.insert(.morning)
        }
    }

    /// Persists a completed reflection for `gate`, writes the activity-log
    /// marker, marks the gate resolved for today, and dismisses its surface.
    /// `answers` come straight from the gate's input controls.
    func saveReflection(gate: ReflectionGate, answers: [ReflectionAnswer]) {
        let reflection = Reflection(
            timestamp: currentTime,
            gate: gate,
            answers: answers
        )
        reflectionState.recorder.record(reflection)
        activityRecorder.recordReflectionRecorded(gate: gate, at: currentTime)
        resolveReflectionGate(gate)
    }

    /// Dismisses `gate` without recording anything — the lenient "skip" path.
    /// The gate stays resolved for the rest of the day so it does not re-nag.
    func skipReflection(gate: ReflectionGate) {
        resolveReflectionGate(gate)
    }

    /// Marks `gate` handled for today and clears whichever surface presented
    /// it. Shared by the save and skip paths.
    private func resolveReflectionGate(_ gate: ReflectionGate) {
        reflectionState.gatesResolvedToday.insert(gate)
        switch gate {
        case .morning:
            reflectionState.isDaybreakPresented = false
        case .evening:
            reflectionState.isEveningReflectionPending = false
        }
    }

    /// Persists an edited reflection configuration and republishes it. Called
    /// by the reflection settings panel.
    func updateReflectionConfiguration(_ configuration: ReflectionConfiguration) {
        reflectionState.configuration = configuration
        settingsStore.saveReflectionConfiguration(configuration)
    }

    /// Day-rollover reset: clears the resolved set and dismisses any open
    /// surfaces so a new day starts fresh, and trims old reflections to the
    /// shared 52-week retention window. Called from `handleDayRollover`.
    func resetReflectionGatesForNewDay() {
        reflectionState.gatesResolvedToday.removeAll()
        reflectionState.isEveningReflectionPending = false
        reflectionState.isDaybreakPresented = false
        reflectionState.recorder.trim(
            olderThan: Self.activityRetentionSeconds,
            now: currentTime
        )
    }
}
