import CurfewAtmosphere
import CurfewKit
import Foundation

/// The live `SkyMoment` for the current tick — the single atmosphere source
/// every surface (Today, lockout, sunrise, menu bar) reads, so they all shift
/// together with the time of day and the curfew window. Recomputed each tick
/// from the published `currentTime` and the cached evaluation.
extension CurfewAppModel {
    /// Capture schedule evaluation before durable/account authority can replace
    /// its dates. A held restriction cannot move the visual morning anchor.
    func retainScheduledRestInterval(from evaluation: CurfewEvaluation) {
        guard evaluation.phase == .locked,
              let start = evaluation.lockDate, let end = evaluation.unlockDate,
              end > start, end != .distantFuture else { return }
        reflectionState.scheduledInterval = DateInterval(start: start, end: end)
    }

    var isTemporaryRestRelease: Bool {
        (accountReleaseOverrideUntil() ?? overrideUntil).map { $0 > currentTime } ?? false
    }

    var isContinuingEveningReflection: Bool {
        reflectionState.isEveningReflectionPending
            && !reflectionState.eveningDraft.values.isEmpty
            && (state.phase == .working || state.phase == .dayOff)
            && !isTemporaryRestRelease
    }

    var restRestrictionStatus: RestRestrictionStatus {
        let end = reflectionState.scheduledInterval?.end ?? state.unlockDate
        return RestRestrictionStatus.resolve(
            now: currentTime, unlockDate: end == .distantFuture ? nil : end,
            isRestricted: isEnforcingLockout
        )
    }

    var shouldPresentRestScreen: Bool {
        isEnforcingLockout || reflectionState.isDaybreakPresented || isContinuingEveningReflection
    }

    /// The sky as it should look right now.
    var skyMoment: SkyMoment {
        let interval = reflectionState.scheduledInterval
        let retainNight = interval.map {
            currentTime >= $0.start && currentTime <= $0.end.addingTimeInterval(15 * 60)
        } ?? false
        return SkyMoment.resolve(
            now: currentTime,
            lockDate: retainNight ? interval?.start : state.lockDate,
            unlockDate: retainNight ? interval?.end : state.unlockDate,
            phase: state.phase
        )
    }

    var restPresentation: RestPresentationSnapshot {
        let content: RestContentState = if reflectionState.isEveningReflectionPending,
                                           isEnforcingLockout || !reflectionState.eveningDraft
                                               .values.isEmpty {
            .evening
        } else {
            reflectionState.isDaybreakPresented ? .morning : .quiet
        }
        let interval = reflectionState.scheduledInterval
        return RestPresentationSnapshot.resolve(
            now: currentTime,
            session: RestSessionContext(
                lockDate: interval?.start ?? state.lockDate,
                unlockDate: interval?.end ?? state.unlockDate
            ),
            isRestricted: isEnforcingLockout, content: content
        )
    }
}
