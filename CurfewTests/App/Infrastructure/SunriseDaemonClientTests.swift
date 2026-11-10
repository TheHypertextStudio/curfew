@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct SunriseDaemonClientTests {
    private func plan(owner: String = "studio.hypertext.curfew.sunrise") throws -> SunriseWakePlan {
        let json = """
        {"owner":"\(owner)","occurrenceID":"00000000-0000-0000-0000-000000000001",
        "wakeAt":"2027-01-01T08:00:00Z","holdUntil":"2027-01-01T08:35:00Z","allowsBattery":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SunriseWakePlan.self, from: Data(json.utf8))
    }

    @Test func replacementSendsTypedPlanAndRequiresExactEcho() async throws {
        let expected = try plan()
        let transport = RecordingTransport()
        let client = XPCPrivilegedDaemonClient(sunriseTransport: { method, request in
            await transport.call(method, request: request)
        })
        try await client.replaceSunriseWakePlan(expected)
        let calls = await transport.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == .replace)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request = try #require(calls.first?.1)
        #expect(try decoder.decode(SunriseWakePlan.self, from: request) == expected)
        let object = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
        #expect(Set(object.keys) == [
            "owner",
            "occurrenceID",
            "wakeAt",
            "holdUntil",
            "allowsBattery"
        ])
    }

    @Test func cancellationRequiresTrueAndHasNoPayload() async throws {
        let transport = RecordingTransport()
        let client = XPCPrivilegedDaemonClient(sunriseTransport: { method, request in
            await transport.call(method, request: request)
        })
        try await client.cancelSunriseWakePlan()
        let calls = await transport.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == .cancel)
        #expect(calls.first?.1 == nil)
    }

    @Test func malformedAndMismatchedEchoesAreRejected() async throws {
        let expected = try plan()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let mismatch = try encoder.encode(plan(owner: "another.owner"))
        for response in [Data("invalid".utf8), Data("true".utf8), mismatch] {
            let client = XPCPrivilegedDaemonClient(sunriseTransport: { _, _ in response })
            await #expect(throws: SunriseDaemonRPCError.invalidResponse) {
                try await client.replaceSunriseWakePlan(expected)
            }
        }
        let client = XPCPrivilegedDaemonClient(sunriseTransport: { _, _ in Data("false".utf8) })
        await #expect(throws: SunriseDaemonRPCError.invalidResponse) {
            try await client.cancelSunriseWakePlan()
        }
    }

    @Test func unavailableRemainsDistinctFromRejection() async throws {
        let expected = try plan()
        let client = XPCPrivilegedDaemonClient(sunriseTransport: { _, _ in
            throw SunriseDaemonRPCError.unavailable
        })
        await #expect(throws: SunriseDaemonRPCError.unavailable) {
            try await client.replaceSunriseWakePlan(expected)
        }
        await #expect(throws: SunriseDaemonRPCError.unavailable) {
            try await client.cancelSunriseWakePlan()
        }
        let rejected = XPCPrivilegedDaemonClient(sunriseTransport: { _, _ in
            throw SunriseDaemonRPCError.rejected
        })
        await #expect(throws: SunriseDaemonRPCError.rejected) {
            try await rejected.replaceSunriseWakePlan(expected)
        }
    }

    @Test func fractionalDatesCompareAtSerializedWirePrecision() async throws {
        let expected = SunriseWakePlan(
            owner: "studio.hypertext.curfew.sunrise", occurrenceID: UUID(),
            wakeAt: Date(timeIntervalSince1970: 1_800_000_000.25),
            holdUntil: Date(timeIntervalSince1970: 1_800_002_100.25), allowsBattery: false
        )
        let transport = RecordingTransport()
        let client = XPCPrivilegedDaemonClient(sunriseTransport: { method, request in
            await transport.call(method, request: request)
        })
        try await client.replaceSunriseWakePlan(expected)
        #expect(await transport.calls.count == 1)
    }

    @Test func oversizedPlanNeverReachesTransport() async throws {
        let expected = try plan(owner: String(repeating: "a", count: 4097))
        let transport = RecordingTransport()
        let client = XPCPrivilegedDaemonClient(sunriseTransport: { method, request in
            await transport.call(method, request: request)
        })
        await #expect(throws: SunriseDaemonRPCError.rejected) {
            try await client.replaceSunriseWakePlan(expected)
        }
        #expect(await transport.calls.isEmpty)
    }

    private actor RecordingTransport {
        var calls: [(SunriseDaemonRPCMethod, Data?)] = []

        func call(_ method: SunriseDaemonRPCMethod, request: Data?) -> Data {
            calls.append((method, request))
            return request ?? Data("true".utf8)
        }
    }
}
