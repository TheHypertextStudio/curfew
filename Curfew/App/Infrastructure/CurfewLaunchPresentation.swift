import AppKit

extension CurfewLaunchBehavior {
    /// How the process shows itself on this Mac.
    struct Presentation: Equatable {
        var activationPolicy: NSApplication.ActivationPolicy
        var showsMenuBarItem: Bool
        var opensWindowsOnLaunch: Bool
    }

    /// A unit-test host is not an app anyone launched: it stays out of the
    /// Dock and the menu bar and opens no windows, so several test runs do
    /// not look like several copies of Curfew. Tests still create the
    /// windows they render.
    static func presentation(hostsUnitTests: Bool) -> Presentation {
        hostsUnitTests
            ? Presentation(
                activationPolicy: .accessory, showsMenuBarItem: false, opensWindowsOnLaunch: false
            )
            : Presentation(
                activationPolicy: .regular, showsMenuBarItem: true, opensWindowsOnLaunch: true
            )
    }
}
