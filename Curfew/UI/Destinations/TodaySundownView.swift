import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// The Today surface, driven by plain values so it renders live (through
/// ``TodayView``) and in the snapshot tier.
///
/// The sky holds time and voice: the countdown, "until curfew at (time)" or
/// the warning line, and the two hold-to-confirm actions just above the
/// horizon. The ground holds what the person does: the one thing.
struct TodaySundownView: View {
    var horizon: HorizonFrame = Self.previewHorizon
    var isDayRunning = false
    var presentation: TodayPresentation
    var oneThing: TodayOneThing?
    var voice: VoicePack = .standard
    var holdDuration: TimeInterval = CurfewAppModel.extensionConfirmationHoldSeconds
    var showAccessibilityWarning = false
    /// True for the brief window after Accessibility trust is granted.
    var showAccessibilityGranted = false
    var onTurnOn: () -> Void = {}
    var onMoreTime: () -> Void = {}
    var onCallItADay: () -> Void = {}
    var onOneThingDone: (Bool) -> Void = { _ in }
    var onSaveOneThing: (String) -> Bool = { _ in true }
    var onResolveAccessibility: () -> Void = {}
    @Environment(\.horizonPalette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            // Drawn over the same area as the text, so the sky is quieted
            // exactly behind it; the extension effect carries it on beneath
            // the system sidebar.
            HorizonSkyView(
                today: horizon, isDayRunning: isDayRunning, palette: palette,
                metrics: TodayMetrics.window
            )
            .backgroundExtensionEffect()
            .ignoresSafeArea(.container, edges: .vertical)
            GeometryReader { proxy in
                layout(in: proxy.size)
            }
            .ignoresSafeArea(.container, edges: .vertical)
            TodayHealthBanner(
                showWarning: showAccessibilityWarning,
                showGranted: showAccessibilityGranted,
                onResolve: onResolveAccessibility
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .animation(.easeOut(duration: 0.4), value: showAccessibilityGranted)
        .animation(.easeOut(duration: 0.4), value: showAccessibilityWarning)
    }

    private func layout(in size: CGSize) -> some View {
        let metrics = TodayMetrics.window(size)
        let skyHeight = size.height * (1 - HorizonGeometry.horizon)
        return VStack(spacing: 0) {
            TodayHero(
                presentation: presentation, metrics: metrics, voice: voice,
                holdDuration: holdDuration, onTurnOn: onTurnOn, onMoreTime: onMoreTime,
                onCallItADay: onCallItADay
            )
            .padding(.bottom, metrics.actionsToHorizon)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .frame(height: skyHeight)

            Group {
                if presentation.showsOneThing {
                    OneThingView(
                        oneThing: oneThing, size: metrics.oneThing, voice: voice,
                        onDone: onOneThingDone, onSave: onSaveOneThing
                    )
                    .frame(maxWidth: metrics.groundWidth)
                    .accessibilitySortPriority(2)
                }
            }
            .padding(.top, metrics.horizonToGround)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, CurfewSpacing.xLarge)
    }
}

/// Sizes for one Today surface, from the prototype's proportions: numerals
/// 13.5% of the width, the line and buttons near the horizon, the one thing
/// a little below it.
struct TodayMetrics: Equatable {
    var numeral: CGFloat
    var statement: CGFloat
    var line: CGFloat
    var oneThing: CGFloat
    /// Numerals to the line under them. Negative where the numerals' descender
    /// space would otherwise open a gap wider than the prototype's.
    var headlineToLine: CGFloat
    /// The line to the buttons.
    var lineToActions: CGFloat
    /// The buttons' bottom edge to the horizon.
    var actionsToHorizon: CGFloat
    /// The horizon to the one thing.
    var horizonToGround: CGFloat
    var groundWidth: CGFloat
    /// Stacks the two actions vertically where the width is tight.
    var stacksActions: Bool

