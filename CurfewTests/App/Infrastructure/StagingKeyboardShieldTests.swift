@testable import Curfew
import CurfewKit
import Testing

struct StagingKeyboardShieldTests {
    struct Fixture {
        var testHost = false
        var demo = true
        var staging = false
        var optedIn = false
        var backgroundAcceptance = true
        var expected = false
    }

    @Test(
        "Only explicitly opted-in staging fixtures can install a real keyboard shield",
        arguments: [
            Fixture(demo: false, expected: true),
            Fixture(),
            Fixture(optedIn: true),
            Fixture(staging: true),
            Fixture(staging: true, optedIn: true, expected: true),
            Fixture(staging: true, optedIn: true, backgroundAcceptance: false),
            Fixture(testHost: true, demo: false, staging: true, optedIn: true),
            Fixture(testHost: true, staging: true, optedIn: true)
        ]
    )
    func fixturePermissionBoundary(_ fixture: Fixture) {
        #expect(RuntimeEnvironment.permitsKeyboardInterception(
            testHost: fixture.testHost, demo: fixture.demo,
            staging: fixture.staging, acceptanceOptIn: fixture.optedIn,
            backgroundAcceptance: fixture.backgroundAcceptance
        ) == fixture.expected)
    }
}
