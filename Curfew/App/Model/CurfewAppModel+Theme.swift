import CurfewAtmosphere
import CurfewKit
import Foundation

/// The theme the person chose in Settings > Rest screen: a sky palette, a
/// clock style and a voice. Every surface reads these, so a change in the
/// editor shows everywhere at once.
@MainActor
extension CurfewAppModel {
    /// Everything Curfew says, in the chosen voice with the person's own
    /// words laid over it.
    var voice: VoicePack {
        restAppearance.voicePack
    }

    /// The sky every surface draws: Today, the lock, Sunrise and setup.
    var horizonPalette: HorizonPalette {
        HorizonPalette(restAppearance.palette)
    }

    /// Changes the theme through a draft, keeping every other choice.
    func updateTheme(_ change: (inout RestAppearanceDraft) -> Void) {
        var draft = RestAppearanceDraft(restAppearance)
        change(&draft)
        let updated = draft.preferences
        if updated != restAppearance {
            restAppearance = updated
        }
    }
}
