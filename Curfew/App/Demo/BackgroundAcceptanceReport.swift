import CurfewKit
#if DEBUG
    import AppKit
    import Foundation

    @MainActor
    extension CurfewAppModel {
        /// Only the isolated fixture emits this local evidence; Release cannot honor the path.
        func recordBackgroundAcceptanceState() {
            guard RuntimeEnvironment.isDemoFixture,
                  let path = ProcessInfo.processInfo.environment["CURFEW_ACCEPTANCE_REPORT"]
            else { return }
            let report = BackgroundAcceptanceReport(
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                phase: AuditTokens.phase(state.phase),
                isEnforcementRunning: isEnforcementRunning,
                ordinaryWindows: NSApp.windows.filter { $0.isVisible && $0.level == .normal }.count,
                lockoutWindows: NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver }
                    .count,
                accessibilityGranted: isAccessibilityTrusted,
                keyboardShieldEnabled: lockoutKeyInterceptor.isEnabled,
                enforcementHealth: String(describing: enforcementHealth)
            )
            if let data = try? JSONEncoder().encode(report) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }

    private struct BackgroundAcceptanceReport: Encodable {
        let processIdentifier: Int32
        let phase: String
        let isEnforcementRunning: Bool
        let ordinaryWindows: Int
        let lockoutWindows: Int
        let accessibilityGranted: Bool
        let keyboardShieldEnabled: Bool
        let enforcementHealth: String
    }
#endif
