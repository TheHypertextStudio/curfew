import Foundation

/// Decoded payload from a verified Curfew Pro license key.
struct LicenseKey: Codable, Equatable {
    let email: String
    let product: String
    let orderID: String
    let issuedAt: Date

    enum CodingKeys: String, CodingKey {
        case email
        case product
        case orderID = "order_id"
        case issuedAt = "issued_at"
    }
}
