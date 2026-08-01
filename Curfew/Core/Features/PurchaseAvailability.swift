import Foundation

/// Centralizes whether the current build may direct a person to hosted checkout.
///
/// The initial release keeps checkout unavailable until the production
/// purchase-to-license path is ready to be offered. Existing license keys can
/// still be activated locally.
enum PurchaseAvailability {
    static let checkoutURL: URL? = nil
}
