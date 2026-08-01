import CurfewKit
import Foundation

/// Decoded payload from a verified Curfew Plus license key.
struct LicenseKey: Codable, Equatable {
    enum Plan: String, Codable {
        case lifetime
        case subscription
    }

    /// Email address the key was issued to. Shown in Settings → License.
    let email: String
    /// Product SKU. Must equal `"curfew-plus"` for this build to accept the
    /// key (legacy `"curfew-pro"` is also accepted as a lifetime key for
    /// pre-release continuity); other values are rejected via
    /// `LicenseActivationError.wrongProduct`.
    let product: String
    let plan: Plan
    /// Stripe Checkout Session id (kept as the `order_id` wire field).
    /// Surfaces in support workflows.
    let orderID: String
    /// Issuance timestamp from the Cloudflare Worker signer.
    let issuedAt: Date
    let expiresAt: Date?
    let refreshToken: String?

    /// Maps Swift property names to the snake_case fields the Cloudflare
    /// Worker emits, so the signed JSON and the Swift struct stay in
    /// lock-step across releases.
    enum CodingKeys: String, CodingKey {
        /// Email address field.
        case email
        /// Product SKU field.
        case product
        case plan
        /// Stripe Checkout Session id — `order_id` in JSON (legacy field name).
        case orderID = "order_id"
        /// Issue timestamp — `issued_at` in JSON.
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
    }

    init(
        email: String,
        product: String,
        plan: Plan = .lifetime,
        orderID: String,
        issuedAt: Date,
        expiresAt: Date? = nil,
        refreshToken: String? = nil
    ) {
        self.email = email
        self.product = product
        self.plan = plan
        self.orderID = orderID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decode(String.self, forKey: .email)
        self.product = try container.decode(String.self, forKey: .product)
        self.plan = try container.decodeIfPresent(Plan.self, forKey: .plan) ?? .lifetime
        self.orderID = try container.decode(String.self, forKey: .orderID)
        self.issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
    }
}
