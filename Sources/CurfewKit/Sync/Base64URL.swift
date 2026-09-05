import Foundation

/// Unpadded base64url, the one spelling every sync-facing digest and JOSE
/// segment in curfew-protocols uses.
///
/// Extracted so there is exactly one implementation of it. `scheduleDigest`,
/// the device-status `cursor`, the assertion's `keyThumbprint`, and all three
/// segments of a `CompactJWS` are the same transformation of different bytes,
/// and a second copy that differed by a padding character would produce values
/// the coordinator's `^[A-Za-z0-9_-]{43}$` and `CompactJWS` patterns reject —
/// silently, at request time, on someone else's machine.
public enum Base64URL {
    /// `data` as unpadded base64url: standard base64 with `+` → `-`, `/` → `_`,
    /// and the `=` padding removed.
    ///
    /// Removing the padding is required rather than cosmetic. RFC 7515 §2
    /// defines JOSE's BASE64URL as unpadded, and the schemas follow it: both
    /// `^[A-Za-z0-9_-]{43}$` (a SHA-256) and `CompactJWS`'s
    /// `[A-Za-z0-9_-]{86}` (an HMAC-SHA-512) admit no `=` at all.
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes a strictly unpadded base64url value.
    public static func decode(_ value: String) -> Data? {
        guard !value.isEmpty,
              value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        else { return nil }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