    static func window(_ size: CGSize) -> TodayMetrics {
        let numeral = min(max(size.width * 0.135, 64), min(size.height * 0.2, 150))
        return TodayMetrics(
            numeral: numeral,
            statement: (numeral * 0.34).rounded(),
            line: 15,
            oneThing: 19,
            // The numerals' line box carries their descender; pull the line up
            // into it so the visible gap is the prototype's eighth of an em.
            headlineToLine: -(numeral * 0.1).rounded(),
            lineToActions: size.height < 560 ? CurfewSpacing.xLarge : CurfewSpacing.xxLarge,
            actionsToHorizon: size.height < 560 ? CurfewSpacing.xLarge : CurfewSpacing.xxLarge,
            horizonToGround: min(max(size.height * 0.095, CurfewSpacing.xLarge), 72),
            groundWidth: min(560, size.width * 0.62),
            stacksActions: false
        )
    }

    /// The menu bar popover: the same order at a third of the scale.
    static let popover = TodayMetrics(
        numeral: 52,
        statement: 22,
        line: 13,
        oneThing: 15,
        headlineToLine: -5,
        lineToActions: CurfewSpacing.large,
        actionsToHorizon: CurfewSpacing.large,
        horizonToGround: CurfewSpacing.xLarge,
        groundWidth: 300,
        stacksActions: true
    )
}

/// The sky's half of Today: the countdown or a statement, the line under it
/// and the actions. Shared by the window and the menu bar popover.
struct TodayHero: View {
    var presentation: TodayPresentation
    var metrics: TodayMetrics
    var voice: VoicePack
    var holdDuration: TimeInterval
    var onTurnOn: () -> Void
    var onMoreTime: () -> Void
    var onCallItADay: () -> Void

    var body: some View {
        let headlineGap = presentation.isCountdown ? metrics.headlineToLine : CurfewSpacing.small
        VStack(spacing: 0) {
            VStack(spacing: headlineGap) {
                headline
                if let line = presentation.line {
                    TodayLine(text: line, symbol: presentation.lineSymbol, size: metrics.line)
                }
            }

            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.spokenTime)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilitySortPriority(3)

            TodayActions(
                presentation: presentation, voice: voice, holdDuration: holdDuration,
                stacked: metrics.stacksActions, onTurnOn: onTurnOn, onMoreTime: onMoreTime,
                onCallItADay: onCallItADay
            )
            .padding(.top, metrics.lineToActions)
            .accessibilitySortPriority(1)
        }
        // Nothing is drawn behind the text: the sky beneath it is quieted
        // (`HorizonSkyView(today:)`), so it reads at every moment.
        .foregroundStyle(SundownPalette.warmWhite)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var headline: some View {
        switch presentation.headline {
        case .countdown(let value):
            TodayCountdown(value: value, size: metrics.numeral)
        case .statement(let text):
            Text(text)
                .sundownFont(.headline, size: metrics.statement)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The countdown numerals. They roll as they change, counting down, and swap
/// without moving under Reduce Motion.
struct TodayCountdown: View {
    var value: String
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(value)
            .sundownFont(.display, size: size)
            .monospacedDigit()
            .tracking(-0.03 * size)
            // Tracking also trails the last figure; shift it back so the
            // figures, not their box, sit on the centre line.
            .offset(x: -0.015 * size)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: value)
    }
}

/// A status line led by its symbol at the text's weight.
struct TodayLine: View {
    var text: String
    var symbol: HorizonSymbol?
    var size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.4) {
            if let symbol {
                symbol.image
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sundownFont(.strong, size: size)
        .contentTransition(.opacity)
    }
}

extension TodaySundownView {
    /// Mid-afternoon on a 7 AM to 6 PM day, for previews and the snapshot tier.
    static var previewHorizon: HorizonFrame {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let afternoon = calendar.date(bySettingHour: 15, minute: 30, second: 0, of: today) ?? today
        return HorizonMoment.unscheduled(now: afternoon).frame
    }
}
