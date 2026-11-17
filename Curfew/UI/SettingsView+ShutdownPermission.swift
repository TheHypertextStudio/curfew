import AppKit
import CoreServices
import Foundation

/// Asks macOS whether Curfew may send System Events the shutdown command,
/// prompting the person if they have not decided yet.
enum ShutdownAutomationPermission {
    enum Result: Equatable {
        case granted
        case denied
        case undetermined
    }

    private static let systemEventsBundleID = "com.apple.systemevents"
    private static let systemEventsURL =
        URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")

    static func request() async -> Result {
        var status = await determine()
        if status == OSStatus(procNotFound) {
            // The check needs System Events running; start it without focus.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            _ = try? await NSWorkspace.shared.openApplication(
                at: systemEventsURL, configuration: configuration
            )
            status = await determine()
        }
        return result(for: status)
    }

    static func result(for status: OSStatus) -> Result {
        switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        default: .undetermined
        }
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func determine() async -> OSStatus {
        await Task.detached(priority: .userInitiated) {
            var target = AEAddressDesc()
            let bundleID = Array(systemEventsBundleID.utf8)
            let created = bundleID.withUnsafeBufferPointer { buffer in
                AECreateDesc(
                    DescType(typeApplicationBundleID), buffer.baseAddress, buffer.count, &target
                )
            }
            guard created == noErr else { return OSStatus(created) }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(
                &target, AEEventClass(typeWildCard), AEEventID(typeWildCard), true
            )
        }.value
    }
}
