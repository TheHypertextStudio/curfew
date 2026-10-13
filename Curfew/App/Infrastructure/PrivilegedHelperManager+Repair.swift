import CurfewKit
import Foundation
import ServiceManagement

extension PrivilegedHelperManager {
    func reconnectBackgroundProtection(
        quiesce: @escaping DaemonRegistrationRepair.Step,
        legacyAdmission: @escaping DaemonRegistrationRepair.Step,
        contextIsCurrent: @escaping @MainActor () -> Bool,
        resume: @escaping @MainActor () -> Void
    ) async {
        guard !repairInProgress else { return }
        repairInProgress = true
        defer { repairInProgress = false }
        lastError = nil
        let admit: DaemonRegistrationRepair.Step = { [self] in
            do {
                let status = try await daemonRPC.status()
                guard status.activeRecord == nil, !status.shutdownIssued else {
                    throw PrivilegedEnforcementError.activeLockout
                }
            } catch PrivilegedDaemonRPCError.unavailable {
                try await legacyAdmission()
            }
            guard contextIsCurrent() else { throw HelperMaintenanceError.changedState }
        }
        do {
            try await registrationRepair.run(
                quiesce: {
                    try await admit()
                    try await quiesce()
                },
                admit: { [self] in
                    try await admit()
                    maintenancePaused = true
                    connectionState = .unavailable
                },
                unregister: { [self] in
                    if daemonService.status != .notRegistered {
                        try await daemonService.unregisterAndWait()
                    }
                },
                register: { [self] in
                    try daemonService.register()
                    refreshStatus()
                },
                verify: { [self] in
                    try await verifyRepairedConnection(contextIsCurrent: contextIsCurrent)
                },
                resume: resume
            )
            guard contextIsCurrent() else { throw HelperMaintenanceError.changedState }
            maintenancePaused = false
        } catch {
            refreshStatus()
            connectionState = .unavailable
            lastError = error.localizedDescription
        }
    }

    private func verifyRepairedConnection(contextIsCurrent: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 10 {
            try Task.checkCancellation()
            guard contextIsCurrent() else { throw HelperMaintenanceError.changedState }
            if await reconcileDaemonStatus() != nil,
               connectionState == .ready, isDaemonResponding {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw PrivilegedDaemonRPCError.unavailable
    }
}
