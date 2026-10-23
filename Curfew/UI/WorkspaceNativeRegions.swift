import AppKit
import SwiftUI

/// Names AppKit's hosting and split-column containers, rather than introducing
/// additional SwiftUI groups inside the unnamed native containers.
@MainActor
enum WorkspaceNativeRegions {
    static func name(in root: NSView, selectedTitle: String) {
        name(root, "Curfew workspace")
        guard let split = firstSplit(in: root), split.arrangedSubviews.count == 2 else { return }
        name(split.arrangedSubviews[0], "Workspace navigation")
        name(split.arrangedSubviews[1], "\(selectedTitle) workspace")
    }

    private static func name(_ view: NSView, _ label: String) {
        if view.accessibilityLabel() != label {
            view.setAccessibilityLabel(label)
        }
    }

    private static func firstSplit(in view: NSView, depth: Int = 0) -> NSSplitView? {
        guard depth < 32 else { return nil }
        if let split = view as? NSSplitView {
            return split
        }
        for child in view.subviews {
            if let split = firstSplit(in: child, depth: depth + 1) {
                return split
            }
        }
        return nil
    }
}

struct WorkspaceNativeRegionReader: NSViewRepresentable {
    let selectedTitle: String

    func makeNSView(context: Context) -> RegionView {
        let view = RegionView()
        view.setAccessibilityElement(false)
        view.update(selectedTitle: selectedTitle)
        return view
    }

    func updateNSView(_ view: RegionView, context: Context) {
        view.update(selectedTitle: selectedTitle)
    }

    final class RegionView: NSView {
        private var selectedTitle = ""
        private var synchronizationScheduled = false

        func update(selectedTitle: String) {
            guard self.selectedTitle != selectedTitle else { return }
            self.selectedTitle = selectedTitle
            synchronize()
            scheduleSynchronization()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            synchronize()
            scheduleSynchronization()
        }

        override func layout() {
            super.layout()
            synchronize()
        }

        private func synchronize() {
            guard let root = window?.contentView else { return }
            WorkspaceNativeRegions.name(in: root, selectedTitle: selectedTitle)
        }

        private func scheduleSynchronization() {
            guard !synchronizationScheduled else { return }
            synchronizationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                synchronizationScheduled = false
                synchronize()
            }
        }
    }
}
