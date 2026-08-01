import CurfewKit
import Foundation
import OSLog

private let daemonLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "privileged-daemon"
)

private final class DaemonConnectionValidator {
    func authenticate(_ connection: NSXPCConnection) {
        // Foundation evaluates every incoming message against the sender's
        // audit-token code identity, avoiding PID reuse and lookup races.
        connection.setCodeSigningRequirement(
            PrivilegedDaemonConstants.clientSigningRequirement
        )
    }
}

private final class DaemonService: NSObject, CurfewDaemonXPCProtocol {
    private let queue = DispatchQueue(label: "studio.hypertext.curfew.daemon.state")
    private let store: PrivilegedDaemonStateStore
    private var machine: PrivilegedEnforcementStateMachine
    private var timer: DispatchSourceTimer?

    override init() {
        let store = PrivilegedDaemonStateStore()
        self.store = store
        let now = Date()
        if let persisted = try? store.load() {
            machine = PrivilegedEnforcementStateMachine(status: persisted, startedAt: now)
        } else {
            machine = PrivilegedEnforcementStateMachine(startedAt: now)
        }
        super.init()
        startEvaluationTimer()
    }

    func armLockout(_ request: Data, reply: @escaping (Data?, NSError?) -> Void) {
        mutate(reply: reply) { machine in
            let record = try Self.decoder.decode(LockoutDeadlineRecord.self, from: request)
            try machine.arm(record, now: Date())
        }
    }

    func heartbeat(_ request: Data, reply: @escaping (Data?, NSError?) -> Void) {
        mutate(reply: reply) { machine in
            let heartbeat = try Self.decoder.decode(PrivilegedHeartbeatRequest.self, from: request)
            try machine.heartbeat(lockoutID: heartbeat.lockoutID, now: Date())
        }
    }

    func completeLockout(
        _ request: Data,
        reason: String,
        reply: @escaping (Data?, NSError?) -> Void
    ) {
        mutate(reply: reply) { machine in
            let completion = try Self.decoder.decode(PrivilegedHeartbeatRequest.self, from: request)
            guard let reason = PrivilegedCompletionReason(rawValue: reason) else {
                throw PrivilegedEnforcementError.invalidDeadline
            }
            try machine.complete(lockoutID: completion.lockoutID, reason: reason, now: Date())
        }
    }

    func status(reply: @escaping (Data?, NSError?) -> Void) {
        queue.async {
            do {
                try self.expireElapsedLockout(now: Date())
                reply(try Self.encoder.encode(self.machine.status), nil)
            } catch {
                reply(nil, Self.nsError(error))
            }
        }
    }

    func prepareForUninstall(reply: @escaping (Data?, NSError?) -> Void) {
        queue.async {
            do {
                let now = Date()
                try self.expireElapsedLockout(now: now)
                try self.machine.prepareForUninstall(now: now)
                try self.store.clear()
                reply(try Self.encoder.encode(self.machine.status), nil)
            } catch {
                reply(nil, Self.nsError(error))
            }
        }
    }

    private func mutate(
        reply: @escaping (Data?, NSError?) -> Void,
        operation: @escaping (inout PrivilegedEnforcementStateMachine) throws -> Void
    ) {
        queue.async {
            do {
                try operation(&self.machine)
                try self.persistCurrentStatus()
                reply(try Self.encoder.encode(self.machine.status), nil)
            } catch {
                reply(nil, Self.nsError(error))
            }
        }
    }

    private func startEvaluationTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.evaluateHeartbeat()
        }
        self.timer = timer
        timer.resume()
    }

    private func evaluateHeartbeat() {
        let now = Date()
        do {
            try expireElapsedLockout(now: now)
            guard machine.evaluate(now: now) == .shutdown else { return }
            try persistCurrentStatus()
            issueShutdown()
        } catch {
            daemonLogger.error("daemon evaluation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func expireElapsedLockout(now: Date) throws {
        guard let record = machine.status.activeRecord,
              now >= record.scheduledUnlockAt
        else { return }
        try machine.complete(lockoutID: record.lockoutID, reason: .naturalExpiry, now: now)
        try store.clear()
    }

    private func persistCurrentStatus() throws {
        if machine.status.activeRecord == nil {
            try store.clear()
        } else {
            try store.save(machine.status)
        }
    }

    private func issueShutdown() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/shutdown")
        process.arguments = ["-h", "+1", "Curfew enforcement: app heartbeat stale."]
        do {
            try process.run()
            daemonLogger.notice("/sbin/shutdown -h +1 issued")
        } catch {
            daemonLogger.error("shutdown failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func nsError(_ error: Error) -> NSError {
        if let enforcementError = error as? PrivilegedEnforcementError {
            return NSError(
                domain: "studio.hypertext.curfew.daemon",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: enforcementError.rawValue]
            )
        }
        return error as NSError
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

private final class DaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = DaemonService()
    private let validator = DaemonConnectionValidator()

    func listener(
        _: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        validator.authenticate(connection)
        connection.exportedInterface = NSXPCInterface(with: CurfewDaemonXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private let delegate = DaemonListenerDelegate()
private let listener = NSXPCListener(machServiceName: PrivilegedDaemonConstants.machServiceName)
listener.delegate = delegate
daemonLogger.info("curfew-daemon listening on authenticated Mach service")
listener.resume()
RunLoop.current.run()
