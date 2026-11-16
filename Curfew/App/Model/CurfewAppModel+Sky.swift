import CurfewAtmosphere
import CurfewKit
import Foundation

/// The live Horizon frame for the current tick — the single sky source every
/// surface (Today, the lock, Sunrise, the menu bar) reads, so they all move
/// together with the real schedule. Recomputed each tick from the published
/// `currentTime` and the cached evaluation.
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

    /// The sky's inputs right now: the working day, the effective curfew
    /// (with any extension, so more time moves the sun back up) and the next
    /// unlock. A surface with a sidebar passes its own span.
    func horizonMoment(span: HorizonSpan = .fullBleed) -> HorizonMoment {
        let interval = reflectionState.scheduledInterval
        let retainNight = interval.map {
            currentTime >= $0.start && currentTime <= $0.end.addingTimeInterval(15 * 60)
        } ?? false
        let lock = retainNight ? interval?.start : state.lockDate
        let unlock = retainNight ? interval?.end : state.unlockDate
        guard let lock, let unlock, unlock > lock, unlock != .distantFuture else {
            return .unscheduled(now: currentTime, span: span)
        }
        let moment = HorizonMoment.scheduled(
            now: currentTime, curfew: lock, nextUnlock: unlock, span: span
        )
        // Tomorrow's sun crosses a scheduled day, without tonight's extra time.
        let extra = TimeInterval(extensionMinutesGrantedToday + snoozeMinutesGrantedToday) * 60
        return HorizonMoment(
            now: currentTime, dayStart: moment.dayStart, curfew: lock, nextUnlock: unlock,
            nextDayLength: lock.timeIntervalSince(moment.dayStart) - extra, span: span
        )
    }

    /// The sky as it should look right now on a full-bleed surface.
    var horizonFrame: HorizonFrame {
        horizonMoment().frame
    }

    /// Whether the working day is running, which is when the bands drift.
    /// They hold still while locked, on a day off and while Curfew is off.
    var isHorizonDayRunning: Bool {
        (state.phase == .working || state.phase == .warning)
            && isEnforcementRunning && !isEnforcingLockout
    }

    var restPresentation: RestPresentationSnapshot {
        let hasDraft = !reflectionState.eveningDraft.values.isEmpty
        let content: RestContentState = if reflectionState.isEveningReflectionPending,
                                           isEnforcingLockout || hasDraft {
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
