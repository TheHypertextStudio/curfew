@testable import Curfew
import Foundation
import LocalAuthentication
import Security
import Testing

@Suite("Keychain account secret store")
struct KeychainAccountSecretStoreTests {
    @Test("Background credential reads never present Keychain authorization UI")
    func backgroundReadsAreNonInteractive() throws {
        let query = KeychainAccountSecretStore.backgroundReadQuery(
            service: "studio.hypertext.curfew.docket",
            account: "oauth-access-token"
        )
        let context = try #require(query[kSecUseAuthenticationContext] as? LAContext)

        #expect(context.interactionNotAllowed)
    }
}
