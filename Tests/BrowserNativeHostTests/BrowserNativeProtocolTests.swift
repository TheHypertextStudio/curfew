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

    @Test func policyRequestCarriesOnlyAnOptionalKnownRevision() throws {
        let data = Data(
            #"{"schemaVersion":"browser-host/1","requestId":"watch","type":"get_policy","knownPolicyRevision":"revision-1"}"#
                .utf8
        )

        let request = try BrowserNativeRequest.decode(data)

        #expect(request.type == .getPolicy)
        #expect(request.knownPolicyRevision == "revision-1")
        #expect(request.sessionID == nil)
        #expect(request.destination == nil)
    }

    @Test(arguments: [19, 1001])
    func reviewRejectsJustificationOutsideDocketCharacterLimits(length: Int) throws {
        let data = try reviewRequest(justification: String(repeating: "x", count: length))

        #expect(throws: BrowserNativeError.invalidRequest) {
            try BrowserNativeRequest.decode(data)
        }
    }

    @Test func reviewUsesDocketUTF16CharacterSemantics() throws {
        let accepted = try reviewRequest(justification: String(repeating: "😀", count: 500))
        let rejected = try reviewRequest(justification: String(repeating: "😀", count: 501))

        #expect(try BrowserNativeRequest.decode(accepted).justification?.utf16.count == 1000)
        #expect(throws: BrowserNativeError.invalidRequest) {
            try BrowserNativeRequest.decode(rejected)
        }
    }

    @Test func reviewRejectsAChallengeAnswerOverOneThousandUTF16Characters() throws {
        let accepted = try reviewRequest(
            justification: String(repeating: "x", count: 20),
            challengeAnswer: String(repeating: "😀", count: 500)
        )
        let rejected = try reviewRequest(
            justification: String(repeating: "x", count: 20),
            challengeAnswer: String(repeating: "😀", count: 501)
        )

        #expect(try BrowserNativeRequest.decode(accepted).challengeAnswer?.utf16.count == 1000)
        #expect(throws: BrowserNativeError.invalidRequest) {
            try BrowserNativeRequest.decode(rejected)
        }
    }

    private func reviewRequest(
        justification: String,
        challengeAnswer: String? = nil
    ) throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": "browser-host/1",
            "requestId": "review",
            "type": "review_destination",
            "sessionId": "00000000-0000-0000-0000-000000000001",
            "destination": ["origin": "https://example.com", "path": "/research"],
            "justification": justification
        ]
        object["challengeAnswer"] = challengeAnswer
        return try JSONSerialization.data(withJSONObject: object)
    }
}
