import Foundation

/// Serializes authenticated mutations and policy application. Network discovery
/// runs separately so a coordinator outage cannot stall local XPC replies.
public final class AuthenticatedDaemonService: NSObject, CurfewDaemonXPCProtocol,
    NSXPCListenerDelegate {
    private let queue = DispatchQueue(label: "studio.hypertext.curfew.daemon.state")
    private let discoveryQueue = DispatchQueue(label: "studio.hypertext.curfew.daemon.discovery")
    private let store: PrivilegedDaemonStateStore
    private let persistenceError: NSError?
    private var control: AuthenticatedDaemonControl
    private var timer: DispatchSourceTimer?
    private var discoveryInFlight = false
    private var shutdownIssued = false
    private let readExternal: (AuthenticatedDaemonControl, Date) -> LockoutDeadlineRecord?
    private let evaluate: (PrivilegedDaemonStatus, Date, Bool) -> Bool
    private let discover: () -> Void
    private let sunriseScheduler: SunriseWakeScheduler?
    private let sunriseOwner: String
    private let sunriseNow: () -> Date
    private let sunriseOnExternalPower: () -> Bool

    public init(
        store: PrivilegedDaemonStateStore = PrivilegedDaemonStateStore(),
        readExternal: @escaping (AuthenticatedDaemonControl, Date) -> LockoutDeadlineRecord?,
        evaluate: @escaping (PrivilegedDaemonStatus, Date, Bool) -> Bool,
        discover: @escaping () -> Void,
        sunriseScheduler: SunriseWakeScheduler? = nil,
        sunriseOwner: String = CurfewFlavor.current.daemonLabel + ".sunrise",
        sunriseNow: @escaping () -> Date = Date.init,
        sunriseOnExternalPower: @escaping () -> Bool = { false }
    ) {
        self.store = store
        do {
            self.control = try store.loadControl() ?? AuthenticatedDaemonControl()
            self.persistenceError = nil
        } catch {
            // Keep independent file and signed-remote authority operational,
            // but never overwrite damaged authenticated state or acknowledge
            // a mutation that could not retain its release tombstones.
            self.control = AuthenticatedDaemonControl()
            self.persistenceError = error as NSError
            NSLog("Curfew authenticated daemon storage unavailable: %@", error.localizedDescription)
        }
        self.readExternal = readExternal
        self.evaluate = evaluate
        self.discover = discover
        self.sunriseScheduler = sunriseScheduler
        self.sunriseOwner = sunriseOwner
        self.sunriseNow = sunriseNow
        self.sunriseOnExternalPower = sunriseOnExternalPower
        super.init()
    }

    /// Inert boundary until failing-first service contracts are observed.
    /// No payload decoding, journal access or native operation occurs here.
    public func replaceSunriseWakePlan(
        _: Data, reply: @escaping (Data?, NSError?) -> Void
    ) {
        reply(nil, Self.sunriseUnavailable)
    }

    public func cancelSunriseWakePlan(reply: @escaping (Data?, NSError?) -> Void) {
        reply(nil, Self.sunriseUnavailable)
    }

    private static var sunriseUnavailable: NSError {
        NSError(
            domain: "studio.hypertext.curfew.daemon.sunrise", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Sunrise helper scheduling is unavailable."]
        )
    }

    public func evaluateNow() async -> PrivilegedDaemonStatus {
        await withCheckedContinuation { continuation in
            queue.async {
                let now = Date()
                self.evaluatePolicy(now: now)
                continuation.resume(returning: self.currentStatus(now: now))
            }
        }
    }

    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            evaluatePolicy(now: Date())
            guard !discoveryInFlight else { return }
            discoveryInFlight = true
            discoveryQueue.async {
                self.discover()
                self.queue.async {
                    self.discoveryInFlight = false
                    self.evaluatePolicy(now: Date())
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    public func listener(
        _: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard let identity = DaemonSigningIdentity.current else { return false }
        connection.setCodeSigningRequirement(identity.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: CurfewDaemonXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    public func armLockout(_ request: Data, reply: @escaping (Data?, NSError?) -> Void) {
        mutate(reply: reply) { control, _, now in
            try control.arm(
                Self.decoder.decode(LockoutDeadlineRecord.self, from: request),
                now: now
            )
        }
    }

    public func heartbeat(_ request: Data, reply: @escaping (Data?, NSError?) -> Void) {
        mutate(reply: reply) { control, external, now in
            let heartbeat = try Self.decoder.decode(PrivilegedHeartbeatRequest.self, from: request)
            try control.heartbeat(lockoutID: heartbeat.lockoutID, external: external, now: now)
        }
    }

    public func completeLockout(
        _ request: Data,
        reason: String,
        reply: @escaping (Data?, NSError?) -> Void
    ) {
        mutate(reply: reply) { control, external, now in
            let request = try Self.decoder.decode(PrivilegedHeartbeatRequest.self, from: request)
            guard let reason = PrivilegedCompletionReason(rawValue: reason) else {
                throw PrivilegedEnforcementError.invalidDeadline
            }
            try control.complete(
                lockoutID: request.lockoutID,
                reason: reason,
                now: now,
                external: external
            )
        }
    }

    public func status(reply: @escaping (Data?, NSError?) -> Void) {
        queue.async {
            do {
                if let error = self.persistenceError {
                    throw error
                }
                try reply(Self.encoder.encode(self.currentStatus(now: Date())), nil)
            } catch { reply(nil, Self.nsError(error)) }
        }
    }

    public func prepareForUninstall(reply: @escaping (Data?, NSError?) -> Void) {
        queue.async {
            do {
                if let error = self.persistenceError {
                    throw error
                }
                let now = Date()
                try self.control.prepareForUninstall(
                    external: self.readExternal(self.control, now),
                    now: now
                )
                try self.store.clear()
                try reply(Self.encoder.encode(self.currentStatus(now: now)), nil)
            } catch { reply(nil, Self.nsError(error)) }
        }
    }

    private func mutate(
        reply: @escaping (Data?, NSError?) -> Void,
        operation: @escaping (
            inout AuthenticatedDaemonControl,
            LockoutDeadlineRecord?,
            Date
        ) throws -> Void
    ) {
        queue.async {
            do {
                if let error = self.persistenceError {
                    throw error
                }
                let now = Date()
                let external = self.readExternal(self.control, now)
                var candidate = self.control
                try operation(&candidate, external, now)
                // Commit authority and release tombstones before acknowledging.
                try self.store.saveControl(candidate)
                self.control = candidate
                self.evaluatePolicy(now: now)
                try reply(Self.encoder.encode(self.currentStatus(now: now)), nil)
            } catch { reply(nil, Self.nsError(error)) }
        }
    }

    private func currentStatus(now: Date) -> PrivilegedDaemonStatus {
        control.status(
            external: readExternal(control, now),
            shutdownIssued: shutdownIssued,
            now: now
        )
    }

    private func evaluatePolicy(now: Date) {
        let status = currentStatus(now: now)
        shutdownIssued = evaluate(
            status, now, control.usesAuthenticatedHeartbeat(for: status.activeRecord, now: now)
        )
    }

    private static func nsError(_ error: Error) -> NSError {
        guard let enforcement = error as? PrivilegedEnforcementError
        else { return error as NSError }
        return NSError(
            domain: "studio.hypertext.curfew.daemon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: enforcement.rawValue]
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
