import AppKit
import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// What tonight looks like, shown from setup step 3. It is drawn from plain
/// values, has an obvious way out, and is not the real lock: no kiosk mode,
/// no key interception, no enforcement state.
struct GettingStartedLockPreviewView: View {
    let content: LockPreviewContent
    let appearance: RestAppearancePreferences
    let onEnd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var headlineFocused: Bool

    var body: some View {
        ZStack {
            RestAmbientScene(
                snapshot: RestSceneSnapshot(
                    version: 1,
                    expiresAt: .distantFuture,
                    appearance: appearance,
                    lockDate: content.curfew,
                    unlockDate: content.unlock
                ),
                date: content.curfew,
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency,
                showsClock: false
            ) { frame, drifts in
                HorizonSkyView(frame: frame, isDayRunning: drifts)
            }
            VStack(spacing: GettingStartedLayout.spacing16) {
                Text(content.curfew, style: .time)
                    .font(.system(size: 96, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(GettingStartedCopy.lockedHeadline)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headlineFocused)
                Label(GettingStartedCopy.unlockLine(content.unlock), systemImage: "lock.fill")
                    .font(.system(.title3, design: .rounded, weight: .medium))
            }
            .foregroundStyle(GettingStartedPalette.panelText)
            VStack {
                Text("Preview")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(GettingStartedPalette.panelMutedText)
                    .padding(.top, GettingStartedLayout.spacing40)
                Spacer()
                Button(GettingStartedCopy.endPreview, action: onEnd)
                    .buttonStyle(PreviewEndButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .padding(
                        .bottom,
                        GettingStartedLayout.spacing40 + GettingStartedLayout.spacing24
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEnd)
        .onAppear { headlineFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lock preview")
    }
}

/// Floating capsule over the scene.
private struct PreviewEndButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .padding(.horizontal, GettingStartedLayout.spacing24)
            .padding(.vertical, GettingStartedLayout.spacing12)
            .foregroundStyle(GettingStartedPalette.panelText)
            .background(.white.opacity(0.2), in: .capsule)
            // Fill only: a stroked Capsule overlay drew a second straight
            // outline on the frame's left and right edges. The focus ring
            // follows the capsule.
            .contentShape(.focusEffect, Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Covers the screen setup is on with the preview, above ordinary windows
/// but below anything the system shows, and takes key focus so Escape ends it.
@MainActor
final class LockPreviewWindowPresenter: LockPreviewPresenting {
    private let appearance: () -> RestAppearancePreferences
    private var window: NSWindow?

    init(appearance: @escaping () -> RestAppearancePreferences) {
        self.appearance = appearance
    }

    func show(_ content: LockPreviewContent, onEnd: @escaping () -> Void) {
        hide()
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.frame else { return }
        let window = PreviewWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenAuxiliary, .transient]
        window.contentView = NSHostingView(rootView: GettingStartedLockPreviewView(
            content: content,
            appearance: appearance(),
            onEnd: onEnd
        ))
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Borderless windows refuse key status by default; the preview needs it
/// for Escape and the keyboard path to its button.
private final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}
