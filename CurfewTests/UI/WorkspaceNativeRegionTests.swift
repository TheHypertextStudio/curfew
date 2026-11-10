import AppKit
@testable import Curfew
import SwiftUI
import Testing

@MainActor
struct WorkspaceNativeRegionTests {
    @Test("Native column naming preserves controls and follows the selected destination")
    func nativeColumnsPreserveTheirChildren() {
        let root = NSView()
        let split = NSSplitView()
        let navigation = NSView()
        let detail = NSView()
        let control = NSButton(title: "An existing action", target: nil, action: nil)
        root.addSubview(split)
        split.addArrangedSubview(navigation)
        split.addArrangedSubview(detail)
        detail.addSubview(control)
        WorkspaceNativeRegions.name(in: root, selectedTitle: "Today")
        #expect(root.accessibilityLabel() == "Curfew workspace")
        #expect(navigation.accessibilityLabel() == "Workspace navigation")
        #expect(detail.accessibilityLabel() == "Today workspace")
        WorkspaceNativeRegions.name(in: root, selectedTitle: "Schedule")
        #expect(detail.accessibilityLabel() == "Schedule workspace")
        #expect(detail.subviews.first === control)
        #expect(control.isEnabled)
        #expect(control.title == "An existing action")
    }

    @Test("The workspace names its actual native hosting container")
    func nativeHostingContainerHasAName() {
        let host = NSHostingView(rootView: MainWindowView().environment(CurfewAppModel.demoModel()))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(host.accessibilityLabel() == "Curfew workspace")
        #expect(!window.isVisible)
    }
}
