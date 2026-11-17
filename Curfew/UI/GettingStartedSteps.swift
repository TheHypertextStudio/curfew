import AppKit
import CurfewKit
import SwiftUI

/// Where the welcome is in its opening: the title card, the small mark alone,
/// one of the three captions, or the resting sentence with its button.
enum SetupIntroPhase: Equatable {
    case title
    case settled
    case caption(Int)
    case rest
}

// MARK: Welcome

/// The sentence between the welcome's heading and its buttons. It keeps its
/// space while the welcome's day plays, so nothing around it moves.
struct GettingStartedWelcomeContent: View {
    let isRest: Bool
    @Environment(\.setupMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(GettingStartedCopy.welcomeLine)
            .setupBody(metrics.body)
            .opacity(isRest ? 1 : 0)
            .offset(y: isRest || reduceMotion ? 0 : 14)
            .blur(radius: isRest || reduceMotion ? 0 : 6)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(duration: 0.75, bounce: 0.12).delay(0.15),
                value: isRest
            )
            .accessibilityHidden(!isRest)
    }
}

// MARK: Times

/// One time, large, with a round button either side. The buttons move it a
/// quarter hour; the arrow keys and VoiceOver move it five minutes (Shift an
/// hour); dragging it up or down scrubs it. The time has a fixed width, so the
/// buttons never move as the digits change.
struct GettingStartedTimeControl: View {
    @Binding var draft: SetupScheduleDraft
    let field: SetupScheduleDraft.Field
    let label: String
    @Environment(\.setupMetrics) private var metrics
    @State private var dragStart: SetupScheduleDraft?

    private var minutes: Int {
        field == .curfew ? draft.lockMinutes : draft.unlockMinutes
    }

    private var date: Date {
        Self.date(minutes: minutes)
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// A time in the locale's format, with the AM or PM mark set smaller.
    private func timeText(_ date: Date) -> AttributedString {
        var text = date.formatted(Date.FormatStyle().hour().minute().attributed)
        for run in text.runs where run.dateField == .amPM {
            text[run.range].font = SundownType.figure((metrics.numeral * 0.36).rounded())
        }
        return text
    }

    private func step(_ change: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            draft = draft.adjusting(field, by: change)
        }
    }

    var body: some View {
        HStack(spacing: GettingStartedLayout.spacing16) {
            Button { step(-15) } label: { Image(systemName: "minus") }
                .buttonStyle(GettingStartedStepButtonStyle())
                .accessibilityLabel("\(GettingStartedCopy.earlier), \(label)")
            ZStack {
                // The widest time there is, to hold the width.
                Text(timeText(Self.date(minutes: 22 * 60 + 58)))
                    .hidden()
                Text(timeText(date))
                    .contentTransition(.numericText(value: Double(minutes)))
            }
            .sundownFont(.figure, size: metrics.numeral)
            .monospacedDigit()
            .fixedSize()
            .focusable()
            .onKeyPress(keys: [.upArrow, .rightArrow]) { press in
                step(press.modifiers.contains(.shift) ? 60 : 5)
                return .handled
            }
            .onKeyPress(keys: [.downArrow, .leftArrow]) { press in
                step(press.modifiers.contains(.shift) ? -60 : -5)
                return .handled
            }
            .gesture(scrub)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(date.formatted(date: .omitted, time: .shortened))
            .accessibilityAdjustableAction { direction in
                step(direction == .increment ? 5 : -5)
            }
            Button { step(15) } label: { Image(systemName: "plus") }
                .buttonStyle(GettingStartedStepButtonStyle())
                .accessibilityLabel("\(GettingStartedCopy.later), \(label)")
        }
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? draft
                dragStart = start
                let change = Int((-value.translation.height / 6).rounded()) * 5
                draft = start.adjusting(field, by: change)
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// The one question: when the day ends. The days and the unlock time are
/// stated as defaults and changed on their own screen.
struct GettingStartedScheduleContent: View {
    @Binding var draft: SetupScheduleDraft
    let onChange: () -> Void
    @Environment(\.setupMetrics) private var metrics

    var body: some View {
        VStack(spacing: GettingStartedLayout.spacing8) {
            GettingStartedTimeControl(
                draft: $draft, field: .curfew, label: GettingStartedCopy.curfewLabel
            )
            HStack(spacing: GettingStartedLayout.spacing12) {
                Text(GettingStartedCopy.defaultsLine(
                    days: draft.workingDays, unlockMinutes: draft.unlockMinutes
                ))
                .sundownFont(.body, size: metrics.small)
                Button(GettingStartedCopy.change, action: onChange)
                    .buttonStyle(GettingStartedSecondaryButtonStyle(compact: true))
                    .accessibilityHint(GettingStartedCopy.changeHint)
            }
        }
    }
}

/// When this Mac opens again, and which days lock. Reached from "Change".
struct GettingStartedMorningContent: View {
    @Binding var draft: SetupScheduleDraft
    @Environment(\.setupMetrics) private var metrics

    private var calendar: Calendar {
        .current
    }

    /// Weekdays in the locale's order.
    private var orderedDays: [Weekday] {
        let first = calendar.firstWeekday
        return (0 ..< 7).compactMap { Weekday(rawValue: (first - 1 + $0) % 7 + 1) }
    }

    var body: some View {
        VStack(spacing: GettingStartedLayout.spacing8) {
            GettingStartedTimeControl(
                draft: $draft, field: .unlock, label: GettingStartedCopy.unlockLabel
            )
            HStack(spacing: GettingStartedLayout.spacing8) {
                ForEach(orderedDays) { day in
                    Toggle(isOn: binding(for: day)) {
                        Text(calendar.veryShortWeekdaySymbols[day.rawValue - 1])
                    }
                    .toggleStyle(GettingStartedChipStyle())
                    .accessibilityLabel(calendar.weekdaySymbols[day.rawValue - 1])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(GettingStartedCopy.daysLabel)
            // Always in its place, shown only when there is something to say.
            Text(GettingStartedCopy.pickADay)
                .sundownFont(.body, size: metrics.small)
                .opacity(draft.workingDays.isEmpty ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: draft.workingDays.isEmpty)
                .accessibilityHidden(!draft.workingDays.isEmpty)
        }
    }

    private func binding(for day: Weekday) -> Binding<Bool> {
        Binding(
            get: { draft.workingDays.contains(day) },
            set: { isOn in
                if isOn {
                    draft.workingDays.insert(day)
                } else {
                    draft.workingDays.remove(day)
                }
            }
        )
    }
}
