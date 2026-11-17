import AppKit
import CurfewAtmosphere
import CurfewKit
import Observation
import SwiftUI

/// Which warnings show the notice. The thirty and fifteen minute notices can
/// be dismissed without silencing the next stage; the last five minutes stay.
struct WarningNoticeVisibility {
    private var dismissedStage: WarningStage?

    static func isDismissible(_ stage: WarningStage) -> Bool {
        stage == .thirtyMinutes || stage == .fifteenMinutes
    }

    func shouldShow(_ stage: WarningStage) -> Bool {
        switch stage {
        case .thirtyMinutes, .fifteenMinutes:
            stage != dismissedStage
        case .fiveMinutes, .twoMinutes, .oneMinute:
            true
        case .none, .lockout:
            false
        }
    }

    mutating func dismiss(_ stage: WarningStage) {
        dismissedStage = stage
    }

    mutating func reset() {
        dismissedStage = nil
    }
}

/// The notice's words: the countdown to curfew and the stage line.
enum WarningNoticeContent {
    /// Minutes and seconds to curfew, "4:59".
    static func countdown(secondsRemaining: Int) -> String {
        let seconds = max(0, secondsRemaining)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// The countdown as VoiceOver reads it, "2 minutes to curfew".
    static func spokenCountdown(secondsRemaining: Int, voice: VoicePack = .standard) -> String {
        voice.warningTitle(minutes: Int((Double(max(0, secondsRemaining)) / 60).rounded(.up)))
    }
}

/// What every display's notice shows. The windows are built once and observe
/// this; a tick changes values, never the windows.
@Observable
@MainActor
final class WarningNoticeState {
    var stage: WarningStage = .none
    var curfew: Date?
    var fallbackSeconds = 0
    /// The demo fixture's fixed clock; nil counts down from the wall clock.
    var pinnedNow: Date?
    /// The voice the stage line is spoken in.
    var voice = VoicePack.standard
    /// The palette its solid panel takes under Reduce Transparency.
    var palette = HorizonPalette.standard
    @ObservationIgnored var onDismiss: () -> Void = {}
}

/// Presents the warning notice on every display without activating Curfew or
/// stealing focus from the person's current full-screen task.
@MainActor
final class WarningNoticeCoordinator {
    static let windowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless, .nonactivatingPanel],
        level: .screenSaver,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    static let size = CGSize(width: 340, height: 104)

    private var windows: [ObjectIdentifier: NSPanel] = [:]
    private var visibility = WarningNoticeVisibility()
    private let state = WarningNoticeState()

    init() {
        state.onDismiss = { [weak self] in
            guard let self else { return }
            dismiss(stage: state.stage)
        }
    }

    func update(
        stage: WarningStage, curfew: Date?, minutesRemaining: Int, voice: VoicePack = .standard,
        palette: HorizonPalette = .standard, pinnedNow: Date? = nil
    ) {
        guard visibility.shouldShow(stage) else {
            hide()
            return
        }
        let stageChanged = state.stage != stage
        state.stage = stage
        state.curfew = curfew
        state.fallbackSeconds = max(0, minutesRemaining) * 60
        if state.pinnedNow != pinnedNow {
            state.pinnedNow = pinnedNow
        }
        if state.voice != voice {
            state.voice = voice
        }
        if state.palette != palette {
            state.palette = palette
        }

        let screens = NSScreen.screens
        let connected = Set(screens.map(ObjectIdentifier.init))
        for key in windows.keys where !connected.contains(key) {
            windows.removeValue(forKey: key)?.orderOut(nil)
        }
        for screen in screens {
            let key = ObjectIdentifier(screen)
            let frame = noticeFrame(for: screen)
            if let window = windows[key] {
                if window.frame != frame {
                    window.setFrame(frame, display: true)
                }
                if stageChanged || !window.isVisible {
                    window.orderFrontRegardless()
                }
                continue
            }
            let window = makeWindow(frame: frame, screen: screen)
            window.orderFrontRegardless()
            windows[key] = window
        }
    }

    func reset() {
        visibility.reset()
        hide()
    }

    func hide() {
        for window in windows.values {
            window.orderOut(nil)
        }
        windows.removeAll()
        state.stage = .none
    }

    private func makeWindow(frame: CGRect, screen: NSScreen) -> NSPanel {
        let window = NSPanel(
            contentRect: frame,
            styleMask: Self.windowConfiguration.styleMask,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = Self.windowConfiguration.level
        window.ignoresMouseEvents = Self.windowConfiguration.ignoresMouseEvents
        window.collectionBehavior = Self.windowConfiguration.collectionBehavior
        window.isMovable = Self.windowConfiguration.isMovable
        window.hidesOnDeactivate = Self.windowConfiguration.hidesOnDeactivate
        window.becomesKeyOnlyIfNeeded = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: WarningNoticeView(state: state))
        return window
    }

    private func dismiss(stage: WarningStage) {
        visibility.dismiss(stage)
        hide()
    }

    private func noticeFrame(for screen: NSScreen) -> CGRect {
        let margin = CurfewSpacing.xLarge
        return CGRect(
            x: screen.visibleFrame.maxX - Self.size.width - margin,
            y: screen.visibleFrame.maxY - Self.size.height - margin,
            width: Self.size.width,
            height: Self.size.height
        )
    }
}

/// The glass notice: the sunset symbol, the countdown to curfew and the stage
/// line. The countdown updates itself each second; the window never rebuilds.
struct WarningNoticeView: View {
    let state: WarningNoticeState
    var now: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = now ?? state.pinnedNow ?? context.date
            let seconds = state.curfew.map { Int($0.timeIntervalSince(date).rounded(.up)) }
                ?? state.fallbackSeconds
            content(seconds: seconds)
        }
    }

    private func content(seconds: Int) -> some View {
        HStack(alignment: .center, spacing: CurfewSpacing.medium) {
            HorizonSymbol.curfew.image
                .font(.system(size: 22, weight: .medium))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CurfewSpacing.xSmall) {
                Text(WarningNoticeContent.countdown(secondsRemaining: seconds))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: seconds)
                    .accessibilityLabel(WarningNoticeContent
                        .spokenCountdown(secondsRemaining: seconds))
                    .accessibilityIdentifier("warning-countdown")
                if let line = state.voice.stageLine(state.stage) {
                    Text(line)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SundownPalette.supportingText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if WarningNoticeVisibility.isDismissible(state.stage) {
                Button(action: state.onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(SundownPalette.supportingText)
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("warning-dismiss")
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .foregroundStyle(SundownPalette.warmWhite)
        .padding(.horizontal, CurfewSpacing.large)
        .padding(.vertical, CurfewSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .nightPanel()
        .environment(\.horizonPalette, state.palette)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("early-warning-notice")
    }
}
