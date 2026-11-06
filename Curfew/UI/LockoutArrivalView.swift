import SwiftUI

enum LockoutArrivalAnimation {
    static func duration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : 3
    }
}

/// The window is fully opaque and captures input from its first frame. Only
/// its content changes, so the arrival animation cannot expose the desktop.
struct LockoutArrivalView: View {
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    var body: some View {
        ZStack {
            LockoutScreenView(message: model.lockoutMessage)

            LinearGradient(
                colors: [
                    SundownPalette.ink,
                    SundownPalette.ember
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .overlay {
                Text("Curfew starts now")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(SundownPalette.warmWhite)
            }
            .opacity(reduceMotion || isRevealed ? 0 : 1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .onAppear {
            let duration = LockoutArrivalAnimation.duration(reduceMotion: reduceMotion)
            if duration == 0 {
                isRevealed = true
            } else {
                withAnimation(.easeInOut(duration: duration)) {
                    isRevealed = true
                }
            }
        }
    }
}
