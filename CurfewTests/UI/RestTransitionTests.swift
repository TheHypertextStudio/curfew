@testable import Curfew
import CurfewAtmosphere
import Foundation
import Testing

struct RestTransitionTests {
    @Test("The scene can reach morning while actual restrictions remain active")
    func morningCanRemainRestricted() {
        let unlock = Date(timeIntervalSince1970: 1_700_000_000)
        let session = RestSessionContext(
            lockDate: unlock.addingTimeInterval(-9 * 3600),
            unlockDate: unlock
        )
        let scene = RestPresentationSnapshot.resolve(
            now: unlock,
            session: session,
            isRestricted: true,
            content: .quiet
        )
        #expect(scene.isRestricted)
        #expect(scene.isMorning)
        #expect(scene.sky.light >= 0.4)
    }

    @Test("Ordinary clock ticks do not choose a new layout")
    func ordinaryTickDoesNotTriggerLayoutTransition() {
        let unlock = Date(timeIntervalSince1970: 1_700_000_000)
        let session = RestSessionContext(
            lockDate: unlock.addingTimeInterval(-9 * 3600),
            unlockDate: unlock
        )
        let first = RestPresentationSnapshot.resolve(
            now: unlock.addingTimeInterval(-3600),
            session: session,
            isRestricted: true,
            content: .quiet
        )
        let second = RestPresentationSnapshot.resolve(
            now: unlock.addingTimeInterval(-3599),
            session: session,
            isRestricted: true,
            content: .quiet
        )
        #expect(first.layout == second.layout)
        let editing = RestPresentationSnapshot.resolve(
            now: unlock.addingTimeInterval(-3599),
            session: session,
            isRestricted: true,
            content: .evening
        )
        #expect(editing.layout != first.layout)
    }

    @Test("Reduce Motion removes positional animation without hiding content")
    func reducedMotionRemovesTranslation() {
        let motion = RestAppearance.standard.motion(reduceMotion: true)
        #expect(motion.translation == 0)
        #expect(motion.layoutDuration == 0)
        #expect(motion.contentDuration <= 0.15)
    }

    @Test("The clock waits for departing content before moving into its space")
    func departingContentClearsBeforeClockMoves() {
        let transition = RestAppearance.standard.transition(
            from: .evening, to: .quiet, reduceMotion: false
        )
        #expect(transition.layoutDelay >= transition.motion.contentDuration)
        #expect(transition.contentDelay == 0)
    }

    @Test("New contextual content waits for the clock to make room")
    func enteringContentWaitsForLayout() {
        let transition = RestAppearance.standard.transition(
            from: .quiet, to: .evening, reduceMotion: false
        )
        #expect(transition.contentDelay >= transition.motion.layoutDuration)
        #expect(transition.layoutDelay == 0)
    }

    @Test("Morning atmosphere cannot promise release while another restriction is active")
    func expiredScheduleStillReportsLocked() {
        let unlock = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(RestRestrictionStatus.resolve(
            now: unlock.addingTimeInterval(60),
            unlockDate: unlock,
            isRestricted: true
        ) ==
            .stillLocked)
        #expect(RestRestrictionStatus.resolve(
            now: unlock.addingTimeInterval(60),
            unlockDate: unlock,
            isRestricted: false
        ) == .released)
    }
}
