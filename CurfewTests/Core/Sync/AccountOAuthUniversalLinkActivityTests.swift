import AppKit
@testable import Curfew
import Foundation
import Testing

struct AccountOAuthUniversalLinkActivityTests {
    @Test("A callback on a different HTTPS port cannot complete the pending sign-in")
    func alternatePortIsNotTheClaimedOrigin() throws {
        let expected = AccountOAuthClaimedCallback.redirectURI(for: .staging)
        let callback = try #require(URL(
            string: "https://curfew-account-staging.hypertext.studio:444/oauth/callback/native/macos?code=code&state=expected-state"
        ))

        #expect(!AccountOAuthCallback.matchesPendingRequest(
            callback,
            expectedState: "expected-state",
            expectedRedirectURI: expected
        ))
    }

    @MainActor
    @Test("The app delegate routes a universal-link user activity from another browser")
    func appDelegateRoutesUniversalLinkActivity() throws {
        let router = AccountOAuthCallbackRouter()
        let delegate = AppDelegate(callbackRouter: router)
        let redirectURI = AccountOAuthClaimedCallback.redirectURI(for: .production)
        let callback = try #require(URL(
            string: redirectURI + "?code=code&state=expected-state"
        ))
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = callback
        var received: URL?
        _ = try router.register(
            expectedState: "expected-state",
            expectedRedirectURI: redirectURI
        ) { received = $0 }

        let handled = delegate.application(
            NSApplication.shared,
            continue: activity,
            restorationHandler: { _ in }
        )

        #expect(handled)
        #expect(received == callback)
    }
}
