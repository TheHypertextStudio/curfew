import AppKit
@testable import Curfew
import CurfewKit
import SwiftUI
import Testing

/// A click on the evening close-out's answer must land on the text view
/// itself, so it takes keyboard focus. Nothing drawn over the field, such as
/// its focus outline or the panel's glass, may take the click instead.
@MainActor
struct CloseOutClickTests {
    @Test("A click on the close-out's answer reaches its text view")
    func clickReachesTheAnswer() throws {
        let draft = ReflectionDraft(prompts: [
            ReflectionPrompt(text: "What would you like to leave here for tomorrow?", kind: .text)
        ])
        let form = ReflectionFormView(
            draft: draft, submitLabel: "Save", usesSolidPanels: false,
            onSubmit: { _ in }, onSkip: {}
        )
        .padding(CurfewSpacing.xLarge)
        .frame(width: 520)
        .nightPanel()
        let host = NSHostingView(rootView: form)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()

        let textView = try #require(Self.firstTextView(in: host))
        let center = NSPoint(x: textView.bounds.midX, y: textView.bounds.midY)
        let superview = try #require(host.superview)
        let point = textView.convert(center, to: superview)
        let hit = try #require(host.hitTest(point))
        #expect(
            hit === textView || hit.isDescendant(of: textView),
            "The click lands on \(type(of: hit)), not the answer's text view"
        )
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) {
                return found
            }
        }
        return nil
    }
}
