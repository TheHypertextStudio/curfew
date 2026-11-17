import AppKit
import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// The Sunrise screen as the person's current settings would show it on their
/// next working morning: the morning sky, the small clock and the gate's
/// first page. Still: it never arms anything, takes focus or records an
/// answer. The Settings pane shows it small; "Preview Sunrise" shows it full size.
struct SunrisePreviewScene: View {
    @Environment(CurfewAppModel.self) private var model

    /// The gate's first page as configured, with last night's real note when
    /// there is one and a sample otherwise, so the note step can be seen.
    private var preview: SunriseGateView.Preview {
        let pages = SunriseGate.pages(
            steps: model.sunriseSteps,
            morningPrompts: model.reflectionConfiguration.morningPrompts,
            lastNightNote: model.sunriseLastNightNote ?? "pick up where you stopped.",
            question: model.voice.gateQuestion
        )
        return SunriseGateView.Preview(page: pages.first, isLastPage: pages.count <= 1)
    }

    var body: some View {
        let unlock = model.sunrisePreviewUnlock
        let moment = HorizonMoment(
            now: unlock.addingTimeInterval(4 * 60),
            dayStart: unlock.addingTimeInterval(-24 * 3600),
            curfew: unlock.addingTimeInterval(-13 * 3600),
            nextUnlock: unlock
        )
        GeometryReader { geometry in
            ZStack {
                HorizonSkyView(frame: moment.frame, isDayRunning: false)
                ScrollView {
                    VStack(spacing: 18) {
                        Text(unlock.addingTimeInterval(4 * 60), style: .time)
                            .font(.system(
                                size: 64, weight: .semibold,
                                design: model.restAppearance.clockStyle.fontDesign
                            ))
                            .monospacedDigit()
                            .foregroundStyle(SundownPalette.warmWhite)
                        SunriseGateView(preview: preview)
                    }
                    .padding(32)
                    .frame(width: geometry.size.width)
                }
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
            }
        }
        .allowsHitTesting(false)
    }
}

extension CurfewAppModel {
    /// The next scheduled unlock, or 7:00 AM tomorrow when none is scheduled.
    var sunrisePreviewUnlock: Date {
        if let plan = sunriseWakePlan {
            return plan.holdUntil.addingTimeInterval(-300)
        }
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentTime) ?? currentTime
        let rule = settings.schedule.rule(for: tomorrow, calendar: calendar)
        let minutes = rule.isDayOff ? 7 * 60 : rule.unlockMinutes % (24 * 60)
        return calendar.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: tomorrow
        ) ?? tomorrow
    }
}

/// Shows ``SunrisePreviewScene`` full size in an ordinary window. It never
/// covers other windows at the lock's level, arms enforcement or records an
/// answer, and closes with its button, Escape or the window's close button.
@MainActor
enum SunrisePreviewWindow {
    private static var window: NSWindow?

    static func show(model: CurfewAppModel) {
        window?.close()
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: frame, styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Sunrise preview"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SunrisePreviewFrame {
            Self.window?.close()
        }.environment(model).curfewTheme(model))
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        Self.window = window
    }
}

private struct SunrisePreviewFrame: View {
    let close: () -> Void

    var body: some View {
        SunrisePreviewScene()
            .overlay(alignment: .topTrailing) {
                Button("Close preview", action: close)
                    .buttonStyle(.horizonGlass)
                    .keyboardShortcut(.cancelAction)
                    .padding(CurfewSpacing.xLarge)
            }
            .ignoresSafeArea()
    }
}
