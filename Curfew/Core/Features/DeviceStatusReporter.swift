import Foundation
import OSLog

/// What one publish attempt did.
///
/// `stale` is not an error and is deliberately not lumped in with `refused`:
/// it is the coordinator's staleness guard doing its job, and the correct
/// response is to carry on, not to retry a report the server has already
/// superseded.
enum DeviceStatusPublishOutcome: Equatable, Sendable {
    /// The coordinator accepted the report (documented as `204`).
    case accepted

    /// The coordinator already holds a newer `statusVersion` (documented as
    /// `409`). This report lost the race and must not be resent.
    case stale

    /// The coordinator answered, but not with acceptance. Carries the status
    /// code so the log can say which.
    case refused(Int)

    /// Nothing answered — offline, DNS failure, TLS failure, timeout, the
    /// endpoint does not exist. Indistinguishable from each other here, and
    /// treated the same way: drop it, the next heartbeat is the retry.
    case unreachable
}

/// How a report gets to a coordinator. A protocol so the suite can prove the
/// failure paths without a network, and so the reporter's ordering guarantees
/// can be asserted against a transport that records what it was handed.
protocol DeviceStatusTransporting: Sendable {
    /// Publishes `body` and reports what happened. Never throws: a transport
    /// failure is an outcome, not an exception, because no caller of this is in
    /// a position to handle one.
    func publish(
        _ body: Data,
        to endpoint: URL,
        bearerToken: String
    ) async -> DeviceStatusPublishOutcome
}

/// The production transport: one `POST`, short timeout, no retry.
///
/// Deliberately spartan. Every knob that could make a request take longer is
/// turned down, because this request rides alongside enforcement on a Mac whose
/// user is trying to work.
struct URLSessionDeviceStatusTransport: DeviceStatusTransporting {
    /// How long a publish may take before it is abandoned. Well under the
    /// shortest heartbeat, so attempts can never pile up.
    static let timeoutSeconds: TimeInterval = 10

    /// Built per instance rather than sharing `URLSession.shared`, so Curfew's
    /// telemetry cannot inherit or contribute cookies, credentials, or a cache
    /// shared with anything else the app does.
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeoutSeconds
        configuration.timeoutIntervalForResource = Self.timeoutSeconds
        // Off on purpose. `waitsForConnectivity` would park a request until the
        // network returns, which for a status report means holding a stale
        // observation open until it describes a moment that has passed.
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = true
        self.session = URLSession(configuration: configuration)
    }

    func publish(
        _ body: Data,
        to endpoint: URL,
        bearerToken: String
    ) async -> DeviceStatusPublishOutcome {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200 ..< 300: return .accepted
            case 409: return .stale
            default: return .refused(http.statusCode)
            }
        } catch {
            return .unreachable
        }
    }
}

/// Publishes device status to a coordinator, best-effort.
///
/// **This must never affect enforcement.** Curfew's whole value is that it
/// locks the machine when it said it would, and it has to do that on a plane,
/// behind a captive portal, and while the coordinator is down. Three properties
/// hold that line, and each is structural rather than a promise:
///
/// 1. ``report(_:endpoint:bearerToken:)`` is synchronous, non-throwing, and
///    returns without awaiting anything. The caller — `tick()`, on the main
///    actor, once a second — cannot be suspended by it.
/// 2. Every network outcome collapses to a log line. There is no error to
///    propagate, no exception to catch at the call site, and no code path from
///    a failed publish back into the enforcement engine.
/// 3. There is no retry. A failed report is dropped; the next transition or
///    heartbeat carries fresher state anyway, so retrying would put a stale
///    observation on the wire *and* build a queue that grows while offline.
///
/// It also enforces, on the device side, the ordering the coordinator's
/// staleness guard enforces on the server side — see ``report(_:endpoint:bearerToken:)``.
@MainActor
final class DeviceStatusReporter {
    /// One publish, packaged. A named type rather than a tuple because it
    /// travels into a `Task` and back out of a queue, and four positional
    /// members is where a tuple stops documenting itself.
    private struct Envelope {
        let body: Data
        let endpoint: URL
        let token: String
        let version: Int
    }

