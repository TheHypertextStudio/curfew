import CurfewAtmosphere
import CurfewKit
import Foundation

/// Absolute schedule context survives midnight, overrides, and the engine's
/// switch to the next working-day evaluation. It never grants release.
struct RestSessionContext: Equatable {
    let lockDate: Date?
    let unlockDate: Date?
}

enum RestContentState: Equatable {
    case quiet, evening, morning
}

struct RestPresentationSnapshot: Equatable {
    let isRestricted: Bool
    let isMorning: Bool
    let layout: RestContentState
    let sky: SkyMoment

    static func resolve(
        now: Date, session: RestSessionContext, isRestricted: Bool, content: RestContentState
    ) -> RestPresentationSnapshot {
        RestPresentationSnapshot(
            isRestricted: isRestricted,
            isMorning: session.unlockDate.map { now >= $0 } ?? false,
            layout: content,
            sky: SkyMoment.resolve(
                now: now, lockDate: session.lockDate,
                unlockDate: session.unlockDate, phase: isRestricted ? .locked : .working
            )
        )
    }
}

/// One authored default, kept separate from authority and lifecycle so future
/// appearance settings need not reimplement scheduling or input policy.
struct RestAppearance {
    static let standard = RestAppearance()

    struct Motion {
        let translation: Double
        let contentDuration: Double
        let layoutDuration: Double
        let revealDuration: Double
    }

    struct Transition {
        let motion: Motion
        let layoutDelay: Double
        let contentDelay: Double
    }

    func transition(
        from: RestContentState, to destination: RestContentState, reduceMotion: Bool
    ) -> Transition {
        let timing = motion(reduceMotion: reduceMotion)
        let departing = from != .quiet && from != destination
        let layoutDelay = departing && !reduceMotion ? timing.contentDuration : 0
        let contentDelay = destination != .quiet && from != destination && !reduceMotion
            ? layoutDelay + timing.layoutDuration : 0
        return Transition(motion: timing, layoutDelay: layoutDelay, contentDelay: contentDelay)
    }

    func motion(reduceMotion: Bool) -> Motion {
        Motion(
            translation: reduceMotion ? 0 : 8,
            contentDuration: reduceMotion ? 0.15 : 0.35,
            layoutDuration: reduceMotion ? 0 : 0.65,
            revealDuration: reduceMotion ? 0.15 : 1.2
        )
    }
}

/// Visual morning and an elapsed scheduled boundary cannot grant release.
enum RestRestrictionStatus: Equatable {
    case lockedUntil(Date)
    case stillLocked
    case unknown
    case released

    static func resolve(now: Date, unlockDate: Date?, isRestricted: Bool) -> RestRestrictionStatus {
        guard isRestricted else { return .released }
        guard let unlockDate else { return .unknown }
        return unlockDate > now ? .lockedUntil(unlockDate) : .stillLocked
    }
}
