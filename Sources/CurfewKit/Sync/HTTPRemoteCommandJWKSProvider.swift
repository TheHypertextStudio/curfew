import Foundation

public enum RemoteCommandJWKSFetchError: Error, Equatable {
    case invalidEndpoint
    case timedOut
    case transport
    case rejected(Int)
    case invalidResponse
}

private final class RemoteCommandJWKSResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<(Data, HTTPURLResponse), Error>?

    func store(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func load() -> Result<(Data, HTTPURLResponse), Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class RemoteCommandRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Synchronous adapter used by the daemon's synchronous enforcement loop.
/// Network I/O stays behind `RemoteCommandJWKSProvider`, so the verifier and
/// command policy remain platform-neutral and deterministic in tests.
public final class HTTPRemoteCommandJWKSProvider: RemoteCommandJWKSProvider,
    @unchecked Sendable {
    private let endpoint: URL
    private let session: URLSession
    private let timeout: TimeInterval

    public init(
        endpoint: URL,
        session: URLSession? = nil,
        timeout: TimeInterval = 10
    ) {
        self.endpoint = endpoint
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: RemoteCommandRedirectDelegate(),
            delegateQueue: nil
        )
        self.timeout = timeout
    }

    public func jwks() throws -> RemoteCommandJWKS {
        guard endpoint.scheme == "https",
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil
        else { throw RemoteCommandJWKSFetchError.invalidEndpoint }

        let semaphore = DispatchSemaphore(value: 0)
        let box = RemoteCommandJWKSResponseBox()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if error != nil {
                box.store(.failure(RemoteCommandJWKSFetchError.transport))
                return
            }
            guard let data, let response = response as? HTTPURLResponse else {
                box.store(.failure(RemoteCommandJWKSFetchError.invalidResponse))
                return
            }
            box.store(.success((data, response)))
        }.resume()

        guard semaphore.wait(timeout: .now() + timeout) == .success,
              let result = box.load()
        else { throw RemoteCommandJWKSFetchError.timedOut }
        let (data, response) = try result.get()
        guard response.statusCode == 200 else {
            throw RemoteCommandJWKSFetchError.rejected(response.statusCode)
        }
        guard data.count <= 64 * 1024,
              let jwks = try? JSONDecoder().decode(RemoteCommandJWKS.self, from: data),
              !jwks.keys.isEmpty,
              jwks.keys.count <= 8
        else { throw RemoteCommandJWKSFetchError.invalidResponse }
        return jwks
    }
}
