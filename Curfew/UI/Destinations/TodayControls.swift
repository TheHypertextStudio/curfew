import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// The two Today actions in one glass container, or the single "Turn on
/// Curfew" when Curfew is off.
struct TodayActions: View {
    var presentation: TodayPresentation
    var voice: VoicePack
    var holdDuration: TimeInterval
    var stacked: Bool
    var onTurnOn: () -> Void
    var onMoreTime: () -> Void
    var onCallItADay: () -> Void

    var body: some View {
        // No shared glass container: inside one, the ember tint of "Call it a
        // day" spreads to the plain glass of "15 more minutes" and the two read
        // as equals. Each keeps its own glass.
        Group {
            let layout = stacked
                ? AnyLayout(VStackLayout(spacing: CurfewSpacing.small))
                : AnyLayout(HStackLayout(spacing: CurfewSpacing.medium))
            layout {
                if let moreTime = presentation.moreTime {
                    MoreTimeButton(
                        moreTime: moreTime, voice: voice, holdDuration: holdDuration,
                        action: onMoreTime
                    )
                }
                if presentation.callsItADay {
                    HoldToConfirmButton(
                        voice.callItADay, holdingLabel: voice.keepHolding, symbol: .curfew,
                        duration: holdDuration, prominent: true, action: onCallItADay
                    )
                    .accessibilityHint("Locks this Mac now, until the scheduled unlock.")
                }
                if presentation.offersTurnOn {
                    Button(action: onTurnOn) {
                        // The system glass style sets its own label weight;
                        // name the button role so it matches the hold buttons.
                        Text(voice.turnOn)
                            .sundownFont(.button, size: 15)
                            .padding(.horizontal, CurfewSpacing.small)
                            .padding(.vertical, CurfewSpacing.small)
                    }
                    .buttonStyle(.horizonGlassProminent)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: presentation.moreTime)
        .animation(.smooth(duration: 0.3), value: presentation.callsItADay)
    }
}

/// "15 more minutes": hold to confirm. The count of extensions left shows
/// only while holding; "Added" confirms; with none left it says so and does
/// nothing.
struct MoreTimeButton: View {
    var moreTime: TodayPresentation.MoreTime
    var voice: VoicePack
    var holdDuration: TimeInterval
    var action: () -> Void
    @State private var justAdded = false

    var body: some View {
        switch moreTime {
        case .available(let left):
            HoldToConfirmButton(
                justAdded ? voice.added : voice.moreTime(minutes: 15),
                holdingLabel: voice.holdingWithRemaining(left),
                symbol: .moreTime, duration: holdDuration
            ) {
                action()
                justAdded = true
            }
            .accessibilityHint("Moves curfew 15 minutes later. \(left) left this week.")
            .task(id: justAdded) {
                guard justAdded else { return }
                try? await Task.sleep(for: .seconds(1.6))
                justAdded = false
            }
        case .exhausted:
            HoldToConfirmButton(
                voice.noExtensionsLeft, holdingLabel: voice.noExtensionsLeft,
                symbol: .moreTime, duration: holdDuration
            ) {}
                .disabled(true)
        }
    }
}

/// The one thing on the ground: a circle to tick, or "What is today for?" as
/// a field when the morning has not named one. Long text wraps to two lines.
struct OneThingView: View {
    var oneThing: TodayOneThing?
    var size: CGFloat
    var voice: VoicePack
    var onDone: (Bool) -> Void
    var onSave: (String) -> Bool
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if let oneThing {
            Button { onDone(!oneThing.isDone) } label: {
                HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
                    Image(systemName: oneThing.isDone
                        ? HorizonSymbol.oneThingDone.systemName : HorizonSymbol.oneThing.systemName)
                        .contentTransition(.symbolEffect(.replace))
                    Text(oneThing.text)
                        .strikethrough(oneThing.isDone)
                        .opacity(oneThing.isDone ? 0.6 : 1)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .sundownFont(.title, size: size)
                .foregroundStyle(SundownPalette.warmWhite)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.smooth(duration: 0.3), value: oneThing.isDone)
            .accessibilityLabel(oneThing.text)
            .accessibilityValue(oneThing.isDone ? "Done" : "Not done")
            .accessibilityHint(oneThing.isDone ? "Marks it not done." : "Marks it done.")
        } else {
            TextField(
                voice.gateQuestion, text: $draft,
                prompt: Text(voice.gateQuestion)
                    .foregroundStyle(SundownPalette.warmWhite.opacity(0.66))
            )
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .sundownFont(.title, size: size)
            .foregroundStyle(SundownPalette.warmWhite)
            .multilineTextAlignment(.center)
            .padding(.bottom, CurfewSpacing.small)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SundownPalette.warmWhite.opacity(fieldFocused ? 0.85 : 0.5))
                    .frame(height: 1.5)
            }
            .onSubmit {
                if onSave(draft) {
                    draft = ""
                }
            }
            .frame(maxWidth: 420)
            .accessibilityLabel(voice.gateQuestion)
            .accessibilityHint("Press Return to save it as today's one thing.")
        }
    }
}

/// The Accessibility health banner as the setup flow defines it, on its own
/// paper so it reads the same over the sky as it did over the page.
struct TodayHealthBanner: View {
    var showWarning: Bool
    var showGranted: Bool
    var onResolve: () -> Void

    var body: some View {
        Group {
            if showGranted {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CurfewTheme.accent)
                    Text("Accessibility access granted.")
                        .font(SundownType.body(14))
                        .foregroundStyle(CurfewTheme.ink)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(CurfewTheme.surfaceMuted, in: .rect(cornerRadius: 12))
                .transition(.opacity)
            } else if showWarning {
                HStack(spacing: 11) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CurfewTheme.warning)
                    Text("Curfew needs Accessibility access to block bypass shortcuts "
                        + "during lockout.")
                        .font(SundownType.body(14))
                        .foregroundStyle(CurfewTheme.ink)
                    Spacer(minLength: 12)
                    Button("Grant Access", action: onResolve)
                        .buttonStyle(.plain)
                        .font(SundownType.title(14))
                        .foregroundStyle(CurfewTheme.accent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(CurfewTheme.warning.opacity(0.13), in: .rect(cornerRadius: 12))
                .background(CurfewTheme.canvas, in: .rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 22)
    }
}
