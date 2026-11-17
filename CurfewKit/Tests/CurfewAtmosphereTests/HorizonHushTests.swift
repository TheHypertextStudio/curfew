@testable import CurfewAtmosphere
import Foundation
import Testing

struct HorizonHushTests {
    private let frame = HorizonFrame(
        sun: HorizonPoint(x: 0.3, y: 0.7), sunWeight: 1, moon: HorizonPoint(x: 0.5, y: -1),
        moonWeight: 0, elevation: 0.65, moonPhase: 0
    )

    @Test("No hush leaves the field exactly as the model draws it")
    func noneIsIdentity() {
        for x in stride(from: 0.0, through: 1, by: 0.1) {
            for y in stride(from: 0.3, through: 1, by: 0.1) {
                let point = HorizonPoint(x: x, y: y)
                #expect(HorizonField.brightness(at: point, aspect: 1.6, frame: frame)
                    == HorizonField.brightness(at: point, aspect: 1.6, frame: frame, hush: .none))
            }
        }
        #expect(HorizonHush.none.isNone)
    }

    @Test("The tone remap is monotonic, keeps 0 and 1, and lowers the knee")
    func toneIsMonotonic() {
        let hush = HorizonHush(
            centre: HorizonPoint(x: 0.5, y: 0.5), radiusX: 0.6, radiusY: 0.4, glow: 0,
            scale: 0.4, knee: 0.8
        )
        var previous = -1.0
        for level in stride(from: 0.0, through: 1, by: 0.01) {
            let toned = hush.toned(level)
            #expect(toned >= previous)
            previous = toned
        }
        #expect(hush.toned(0) == 0)
        #expect(abs(hush.toned(1) - 1) < 1e-9)
        #expect(abs(hush.toned(0.8) - 0.32) < 1e-9)
    }

    @Test("The glow is taken out fully from the centre down to the horizon and fades above")
    func domeRestsOnTheHorizon() {
        let hush = HorizonHush(
            centre: HorizonPoint(x: 0.5, y: 0.5), radiusX: 0.6, radiusY: 0.3, glow: 1,
            scale: 1, knee: 1
        )
        #expect(hush.weight(at: HorizonPoint(x: 0.5, y: 0.3), aspect: 1.6) == 1)
        #expect(hush.weight(at: HorizonPoint(x: 0.5, y: 0.8), aspect: 1.6) < 0.5)
        #expect(hush.weight(at: HorizonPoint(x: 0.95, y: 0.4), aspect: 1.6) < 0.5)
        let below = HorizonField.brightness(
            at: HorizonPoint(x: 0.5, y: 0.3), aspect: 1.6, frame: frame
        )
        let quieted = HorizonField.brightness(
            at: HorizonPoint(x: 0.5, y: 0.3), aspect: 1.6, frame: frame, hush: hush
        )
        #expect(quieted < below)
    }
}
