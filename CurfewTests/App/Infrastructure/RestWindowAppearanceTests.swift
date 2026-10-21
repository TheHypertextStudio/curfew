import AppKit
@testable import Curfew
import SwiftUI
import Testing

@MainActor
struct RestWindowAppearanceTests {
    @Test(arguments: [NSAppearance.Name.aqua.rawValue, NSAppearance.Name.darkAqua.rawValue])
    func restWindowsAndHostsUseDarkAppearance(suppliedName: String) throws {
        let supplied = try #require(NSAppearance(named: NSAppearance.Name(rawValue: suppliedName)))
        let coordinator = OverlayCoordinator()
        for configuration in [
            OverlayCoordinator.lockoutWindowConfiguration,
            OverlayCoordinator.daybreakWindowConfiguration
        ] {
            let window = makeWindow()
            defer { window.orderOut(nil) }
            window.appearance = supplied
            coordinator.apply(configuration: configuration, to: window)
            let host = OverlayCoordinator.makeRestHostingView(rootView: Text("A reflection"))
            window.contentView = host

            #expect(
                window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                "Rest window supplied \(suppliedName), actual \(window.effectiveAppearance.name.rawValue)"
            )
            #expect(
                host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                "Rest host supplied \(suppliedName), actual \(host.effectiveAppearance.name.rawValue)"
            )
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua.rawValue, NSAppearance.Name.darkAqua.rawValue])
    func warningAndTimerPreserveSuppliedAppearance(suppliedName: String) throws {
        let supplied = try #require(NSAppearance(named: NSAppearance.Name(rawValue: suppliedName)))
        let coordinator = OverlayCoordinator()
        for configuration in [
            OverlayCoordinator.warningWindowConfiguration,
            OverlayCoordinator.timerWindowConfiguration
        ] {
            let window = makeWindow()
            defer { window.orderOut(nil) }
            window.appearance = supplied
            coordinator.apply(configuration: configuration, to: window)
            #expect(
                window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == supplied.name,
                "Non-rest window supplied \(suppliedName), actual \(window.effectiveAppearance.name.rawValue)"
            )
        }
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }
}
