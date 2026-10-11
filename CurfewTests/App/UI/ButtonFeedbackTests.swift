import CoreFoundation
@testable import Curfew
@testable import CurfewKit
import Testing

struct ButtonFeedbackTests {
    @Test("Disabled actions are visually subdued and never react as pressed")
    func disabledFeedback() {
        let disabled = CurfewButtonFeedback.resolve(
            isEnabled: false, isPressed: true, reduceMotion: false
        )
        #expect(disabled.opacity < 0.6)
        #expect(disabled.scale == 1)
        #expect(!disabled.animates)
    }

    @Test("Reduce Motion suppresses button scaling and animation")
    func reducedMotionFeedback() {
        let feedback = CurfewButtonFeedback.resolve(
            isEnabled: true, isPressed: true, reduceMotion: true
        )
        #expect(feedback.scale == 1)
        #expect(!feedback.animates)
        #expect(feedback.opacity == 0.9)
    }

    @Test("Enabled buttons retain their normal press feedback")
    func enabledFeedback() {
        let feedback = CurfewButtonFeedback.resolve(
            isEnabled: true, isPressed: true, reduceMotion: false
        )
        #expect(feedback.scale == 0.97)
        #expect(feedback.animates)
        #expect(CurfewButtonFeedback.resolve(
            isEnabled: true, isPressed: false, reduceMotion: false
        ).opacity == 1)
    }
}
