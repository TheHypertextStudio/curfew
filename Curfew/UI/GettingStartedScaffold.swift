import SwiftUI

/// One button in setup's action row.
struct SetupAction: Equatable {
    var title: String
    var isEnabled = true
    /// Said by VoiceOver and shown as the tooltip.
    var hint: String?
    var perform: () -> Void

    static func == (lhs: SetupAction, rhs: SetupAction) -> Bool {
        lhs.title == rhs.title && lhs.isEnabled == rhs.isEnabled && lhs.hint == rhs.hint
    }
}

/// How the word "Curfew" shows above the heading.
enum SetupWordmark: Equatable {
    /// Not on this screen.
    case hidden
    /// Large and alone, as the welcome's title card.
    case title
    /// Small, in its place above the heading.
    case mark
}

/// The four places every setup screen shares, top to bottom: the mark, the
/// heading, the content and the buttons.
///
/// The places never move. When one screen replaces another, each place swaps
/// its content where it stands: the old leaves at once and the new rises in,
/// heading first, then content, then buttons, so nothing jumps. Arrivals wait
/// `delay` seconds for the sky.
struct GettingStartedScaffold<Content: View>: View {
    var scene: SetupScene
    var headline: String?
    var wordmark: SetupWordmark
    var secondary: SetupAction?
    var primary: SetupAction?
    var delay: Double
    var animates: Bool
    @ViewBuilder var content: Content
    @Environment(\.setupMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            mark
                .frame(height: metrics.markSlot)
            heading
                .frame(maxWidth: .infinity, minHeight: metrics.headlineSlot, alignment: .top)
                .padding(.top, GettingStartedLayout.spacing4)
            content
                .id(scene)
                .transition(.setupArrival(delay: delay + 0.08, animates: animates))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            actions
                .frame(height: metrics.actionSlot)
        }
    }

    private var mark: some View {
        Text(GettingStartedCopy.wordmark)
            .sundownFont(.title, size: metrics.body)
            .scaleEffect(wordmark == .title ? 3.4 : 1)
            // From its place at the top of the band to the middle of it.
            .offset(y: wordmark == .title ? (metrics.bandHeight - metrics.markSlot) / 2 : 0)
            .opacity(wordmark == .hidden ? 0 : 1)
            .animation(animates ? .spring(duration: 1.2, bounce: 0.1) : nil, value: wordmark)
            // The heading names Curfew once there is one.
            .accessibilityHidden(wordmark != .title)
    }

    private var heading: some View {
        ZStack(alignment: .top) {
            if let headline {
                Text(headline)
                    .setupHeadline(metrics)
                    .id(headline)
                    .transition(.setupArrival(delay: delay, animates: animates))
            }
        }
    }

    /// The row is in the same place on every screen. Between screens it
    /// leaves and arrives with the rest, so no button is left standing alone
    /// while the sky moves. Within a screen a button keeps its identity: its
    /// title changes in place and the row re-centres smoothly when one comes
    /// or goes.
    private var actions: some View {
        HStack(spacing: GettingStartedLayout.spacing12) {
            if let secondary {
                button(secondary)
                    .buttonStyle(GettingStartedSecondaryButtonStyle())
                    .keyboardShortcut(primary == nil ? .defaultAction : nil)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if let primary {
                button(primary)
                    .buttonStyle(GettingStartedPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(
            animates ? .spring(duration: 0.55, bounce: 0.15) : .easeOut(duration: 0.2),
            value: [secondary, primary]
        )
        .id(scene)
        .transition(.setupArrival(delay: delay + 0.16, animates: animates))
    }

    private func button(_ action: SetupAction) -> some View {
        Button(action: action.perform) {
            Text(action.title)
                .contentTransition(.interpolate)
        }
        .disabled(!action.isEnabled)
        .help(action.hint ?? "")
        .accessibilityHint(action.hint ?? "")
    }
}
