import Foundation

/// Pulls a renewed subscription license from the license Worker.
///
/// Lifetime keys are perpetual and verified entirely offline — they never use
/// this. A subscription key carries a `refreshToken`; while the subscription is
/// active the Worker keeps a freshly-minted key (with an extended `expires_at`)
/// under that token, and the app fetches it on launch and once a day so Plus
/// keeps unlocking across renewals. A cancelled / unpaid subscription makes the
/// Worker drop the token, the fetch returns 404, and the stored key simply
/// lapses at its `expires_at` (+ grace) — `LicenseGate.isPlusUnlocked` then
/// locks Plus on the next daily re-verify, fully offline.
///
/// This is the only network call Curfew makes outside of Pro CloudKit sync.
struct LicenseRefresher {
    var baseURL = URL(string: "https://curfew-license.hypertext.studio")!
    var session: URLSession = .shared

    init(
        baseURL: URL = URL(string: "https://curfew-license.hypertext.studio")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Returns a renewed signed license key string for `refreshToken`, or `nil`
    /// when the subscription is no longer active (404) or the request failed.
    /// Never throws — a failed refresh is a no-op for the caller, which leaves
    /// the existing key in place to expire naturally.
    func refreshedKey(for refreshToken: String) async -> String? {
        guard
            var components = URLComponents(
                url: baseURL.appendingPathComponent("license/refresh"),
                resolvingAgainstBaseURL: false
            )
        else { return nil }
        components.queryItems = [URLQueryItem(name: "token", value: refreshToken)]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200
            else { return nil }
            let decoded = try JSONDecoder().decode(LicenseRefreshResponse.self, from: data)
            return decoded.licenseKey
        } catch {
            return nil
        }
    }
}

private struct LicenseRefreshResponse: Decodable {
    let licenseKey: String?

    enum CodingKeys: String, CodingKey {
        case licenseKey = "license_key"
    }
}
