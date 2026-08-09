@testable import Curfew
import Foundation
import Testing

/// The reporter's two jobs: get a report out, and never let an older one land
/// on top of a newer one.
@MainActor
struct DeviceStatusReporterTests {
    private static let endpoint = URL(string: "https://coordinator.example/sync/heartbeat")!

    private func report(version: Int) -> DeviceStatusReport {
        var report = DeviceStatusReportPayloadTests.sample()
        report.statusVersion = version
        return report
    }

    // MARK: - The happy path

    @Test("A well-formed report reaches the transport with the endpoint and token")
    func publishesToTheConfiguredEndpoint() async {
        let transport = RecordingStatusTransport()
        let reporter = DeviceStatusReporter(transport: transport)

        reporter.report(report(version: 1), endpoint: Self.endpoint, bearerToken: "secret")
        await reporter.settle()

        #expect(transport.calls.count == 1)
        #expect(transport.calls.first?.endpoint == Self.endpoint)
        #expect(transport.calls.first?.bearerToken == "secret")
        #expect(transport.publishedVersions == [1])
    }

    // MARK: - Staleness

    @Test("A report that does not advance the version never reaches the transport")
    func staleReportIsDropped() async {
        let transport = RecordingStatusTransport()
        let reporter = DeviceStatusReporter(transport: transport)

        reporter.report(report(version: 5), endpoint: Self.endpoint, bearerToken: "")
        await reporter.settle()
        // Arriving late, carrying an older observation. This is the write the
        // coordinator must never take.
        reporter.report(report(version: 3), endpoint: Self.endpoint, bearerToken: "")
        await reporter.settle()
        // Same version again — a caller that reused a number.
        reporter.report(report(version: 5), endpoint: Self.endpoint, bearerToken: "")
        await reporter.settle()

        #expect(transport.publishedVersions == [5])
        #expect(reporter.highestPublishedVersion == 5)
    }

    @Test("A report queued behind an in-flight publish cannot overtake it")
    func inFlightPublishesCannotRace() async {
        let transport = BlockingStatusTransport()
        let reporter = DeviceStatusReporter(transport: transport)

        // v1 goes out and hangs.
        reporter.report(report(version: 1), endpoint: Self.endpoint, bearerToken: "")
        await pumpMainActor()
        #expect(transport.calls.count == 1)

        // v2 and v3 arrive while it is still open.
        reporter.report(report(version: 2), endpoint: Self.endpoint, bearerToken: "")
        reporter.report(report(version: 3), endpoint: Self.endpoint, bearerToken: "")
        await pumpMainActor()

        // Neither may start beside v1: two requests carrying different versions
        // in the network stack at once is exactly how they arrive out of order.
        #expect(transport.calls.count == 1)

        transport.release()
        await reporter.settle()

        // v2 was superseded by v3 before either could start, so it is dropped
        // rather than queued: publishing it would put a stale observation on the
        // wire behind a newer one. What lands is strictly increasing.
        #expect(transport.publishedVersions == [1, 3])
        let versions = transport.publishedVersions
        #expect(versions == versions.sorted())
    }

    @Test("A stale rejection from the coordinator is absorbed, not retried")
    func staleRejectionIsNotRetried() async {
        let transport = RecordingStatusTransport(outcome: .stale)
        let reporter = DeviceStatusReporter(transport: transport)

        reporter.report(report(version: 9), endpoint: Self.endpoint, bearerToken: "")
        await reporter.settle()

        // One attempt. Retrying would resend the report the coordinator has
        // already superseded.
        #expect(transport.calls.count == 1)
    }

    // MARK: - Failure handling

    @Test("Every failing outcome is absorbed without a retry")
    func failuresAreAbsorbed() async {
        let outcomes: [DeviceStatusPublishOutcome] = [
            .unreachable,
            .refused(500),
            .refused(401),
            .refused(404)
        ]

        for outcome in outcomes {
            let transport = RecordingStatusTransport(outcome: outcome)
            let reporter = DeviceStatusReporter(transport: transport)

            reporter.report(report(version: 1), endpoint: Self.endpoint, bearerToken: "")
            await reporter.settle()

            #expect(transport.calls.count == 1, "\(outcome) should not be retried")
        }
    }

    @Test("A malformed report is refused before it can reach the network")
    func malformedReportNeverLeaves() async {
        let transport = RecordingStatusTransport()
        let reporter = DeviceStatusReporter(transport: transport)
        var malformed = report(version: 1)
        malformed.deviceID = "not-a-uuid"

        reporter.report(malformed, endpoint: Self.endpoint, bearerToken: "")
        await reporter.settle()

        #expect(transport.calls.isEmpty)
        // And it did not burn the version, so the next good report still
        // advances from where the last published one left off.
        #expect(reporter.highestPublishedVersion == -1)
    }
}

/// The monotonic counter behind `statusVersion`.
struct DeviceStatusVersionCounterTests {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("The first version is zero, and every subsequent one is larger")
    func versionsIncreaseFromZero() {
        let counter = DeviceStatusVersionCounter(defaults: isolatedDefaults())

        #expect(counter.lastIssued == -1)
        #expect((0 ..< 5).map { _ in counter.next() } == [0, 1, 2, 3, 4])
    }

    @Test("A relaunch resumes above the last issued version rather than rewinding")
    func versionsSurviveARelaunch() {
        let defaults = isolatedDefaults()
        let before = DeviceStatusVersionCounter(defaults: defaults)
        _ = before.next()
        _ = before.next()
        _ = before.next()

        // A second counter over the same storage is what a relaunch looks like.
        let after = DeviceStatusVersionCounter(defaults: defaults)

        #expect(after.next() == 3)
    }

    @Test("A corrupted negative version cannot produce one the schema rejects")
    func corruptedStorageCannotGoNegative() {
        let defaults = isolatedDefaults()
        defaults.set(-42, forKey: DeviceStatusVersionCounter.storageKey)
        let counter = DeviceStatusVersionCounter(defaults: defaults)

        #expect(counter.next() == 0)
    }
}
