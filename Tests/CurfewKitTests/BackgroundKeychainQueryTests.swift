@testable import CurfewKit
import LocalAuthentication
import Security
import Testing

@Suite("Background Keychain queries")
struct BackgroundKeychainQueryTests {
    @Test("Use the Data Protection Keychain without authentication UI")
    func usesDataProtectionKeychainWithoutUI() throws {
        let query = BackgroundKeychainQuery.read(
            service: "studio.hypertext.curfew.docket",
            account: "oauth-access-token"
        )
        let context = try #require(query[kSecUseAuthenticationContext] as? LAContext)

        #expect(query[kSecClass] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService] as? String == "studio.hypertext.curfew.docket")
        #expect(query[kSecAttrAccount] as? String == "oauth-access-token")
        #expect(query[kSecUseDataProtectionKeychain] as? Bool == true)
        #expect(query[kSecReturnData] as? Bool == true)
        #expect(query[kSecMatchLimit] as? String == kSecMatchLimitOne as String)
        #expect(context.interactionNotAllowed)
    }
}
