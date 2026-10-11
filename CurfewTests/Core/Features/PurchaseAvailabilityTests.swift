@testable import Curfew
@testable import CurfewKit
import Testing

struct PurchaseAvailabilityTests {
    @Test("initial release does not offer a hosted checkout")
    func checkoutIsUnavailable() {
        #expect(PurchaseAvailability.checkoutURL == nil)
    }
}
