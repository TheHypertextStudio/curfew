import AppKit
import CurfewKit
import ServiceManagement
import SwiftUI

extension SettingsView {
    var backgroundServicePanel: some View {
        BackgroundServicePanel(
            manager: model.backgroundServiceManager,
            runtimePersistenceError: model.runtimePersistenceError
        )
    }
}

private struct BackgroundServicePanel: View {
    @ObservedObject var manager: BackgroundServiceManager
    let runtimePersistenceError: String?

    var body: some View {
        Section("Background recovery") {
            if manager.isAvailable {
                Label(
                    manager.statusLine,
                    systemImage: manager.isRecoveryHealthy
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(manager.isRecoveryHealthy ? CurfewTheme.accent : CurfewTheme
                    .warning)

                detail(manager.detail)
                if let error = manager.lastError {
                    detail(error)
                        .foregroundStyle(CurfewTheme.warning)
                        .accessibilityIdentifier("background-service-error")
                }
                if let error = manager.supervisorHealthError {
                    detail(error)
                        .foregroundStyle(CurfewTheme.warning)
                        .accessibilityIdentifier("supervisor-health-error")
                }
                if manager.status != .enabled {
                    HStack {
                        if manager.status == .notRegistered || manager.status == .notFound {
                            Button("Enable Background Recovery") { manager.register() }
                                .buttonStyle(CurfewSecondaryButtonStyle())
                        }
                        Button("Open Login Items") { manager.openSystemSettings() }
                            .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            } else {
                detail("This development build does not install background recovery.")
            }
            if let error = runtimePersistenceError {
                Label(
                    "Curfew cannot save grants and budgets",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.warning)
                detail(error)
                    .accessibilityIdentifier("runtime-persistence-error")
            }
        }
        .accessibilityIdentifier("background-service-status")
        .onAppear { manager.refreshStatus() }
        .onReceive(NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                manager.refreshStatus()
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}
