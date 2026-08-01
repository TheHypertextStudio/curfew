import Foundation

/// Fetches the current signed key for an active Plus subscription. Lifetime
/// keys remain entirely offline; a failed refresh leaves the stored key alone
/// so it naturally fails closed at its signed expiry.
struct LicenseRefresher {
    var baseURL = URL(string: "https://curfew-license.hypertext.studio")!
    var session: URLSession = .shared

    func refreshedKey(for token: String) async -> String? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("license/refresh"),
            resolvingAgainstBaseURL: false
        )
        else { return nil }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(LicenseRefreshResponse.self, from: data).licenseKey
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
