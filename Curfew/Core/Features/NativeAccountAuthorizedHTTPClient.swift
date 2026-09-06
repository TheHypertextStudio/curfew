import Foundation

private struct NativeAuthorizedWrite {
    let method: String
    let path: String
    let body: Data
    let deviceID: UUID
    let accessToken: String
    let signingPrivateKey: Data
}

struct NativeAccountAuthorizedHTTPClient {
    private let baseURL: URL
    private let session: URLSession
    private let proofFactory: AccountDeviceProofFactory

    init(
        session: URLSession,
        proofFactory: AccountDeviceProofFactory,
        endpoints: CurfewServiceEndpoints = .current
    ) {
        self.session = session
        self.proofFactory = proofFactory
        self.baseURL = endpoints.syncResource
    }

    func get(
        path: String,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws -> Data? {
        let nonce = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let url = baseURL.appending(path: path)
        let proof = try proofFactory.make(.init(
            accessToken: accessToken,
            nonce: nonce,
            method: "GET",
            url: url,
            body: nil,
            signingPrivateKey: signingPrivateKey
        ))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.setValue(
            deviceID.uuidString.lowercased(),
            forHTTPHeaderField: "X-Curfew-Device-ID"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeAccountSyncError.invalidResponse
        }
        if http.statusCode == 404 {
            return nil
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw NativeAccountSyncError.rejected(http.statusCode)
        }
        return data
    }

    func put(
        path: String,
        body: Data,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws {
        _ = try await write(.init(
            method: "PUT",
            path: path,
            body: body,
            deviceID: deviceID,
            accessToken: accessToken,
            signingPrivateKey: signingPrivateKey
        ))
    }

    @discardableResult
    func post(
        path: String,
        body: Data,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws -> Data {
        try await write(.init(
            method: "POST",
            path: path,
            body: body,
            deviceID: deviceID,
            accessToken: accessToken,
            signingPrivateKey: signingPrivateKey
        ))
    }

    private func write(_ input: NativeAuthorizedWrite) async throws -> Data {
        let nonce = try await challenge(deviceID: input.deviceID, accessToken: input.accessToken)
        let url = baseURL.appending(path: input.path)
        let proof = try proofFactory.make(.init(
            accessToken: input.accessToken,
            nonce: nonce,
            method: input.method,
            url: url,
            body: input.body,
            signingPrivateKey: input.signingPrivateKey
        ))
        var request = URLRequest(url: url)
        request.httpMethod = input.method
        request.httpBody = input.body
        request.setValue("Bearer \(input.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.setValue(
            input.deviceID.uuidString.lowercased(),
            forHTTPHeaderField: "X-Curfew-Device-ID"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeAccountSyncError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw NativeAccountSyncError.rejected(http.statusCode)
        }
        return data
    }

    private func challenge(deviceID: UUID, accessToken: String) async throws -> String {
        let url = baseURL.appending(path: "/sync/device-proof/challenge")
        let body = try JSONSerialization.data(
            withJSONObject: ["deviceId": deviceID.uuidString.lowercased()],
            options: [.sortedKeys]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeAccountSyncError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw NativeAccountSyncError.rejected(http.statusCode)
        }
        guard let nonce = try? JSONDecoder()
            .decode(NativeDeviceProofChallenge.self, from: data)
            .coordinatorNonce
        else { throw NativeAccountSyncError.invalidResponse }
        return nonce
    }
}
