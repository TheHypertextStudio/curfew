import CurfewKit
import SwiftUI

extension View {
    /// A Debug-only fixture layout hook. Shipping windows retain native sizing.
    @ViewBuilder
    func demoWindowSize(
        width: CGFloat,
        height: CGFloat,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> some View {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CURFEW_DEMO_FIXTURE"] == "1" {
                background(DemoWindowSize(
                    width: width,
                    height: height,
                    minimumWidth: minimumWidth,
                    minimumHeight: minimumHeight
                ))
            } else {
                self
            }
        #else
            self
        #endif
    }
}

#if DEBUG
    private struct DemoWindowSize: NSViewRepresentable {
        let width: CGFloat
        let height: CGFloat
        let minimumWidth: CGFloat
        let minimumHeight: CGFloat

        func makeNSView(context: Context) -> SizingView {
            let minimum = ProcessInfo.processInfo.environment["CURFEW_DEMO_SIZE"] == "minimum"
            let view = SizingView()
            view.size = NSSize(
                width: minimum ? minimumWidth : width,
                height: minimum ? minimumHeight : height
            )
            return view
        }

        func updateNSView(_ nsView: SizingView, context: Context) {}

        final class SizingView: NSView {
            var size = NSSize.zero
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window else { return }
                DispatchQueue.main.async { window.setContentSize(self.size) }
            }
        }
    }
#endif
