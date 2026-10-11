import CurfewKit
import Foundation

/// The live `SkyMoment` for the current tick — the single atmosphere source
/// every surface (Today, lockout, sunrise, menu bar) reads, so they all shift
/// together with the time of day and the curfew window. Recomputed each tick
/// from the published `currentTime` and the cached evaluation.
extension CurfewAppModel {
    /// The sky as it should look right now.
    var skyMoment: SkyMoment {
        SkyMoment.resolve(
            now: currentTime,
            lockDate: state.lockDate,
            unlockDate: state.unlockDate,
            phase: state.phase
        )
    }
}
