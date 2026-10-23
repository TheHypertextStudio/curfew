import AppKit
import CurfewKit
import Foundation

@MainActor
extension CurfewApp {
    static func handleBackgroundServiceCommand() {
        #if CURFEW_STAGING
            if ProcessInfo.processInfo.arguments.contains("--register-background-service-staging") {
                guard CurfewFlavor.current == .development else { exit(64) }
                let manager = BackgroundServiceManager()
                manager.register()
                print(manager.statusLine)
                if let error = manager.lastError {
                    fputs("\(error)\n", stderr)
                }
                exit(manager.isEnabled ? 0 : 1)
            }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--unregister-background-service") {
            do {
                try BackgroundServiceManager().unregister()
                exit(0)
            } catch {
                fputs(
                    "Curfew could not stop background recovery: \(error.localizedDescription)\n",
                    stderr
                )
                exit(1)
            }
        }
    }
}