    private let transport: any DeviceStatusTransporting
    private let logger = Logger(subsystem: "studio.hypertext.curfew", category: "sync")

    /// The highest `statusVersion` this reporter has put on the wire. Reports
    /// at or below it are refused before they reach the transport.
    private(set) var highestPublishedVersion = -1

    /// The publish currently running, if any.
    private var inFlight: Task<Void, Never>?

    /// The newest report that arrived while ``inFlight`` was running, and that
    /// will go out when it finishes. Only ever one: an older pending report is
    /// replaced, not queued, because a coordinator wants this device's *current*
    /// state and every superseded report would be rejected as stale anyway.
    private var pending: Envelope?

    init(transport: any DeviceStatusTransporting = URLSessionDeviceStatusTransport()) {
        self.transport = transport
    }

    /// Hands `report` to the transport, eventually. Returns immediately.
    ///
    /// Two independent guards keep a delayed report from clobbering a newer
    /// one, because the failure they prevent is the one the coordinator cannot
    /// recover from:
    ///
    /// - **Nothing goes out twice, or backwards.** A report whose
    ///   `statusVersion` is not greater than ``highestPublishedVersion`` is
    ///   dropped here. That covers a caller that reuses a version, and it means
    ///   the numbers arriving at the coordinator are strictly increasing at the
    ///   point they leave this machine.
    /// - **Only one publish is in flight.** A report arriving mid-publish
    ///   replaces any pending one and waits its turn, so two requests carrying
    ///   different versions can never race in the network stack and arrive out
    ///   of order.
    ///
    /// The server-side guard still matters — this process is not the only thing
    /// that can talk to a coordinator, and a report can be delayed by a proxy
    /// after it leaves here. These guards make sure Curfew is not itself the
    /// source of an out-of-order write.
    func report(_ report: DeviceStatusReport, endpoint: URL, bearerToken: String) {
        guard report.isWellFormed else {
            logger.error("Refusing to publish a status report that violates the schema")
            return
        }
        guard report.statusVersion > highestPublishedVersion else {
            logger.debug("Dropping status report that does not advance the version")
            return
        }
        guard let body = try? report.encodedBody() else {
            logger.error("Failed to encode a status report")
            return
        }
        highestPublishedVersion = report.statusVersion
        let work = Envelope(
            body: body,
            endpoint: endpoint,
            token: bearerToken,
            version: report.statusVersion
        )
        guard inFlight == nil else {
            pending = work
            return
        }
        start(work)
    }

    /// Awaits whatever this reporter is doing. Test-only affordance: production
    /// never needs to know when a publish finished, which is the point.
    func settle() async {
        while let task = inFlight {
            await task.value
        }
    }

    private func start(_ work: Envelope) {
        inFlight = Task { [transport, logger] in
            let outcome = await transport.publish(
                work.body,
                to: work.endpoint,
                bearerToken: work.token
            )
            switch outcome {
            case .accepted:
                logger.debug("Published device status v\(work.version, privacy: .public)")
            case .stale:
                // The coordinator holds something newer. Nothing to do — and
                // explicitly no retry, which would resend the losing report.
                let version = work.version
                logger.debug("Coordinator holds a status newer than v\(version, privacy: .public)")
            case .refused(let code):
                logger.warning("Coordinator refused device status: \(code, privacy: .public)")
            case .unreachable:
                // The expected outcome offline, and not worth a warning: the
                // product is working exactly as designed when this happens.
                logger.debug("Coordinator unreachable; dropping this status report")
            }
            self.finish()
        }
    }

    private func finish() {
        inFlight = nil
        guard let next = pending else { return }
        pending = nil
        start(next)
    }
}
