@testable import Curfew
import Foundation
import Testing

struct AccountStatusPresentationTests {
    @Test("Local update failures do not claim account access was removed")
    func localFailure() {
        for reason in [
            "Rejected stale or invalid wake state.",
            "Could not authorize remote unlock on this Mac."
        ] {
            let presentation = AccountConnectionPresentation.resolve(.rejected(reason))
            #expect(presentation.title == "Remote update couldn’t be applied")
            #expect(!presentation.detail.contains("removed"))
            #expect(presentation.detail.contains("schedule is unchanged"))
        }
        let denied = AccountConnectionPresentation
            .resolve(.rejected(AccountSyncRejectionReason.accessDenied))
        #expect(denied.title == "Check this Mac’s account access")
        #expect(denied.detail.contains("retry the connection if access is restored"))
    }

    @Test("Hidden background protection never directs users to its missing settings")
    func unavailableHelper() {
        let presentation = AccountConnectionPresentation.resolve(
            .synchronized(Date()), remoteEnforcementReady: false,
            remoteEnforcementSupported: false
        )
        #expect(!presentation.detail.contains("General"))
        #expect(presentation.detail.contains("official website"))
    }
}
