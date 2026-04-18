import Foundation
import Network

/// Secondary MCP transport: Streamable HTTP on loopback-only TCP.
///
/// For remote MCP clients (editors over SSH, multi-process setups, future
/// web UIs) the app exposes the same tool registry over
/// `127.0.0.1:<port>` with JSON-RPC-in-POST-body + JSON-response.
///
/// Accept-time filtering rejects any non-loopback connection so the
/// listener is never reachable from another machine. The transport is
/// disabled by default; the user turns it on in Settings → Advanced →
/// Expose MCP over localhost HTTP.
///
/// v0.2 ships POST/JSON only. The MCP spec's full Streamable HTTP
/// includes SSE for streamed responses; Curfew's tools are all
/// request/response today so the shortened shape is sufficient. SSE
/// lands when a tool actually needs it.
///
/// Status: the wire format + listener are in place; on some macOS
/// versions the CLI binary needs `com.apple.security.network.server`
/// to bind, which requires codesigning with an Apple Developer cert.
/// Until the binary is signed via the release workflow, the listener
/// may silently stay in `.waiting` — the stdio transport keeps
/// working regardless.
final class StreamableHTTPTransport {
    private let server: MCPServer
    private let port: UInt16
    private var listener: NWListener?
    /// Dedicated queue so the listener services connections even while
    /// the main thread is blocked reading stdin in `MCPServer.run()`.
    /// `DispatchQueue.main` would deadlock in a CLI process without a
    /// run-loop pump.
    private let listenerQueue = DispatchQueue(
        label: "studio.hypertext.curfew.mcp-http",
        qos: .userInitiated
    )

    /// Wraps `server` behind an HTTP listener bound to `port` on the
    /// loopback interface only. Caller must still invoke `start()` to
    /// begin accepting connections.
    init(server: MCPServer, port: UInt16) {
        self.server = server
        self.port = port
    }

    /// Starts the listener. Emits one line on stderr when the port is
    /// already taken so the user can choose a different one. Otherwise
    /// runs silently until the process exits.
    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            FileHandle.standardError.write(Data(
                "curfew-mcp: invalid HTTP port \(port)\n".utf8
            ))
            return
        }

        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.acceptIfLoopback(connection: connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    FileHandle.standardError.write(Data(
                        "curfew-mcp: HTTP ready on 127.0.0.1:\(nwPort)\n".utf8
                    ))
                case .failed(let error):
                    FileHandle.standardError.write(Data(
                        "curfew-mcp: HTTP listener failed: \(error)\n".utf8
                    ))
                case .waiting(let error):
                    FileHandle.standardError.write(Data(
                        "curfew-mcp: HTTP listener waiting: \(error)\n".utf8
                    ))
                default:
                    break
                }
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch {
            FileHandle.standardError.write(Data(
                "curfew-mcp: HTTP transport failed to bind: \(error)\n".utf8
            ))
        }
    }

    /// Rejects any connection whose remote endpoint is not loopback. This
    /// is a belt-and-braces safety check: the listener itself is bound
    /// without an interface restriction because Network.framework's
    /// `requiredInterfaceType = .loopback` is unreliable across macOS
    /// versions. Filtering at accept time guarantees the tool surface is
    /// never reachable from another machine regardless of how the app
    /// was launched or what network interfaces happen to be up.
    private func acceptIfLoopback(connection: NWConnection) {
        if case .hostPort(let host, _) = connection.endpoint {
            let hostString = "\(host)"
            if hostString != "127.0.0.1" && hostString != "::1" && hostString != "localhost" {
                connection.cancel()
                return
            }
        }
        accept(connection: connection)
    }

    private func accept(connection: NWConnection) {
        connection.start(queue: listenerQueue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else {
                connection.cancel()
                return
            }
            let responseBytes = handleHTTPRequest(bytes: data)
            connection.send(
                content: responseBytes,
                completion: .contentProcessed { _ in
                    connection.cancel()
                }
            )
        }
    }

    /// Parses the minimum viable HTTP request: a single POST with a
    /// JSON body. Anything else returns 400. Responses are HTTP/1.1
    /// with a `Content-Type: application/json` header — enough for
    /// every current MCP client.
    private func handleHTTPRequest(bytes: Data) -> Data {
        guard let raw = String(data: bytes, encoding: .utf8) else {
            return respond(status: "400 Bad Request", body: "")
        }

        // Split headers from body on the canonical "\r\n\r\n" boundary.
        // A missing boundary means the client didn't finish streaming
        // headers; we ask them to try again with a 400 rather than
        // stall waiting for more bytes.
        guard let separator = raw.range(of: "\r\n\r\n") else {
            return respond(status: "400 Bad Request", body: "")
        }
        let body = String(raw[separator.upperBound...])
        let line = raw.split(separator: "\n").first.map(String.init) ?? ""
        guard line.hasPrefix("POST ") else {
            return respond(
                status: "405 Method Not Allowed",
                body: "POST only"
            )
        }

        let result = server.handle(line: body.trimmingCharacters(in: .whitespacesAndNewlines))
        return respond(status: "200 OK", body: result ?? "{}")
    }

    /// Canonical HTTP/1.1 response with a JSON body. CORS headers are
    /// omitted — the listener is loopback-only so cross-origin access
    /// isn't reachable in the first place.
    private func respond(status: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: application/json",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(headers.utf8) + bodyData
    }
}
