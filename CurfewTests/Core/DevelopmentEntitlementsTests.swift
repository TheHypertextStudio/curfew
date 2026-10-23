@testable import Curfew
import CurfewKit
import Foundation
import Testing

struct DevelopmentEntitlementsTests {
    @Test("Development builds cannot request the production widget container")
    func developmentCannotAuthorizeProductionContainer() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: source.appendingPathComponent("Curfew/Curfew.entitlements"))
        let entitlements = try #require(PropertyListSerialization.propertyList(
            from: data, format: nil
        ) as? [String: Any])
        let groups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        #expect(!groups.contains("group.studio.hypertext.curfew"))
        #expect(!FeatureFlags.default.widgetKitEnabled)
    }
}
