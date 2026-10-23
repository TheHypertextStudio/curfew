import CurfewKit
import Foundation
import Observation

@MainActor
@Observable
final class LicenseActivationController {
    private(set) var isBusy = false
    private enum Notice {
        case activating
        case active(LicenseKey)
        case restoring
        case restoreSent(String)
    }

    private var notice: Notice?
    var message: String? {
        switch notice {
        case .activating: "Activating Curfew Plus…"
        case .active(let purchase):
            gate.isPlusUnlocked && gate.activatedKey == purchase ? "Curfew Plus is active." : nil
        case .restoring: "Sending restore link…"
        case .restoreSent(let email): "Check \(email) for your restore link."
        case nil: nil
        }
    }

    private(set) var error: String?
    private let gate: LicenseGate
    private let service: any LicenseServicing
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var currentTicket: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(gate: LicenseGate, service: any LicenseServicing = LicenseService()) {
        self.gate = gate
        self.service = service
    }

    static func token(in url: URL, flavor: CurfewFlavor) -> String? {
        let scheme = switch flavor {
        case .production: "curfew"
        case .development: "curfew-dev"
        }
        guard url.scheme == scheme, url.host == "activate", url.path.isEmpty,
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.count == 1,
              items[0].name == "token", let token = items[0].value,
              token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
        else { return nil }
        return token
    }

    @discardableResult
    func open(_ url: URL, flavor: CurfewFlavor = LicenseEndpoint.currentFlavor) -> Bool {
        guard let token = Self.token(in: url, flavor: flavor) else { return false }
        if currentTicket == token {
            return true
        }
        cancel()
        currentTicket = token
        task = Task { await activate(ticket: token) }
        return true
    }

    func activate(ticket: String) async {
        guard !Task.isCancelled else { return }
        let operation = begin()
        currentTicket = ticket
        notice = .activating
        defer { finish(operation) }
        do {
            let key = try await service.redeem(ticket: ticket)
            guard generation == operation, !Task.isCancelled else { return }
            gate.activate(key)
            recordActivationResult()
        } catch {
            fail(error, operation: operation)
        }
    }

    @discardableResult
    func restore(email: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let operation = begin()
        notice = .restoring
        defer { finish(operation) }
        do {
            try await service.restore(email: email)
            guard generation == operation, !Task.isCancelled else { return false }
            notice = .restoreSent(email)
            return true
        } catch {
            fail(error, operation: operation)
            return false
        }
    }

    func activateManually(_ key: String) {
        cancel()
        gate.activate(key)
        recordActivationResult()
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        currentTicket = nil
        isBusy = false
        notice = nil
        error = nil
    }

    private func recordActivationResult() {
        error = gate.activationError
        if error == nil, gate.isPlusUnlocked, let purchase = gate.activatedKey {
            notice = .active(purchase)
        } else {
            notice = nil
        }
    }

    private func begin() -> UUID {
        generation = UUID()
        isBusy = true
        notice = nil
        error = nil
        return generation
    }

    private func finish(_ operation: UUID) {
        guard generation == operation else { return }
        isBusy = false
        currentTicket = nil
    }

    private func fail(_ failure: Error, operation: UUID) {
        guard generation == operation, !Task.isCancelled else { return }
        notice = nil
        error = (failure as? LocalizedError)?.errorDescription ??
            "Couldn't reach the purchase service. Check your connection and try again."
    }
}
