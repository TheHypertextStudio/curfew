import SwiftUI

/// Any available scene can fulfill navigation. The menu-bar label also
/// registers at launch, before a workspace or Settings window is needed.
private struct AppWindowRoutingModifier: ViewModifier {
    let router: AppRouting
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        content.onAppear {
            router.registerWindowActions(
                open: { openWindow(id: $0) },
                dismiss: { dismissWindow(id: $0) }
            )
        }
    }
}

extension View {
    func appWindowRouting(using router: AppRouting) -> some View {
        modifier(AppWindowRoutingModifier(router: router))
    }
}
