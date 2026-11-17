import AppKit
import SwiftUI

/// The small panel that floats beside System Settings during step 2: the app
/// icon to drag into the Accessibility list, and one line saying so.
struct GettingStartedDragPanelView: View {
    let icon: NSImage
    let bundleURL: URL

    var body: some View {
        VStack(spacing: GettingStartedLayout.spacing12) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .onDrag { NSItemProvider(object: bundleURL as NSURL) }
                .accessibilityLabel("Curfew app icon")
                .accessibilityHint("Drag into the Accessibility list in System Settings.")
            Text(GettingStartedCopy.dragInstruction)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(GettingStartedPalette.panelText)
        }
        .padding(GettingStartedLayout.spacing24)
        .frame(
            width: DragPanelPlacement.panelSize.width,
            height: DragPanelPlacement.panelSize.height
        )
        .background(
            GettingStartedPalette.panelSurface,
            in: RoundedRectangle(cornerRadius: GettingStartedLayout.panelRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GettingStartedLayout.panelRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .accessibilityElement(children: .contain)
    }
}

/// Floats the drag panel above every app's normal windows without taking
/// focus from System Settings. Same panel recipe as the warning notice.
@MainActor
final class DragPanelWindowPresenter: DragPanelPresenting {
    static let windowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless, .nonactivatingPanel],
        level: .floating,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .transient],
        isMovable: false,
        hidesOnDeactivate: false
    )

    private var panel: NSPanel?

    func show(at frame: CGRect) {
        let panel = panel ?? makePanel(frame: frame)
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func move(to frame: CGRect) {
        panel?.setFrame(frame, display: true, animate: false)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let configuration = Self.windowConfiguration
        let panel = NSPanel(
            contentRect: frame,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = configuration.level
        panel.ignoresMouseEvents = configuration.ignoresMouseEvents
        panel.collectionBehavior = configuration.collectionBehavior
        panel.isMovable = configuration.isMovable
        panel.hidesOnDeactivate = configuration.hidesOnDeactivate
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let bundleURL = Bundle.main.bundleURL
        panel.contentView = NSHostingView(rootView: GettingStartedDragPanelView(
            icon: NSWorkspace.shared.icon(forFile: bundleURL.path),
            bundleURL: bundleURL
        ))
        return panel
    }
}
