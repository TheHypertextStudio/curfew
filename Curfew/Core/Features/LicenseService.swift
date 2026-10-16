import CurfewKit
import Foundation

nonisolated protocol LicenseServicing: Sendable {
    func redeem(ticket: String) async throws -> String
    func restore(email: String) async throws
}

nonisolated enum LicenseEndpoint {
    static func url(for flavor: CurfewFlavor) -> URL {
        switch flavor {
        case .production: URL(string: "https://curfew-license.hypertext.studio")!
        case .development, .studioDevelopment:
            URL(string: "https://curfew-license-staging.hypertext.studio")!
        }
    }
}

nonisolated struct LicenseService: LicenseServicing {
    var baseURL = LicenseEndpoint.url(for: .current)
    var session = URLSession.shared

    func redeem(ticket: String) async throws -> String {
        let data = try await post("license/redeem", body: ["token": ticket])
        let response = try JSONDecoder().decode(Redemption.self, from: data)
        guard !response.licenseKey.isEmpty else { throw LicenseServiceError.unavailable }
        return response.licenseKey
    }

    func restore(email: String) async throws {
        _ = try await post("license/restore", body: ["email": email])
    }

    private func post(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LicenseServiceError.unavailable }
        switch http.statusCode {
        case 200, 202: return data
        case 404: throw LicenseServiceError.notFound
        case 410: throw LicenseServiceError.expiredLink
        case 429: throw LicenseServiceError.rateLimited
        default: throw LicenseServiceError.unavailable
        }
    }
}

private nonisolated struct Redemption: Decodable {
    let licenseKey: String
    enum CodingKeys: String, CodingKey { case licenseKey = "license_key" }
}

nonisolated enum LicenseServiceError: LocalizedError {
    case unavailable, notFound, expiredLink, rateLimited

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Couldn't reach the purchase service. Check your connection and try again."
        case .notFound:
            "No purchase was found for this link. Restore using the email on your receipt."
        case .expiredLink: "This link has expired. Restore your purchase to get a new one."
        case .rateLimited: "Please wait a minute before requesting another restore link."
        }
    }
}
