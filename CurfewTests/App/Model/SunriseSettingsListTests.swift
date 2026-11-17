@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// The Sunrise settings list on the model: reorder, edit, delete, Must
/// answer, and a Mac without a battery never paused for battery.
extension SunriseGateTests {
    @Test("Moving, editing, deleting and Must answer behave as the settings list shows them")
    func settingsListLogic() throws {
        let model = try makeModel()
        let id = model.addSunriseQuestion("")
        #expect(model.sunriseStepTitle(.question(id)).isEmpty)
        model.renameSunriseQuestion(id, to: "Who do I owe a reply?")
        #expect(model.sunriseStepTitle(.question(id)) == "Who do I owe a reply?")
        model.moveSunriseStep(.question(id), by: -1)
        #expect(model.sunriseSteps.map(\.kind).suffix(2) == [.question(id), .readiness])
        model.moveSunriseStep(.lastNightNote, by: -1)
        #expect(model.sunriseSteps.first?.kind == .lastNightNote)
        model.moveSunriseSteps(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(model.sunriseSteps.map(\.kind).prefix(2) == [.oneThing, .lastNightNote])

        let oneThing = try #require(model.sunriseSteps.first { $0.kind == .oneThing })
        #expect(model.sunriseStepMustBeAnswered(oneThing))
        model.setSunriseStep(.oneThing, canBeSkipped: true)
        let skippable = try #require(model.sunriseSteps.first { $0.kind == .oneThing })
        #expect(!model.sunriseStepMustBeAnswered(skippable))
        model.setSunriseStep(.oneThing, canBeSkipped: false)
        model.setSunriseStep(.oneThing, shown: false)
        let hidden = try #require(model.sunriseSteps.first { $0.kind == .oneThing })
        #expect(!model.sunriseStepMustBeAnswered(hidden))
        model.setSunriseStep(.lastNightNote, canBeSkipped: false)
        let note = try #require(model.sunriseSteps.first { $0.kind == .lastNightNote })
        #expect(!model.sunriseStepMustBeAnswered(note))

        model.sunriseRuntime.editingStep = .question(id)
        model.removeSunriseQuestion(id)
        #expect(model.sunriseRuntime.editingStep == nil)
        #expect(!model.sunriseSteps.contains { $0.kind == .question(id) })
    }

    @Test("A Mac without a battery is never paused for battery")
    func desktopNeverBatteryPaused() async throws {
        let model = try makeModel(now: Self.localDate(19, 12))
        model.restAppearance = RestAppearancePreferences(sunriseWakeEnabled: true)
        let effects = SunriseGateEffects()
        model.sunriseWakeCoordinator = effects.coordinator
        model.sunriseOnExternalPower = { false }
        model.sunriseRuntime.hardware = .desktop
        await model.reconcileSunriseWake()
        #expect(model.sunriseStatus == .scheduled)
        model.sunriseRuntime.hardware = .laptop
        await model.reconcileSunriseWake()
        #expect(model.sunriseStatus == .batteryExcluded)
    }
}
