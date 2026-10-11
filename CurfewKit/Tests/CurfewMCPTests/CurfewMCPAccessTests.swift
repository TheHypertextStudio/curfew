@testable import curfew_mcp
import Foundation
import Testing

struct CurfewMCPAccessTests {
    @Test("Disabled local access hides tools and rejects cached calls")
    func disabledAccessClosesBothDispatcherPaths() throws {
        let server = MCPServer(isAccessEnabled: { false })

        let list = try response(
            from: server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        )
        let result = try #require(list["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        #expect(tools.isEmpty)

        let call = try response(
            from: server.handle(
                line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"curfew_get_reflections","arguments":{}}}"#
            )
        )
        let error = try #require(call["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32001)
        #expect((error["message"] as? String)?.contains("turned off") == true)
    }

    private func response(from line: String?) throws -> [String: Any] {
        let line = try #require(line)
        let data = try #require(line.data(using: .utf8))
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
