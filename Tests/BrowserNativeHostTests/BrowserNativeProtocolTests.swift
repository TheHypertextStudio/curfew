@testable import CurfewKit
import Foundation
import Testing

struct BrowserNativeProtocolTests {
    @Test func framesUseNativeLengthAndSupportMultipleMessages() throws {
        let first = Data(
            #"{"schemaVersion":"browser-host/1","requestId":"one","type":"get_policy"}"#
                .utf8
        )
        let second = Data(
            #"{"schemaVersion":"browser-host/1","requestId":"two","type":"heartbeat"}"#
                .utf8
        )
        var buffer = try BrowserNativeFraming.encode(first) + BrowserNativeFraming.encode(second)
        #expect(try BrowserNativeFraming.take(from: &buffer) == first)
        #expect(try BrowserNativeFraming.take(from: &buffer) == second)
        #expect(buffer.isEmpty)
    }

    @Test func framingRejectsOversizeBeforeReadingBody() throws {
        var length = UInt32(64 * 1024 * 1024 + 1)
        var buffer = withUnsafeBytes(of: &length) { Data($0) }
        #expect(throws: BrowserNativeError.messageTooLarge) {
            try BrowserNativeFraming.take(from: &buffer)
        }
        #expect(throws: BrowserNativeError.messageTooLarge) {
            try BrowserNativeFraming.encode(Data(repeating: 0, count: 1024 * 1024 + 1))
        }
    }

    @Test func partialFrameWaitsForRemainingBytes() throws {
        var buffer = Data([10, 0])
        #expect(try BrowserNativeFraming.take(from: &buffer) == nil)
        #expect(buffer == Data([10, 0]))
    }

    @Test(arguments: [
        #"{"schemaVersion":"browser-host/2","requestId":"one","type":"get_policy"}"#,
        #"{"schemaVersion":"browser-host/1","requestId":"one","type":"get_policy","allowAll":true}"#,
        #"{"schemaVersion":"browser-host/1","requestId":"one","type":"heartbeat","justification":"private"}"#,
        #"{"schemaVersion":"browser-host/1","requestId":"","type":"get_policy"}"#
    ])
    func rejectsAmbiguousRequests(json: String) {
        #expect(throws: (any Error).self) { try BrowserNativeRequest.decode(Data(json.utf8)) }
    }

    @Test func requestAndResponsePreserveCorrelation() throws {
        let data = Data(
            #"{"schemaVersion":"browser-host/1","requestId":"caller-123","type":"get_policy"}"#
                .utf8
        )
        let request = try BrowserNativeRequest.decode(data)
        let response = BrowserNativeResponse(requestID: request.requestID, type: request.type)
        let object = try #require(JSONSerialization
            .jsonObject(with: BrowserNativeJSON.encode(response)) as? [String: Any])
        #expect(object["requestId"] as? String == "caller-123")
        #expect(object["schemaVersion"] as? String == "browser-host/1")
    }
}
