@testable import CurfewKit
import XCTest

final class CopyDeckTests: XCTestCase {
    func testOverrideInstructionsMatchTheConfirmationPolicy() {
        XCTAssertEqual(
            CopyDeck.overrideFrictionRationale,
            "To request an override, wait 5 minutes, type a reason of at least 50 characters, "
                + "then hold the confirmation button for 3 seconds."
        )
    }

    func testWeeklySummaryNamesRecordedLockouts() {
        XCTAssertEqual(
            CopyDeck.weekSummary(daysHeld: 3, extensionsUsed: 2, overridesUsed: 1),
            "3/7 days with lockout, 2 extensions, 1 override this week."
        )
    }

    func testWeeklySummaryPluralizesZeroAndOne() {
        XCTAssertEqual(
            CopyDeck.weekSummary(daysHeld: 0, extensionsUsed: 1, overridesUsed: 0),
            "0/7 days with lockout, 1 extension, 0 overrides this week."
        )
    }
}
