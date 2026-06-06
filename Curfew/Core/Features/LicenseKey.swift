import Foundation

/// Decoded payload from a verified Curfew Pro license key.
struct LicenseKey: Codable, Equatable {
    /// Email address the key was issued to. Shown in Settings → License.
    let email: String
    /// Product SKU. Must equal `"curfew-pro"` for this build to accept
    /// the key; other values (future SKUs, team licences) are rejected
    /// via `LicenseActivationError.wrongProduct`.
    let product: String
    /// Stripe Checkout Session id (kept as the `order_id` wire field).
    /// Surfaces in support workflows.
    let orderID: String
    /// Issuance timestamp from the Cloudflare Worker signer.
    let issuedAt: Date

    /// Maps Swift property names to the snake_case fields the Cloudflare
    /// Worker emits, so the signed JSON and the Swift struct stay in
    /// lock-step across releases.
    enum CodingKeys: String, CodingKey {
        /// Email address field.
        case email
        /// Product SKU field.
        case product
        /// Stripe Checkout Session id — `order_id` in JSON (legacy field name).
        case orderID = "order_id"
        /// Issue timestamp — `issued_at` in JSON.
        case issuedAt = "issued_at"
    }
}
