import AppKit
import SwiftUI

protocol AppCoordinating {
    @MainActor
    func handleInitialLaunch(
        model: CurfewAppModel,
        shouldStartEnforcement: Bool
    )
}

struct AppCoordinator: AppCoordinating {
    @MainActor
    func handleInitialLaunch(
        model: CurfewAppModel,
        shouldStartEnforcement: Bool
    ) {
        if shouldStartEnforcement {
            model.start()
        }

        if model.shouldOpenSettingsOnLaunch {
            model.showGettingStarted()
        }
    }
}

enum CurfewLaunchBehavior {
    static func shouldStartEnforcement(
        environment: [String: String],
        isDebugBuild: Bool
    ) -> Bool {
        if isDebugBuild {
            return environment["CURFEW_ENABLE_ENFORCEMENT"] == "1"
        }
        return environment["CURFEW_SKIP_ENFORCEMENT"] != "1"
    }
}

@main
struct CurfewApp: App {
    @StateObject private var model: CurfewAppModel
    @StateObject private var updater = CurfewUpdater()

    private static let shouldStartEnforcementOnLaunch = CurfewLaunchBehavior.shouldStartEnforcement(
        environment: ProcessInfo.processInfo.environment,
        isDebugBuild: isDebugBuild
    )

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    init() {
        let model = CurfewAppModel()
        _model = StateObject(wrappedValue: model)

        DispatchQueue.main.async {
            AppCoordinator().handleInitialLaunch(
                model: model,
                shouldStartEnforcement: Self.shouldStartEnforcementOnLaunch
            )
        }
    }

    var body: some Scene {
        WindowGroup(id: MainWorkspaceSection.windowID) {
            MainWindowView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }

        MenuBarExtra("Curfew", systemImage: model.menuBarSymbolName) {
            ContentView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 520)
        }
    }
}
