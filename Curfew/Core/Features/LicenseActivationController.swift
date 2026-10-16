import CurfewKit
import Foundation
import Observation

@MainActor
@Observable
final class LicenseActivationController {
    private(set) var isBusy = false
    private(set) var message: String?
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
        case .studioDevelopment: "curfew-studio-dev"
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
    func open(_ url: URL, flavor: CurfewFlavor = .current) -> Bool {
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
        let operation = begin()
        currentTicket = ticket
        message = "Activating Curfew Plus…"
        defer { finish(operation) }
        do {
            let key = try await service.redeem(ticket: ticket)
            guard generation == operation, !Task.isCancelled else { return }
            gate.activate(key)
            error = gate.activationError
            message = error == nil && gate.isPlusUnlocked ? "Curfew Plus is active." : nil
        } catch {
            fail(error, operation: operation)
        }
    }

    func restore(email: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let operation = begin()
        message = "Sending restore link…"
        defer { finish(operation) }
        do {
            try await service.restore(email: email)
            guard generation == operation, !Task.isCancelled else { return }
            message = "Check \(email) for your restore link."
        } catch {
            fail(error, operation: operation)
        }
    }

    func activateManually(_ key: String) {
        cancel()
        gate.activate(key)
        error = gate.activationError
        message = error == nil && gate.isPlusUnlocked ? "Curfew Plus is active." : nil
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        currentTicket = nil
        isBusy = false
        message = nil
        error = nil
    }

    private func begin() -> UUID {
        generation = UUID()
        isBusy = true
        message = nil
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
        message = nil
        error = (failure as? LocalizedError)?.errorDescription ??
            "Couldn't reach the purchase service. Check your connection and try again."
    }
}
