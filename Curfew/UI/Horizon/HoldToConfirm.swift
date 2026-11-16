import SwiftUI

/// The timing of a hold to confirm, separate from the view so it can be
/// tested without UI. Pressing starts the fill; reaching `duration` confirms
/// once; letting go early cancels.
struct HoldToConfirmTimer: Equatable {
    let duration: TimeInterval
    private(set) var pressedAt: Date?
    private(set) var isConfirmed = false

    init(duration: TimeInterval) {
        self.duration = max(duration, 0.05)
    }

    var isHolding: Bool {
        pressedAt != nil && !isConfirmed
    }

    /// Starts a hold. A repeated press while holding (key repeat) is ignored.
    mutating func press(at date: Date) {
        guard pressedAt == nil else { return }
        isConfirmed = false
        pressedAt = date
    }

    /// Ends the hold. Before the duration this cancels; after it, the
    /// confirmation stands until ``reset()``.
    mutating func release(at _: Date) {
        pressedAt = nil
    }

    /// The fill from 0 to 1.
    func progress(at date: Date) -> Double {
        if isConfirmed {
            return 1
        }
        guard let pressedAt else { return 0 }
        return min(max(date.timeIntervalSince(pressedAt) / duration, 0), 1)
    }

    /// Advances the hold; returns true exactly once, when it confirms.
    mutating func update(at date: Date) -> Bool {
        guard isHolding, progress(at: date) >= 1 else { return false }
        isConfirmed = true
        return true
    }

    /// Confirms without a hold, for VoiceOver and other assistive actions.
    /// Returns true if this call confirmed.
    mutating func confirmImmediately() -> Bool {
        guard !isConfirmed else { return false }
        isConfirmed = true
        return true
    }

    /// Back to rest, ready for the next hold.
    mutating func reset() {
        pressedAt = nil
        isConfirmed = false
    }
}

/// A glass capsule that confirms only when held. It fills while held, shows
/// `holdingLabel` during the hold, and confirms at `duration`. Space or Return
/// held while focused does the same; VoiceOver's default action confirms
/// immediately. Confirmation gives sensory feedback.
struct HoldToConfirmButton: View {
    var label: String
    var holdingLabel: String
    var symbol: HorizonSymbol?
    var duration: TimeInterval = 1.1
    var prominent = false
    var action: () -> Void

    @State private var timer: HoldToConfirmTimer
    @State private var confirmations = 0
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        _ label: String, holdingLabel: String, symbol: HorizonSymbol? = nil,
        duration: TimeInterval = 1.1, prominent: Bool = false, action: @escaping () -> Void
    ) {
        self.label = label
        self.holdingLabel = holdingLabel
        self.symbol = symbol
        self.duration = duration
        self.prominent = prominent
        self.action = action
        _timer = State(initialValue: HoldToConfirmTimer(duration: duration))
    }

    var body: some View {
        let look = HorizonGlassLook.resolve(
            reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased
        )
        TimelineView(.animation(paused: !timer.isHolding)) { context in
            content(progress: timer.progress(at: context.date))
        }
        .horizonGlassBackground(in: Capsule(), look: look, prominent: prominent)
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.45)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in begin() }
                .onEnded { _ in end() }
        )
        .focusable(isEnabled)
        .focused($isFocused)
        .onKeyPress(keys: [.space, .return], phases: [.down, .up]) { press in
            if press.phase == .up {
                end()
            } else {
                begin()
            }
            return .handled
        }
        .task(id: timer.isHolding) {
            while timer.isHolding, !Task.isCancelled {
                if timer.update(at: Date()) {
                    confirm()
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .sensoryFeedback(.levelChange, trigger: confirmations)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled else { return }
            timer.reset()
            if timer.confirmImmediately() {
                confirm()
            }
        }
    }

    private func content(progress: Double) -> some View {
        HStack(spacing: CurfewSpacing.small) {
            if let symbol {
                symbol.image
            }
            Text(timer.isHolding ? holdingLabel : label)
                .contentTransition(.opacity)
        }
        .sundownFont(.button, size: 15)
        .padding(.horizontal, CurfewSpacing.large)
        .padding(.vertical, CurfewSpacing.medium)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(SundownPalette.warmWhite.opacity(0.22))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .clipShape(Capsule())
    }

    private func begin() {
        guard isEnabled, !timer.isHolding else { return }
        if timer.isConfirmed {
            timer.reset()
        }
        timer.press(at: Date())
    }

    private func end() {
        timer.release(at: Date())
        if timer.isConfirmed {
            timer.reset()
        }
    }

    private func confirm() {
        confirmations += 1
        action()
    }
}
