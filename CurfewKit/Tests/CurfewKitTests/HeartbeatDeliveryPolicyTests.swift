import CurfewKit
import Foundation
import Testing

struct HeartbeatDeliveryPolicyTests {
    private let start = Date(timeIntervalSince1970: 10000)

    @Test func rollbackAboveLastSendStillRequiresFreshHeartbeat() {
        #expect(HeartbeatDeliveryPolicy.shouldSend(
            lastSentAt: start, lastObservedAt: start.addingTimeInterval(24),
            now: start.addingTimeInterval(1), interval: 30
        ))
    }

    @Test func sameObservationAfterCorrectionDoesNotFloodHeartbeats() {
        #expect(!HeartbeatDeliveryPolicy.shouldSend(
            lastSentAt: start, lastObservedAt: start, now: start, interval: 30
        ))
    }

    @Test func backwardCorrectionCannotStrandAppHeartbeatDelivery() {
        #expect(HeartbeatDeliveryPolicy.shouldSend(
            lastSentAt: start, now: start.addingTimeInterval(-3600), interval: 30
        ))
    }

    @Test func firstHeartbeatIsNotThrottled() {
        #expect(HeartbeatDeliveryPolicy.shouldSend(lastSentAt: nil, now: start, interval: 30))
    }

    @Test func normalThirtySecondBoundaryIsPreserved() {
        #expect(!HeartbeatDeliveryPolicy.shouldSend(
            lastSentAt: start, now: start.addingTimeInterval(29), interval: 30
        ))
        #expect(HeartbeatDeliveryPolicy.shouldSend(
            lastSentAt: start, now: start.addingTimeInterval(30), interval: 30
        ))
    }

    @Test func repeatedObservationAtSameInstantDoesNotFloodHeartbeats() {
        #expect(!HeartbeatDeliveryPolicy.shouldSend(lastSentAt: start, now: start, interval: 30))
    }
}
