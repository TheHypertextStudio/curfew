import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// What the theme editor's preview shows: the moment where the line or the
/// choice being changed appears.
enum RestAppearancePreviewSubject: Hashable, CaseIterable {
    /// The lock at night: the clock, the headline and the unlock line.
    case lock
    /// The idle scene the screen saver shows: the sky and the clock.
    case screenSaver
    /// Today in the last half hour, with the warning notice.
    case warning
    /// The Sunrise gate.
    case sunrise

    var title: String {
        switch self {
        case .lock: "Lock"
        case .screenSaver: "Screen saver"
        case .warning: "Warning"
        case .sunrise: "Sunrise"
        }
    }

    /// Where a line the person can rewrite is seen.
    init(_ line: VoicePack.Line) {
        switch line {
        case .lockedHeadline, .overrideQuestion: self = .lock
        case .thirtyMinutes, .fifteenMinutes, .fiveMinutes, .lastMinute: self = .warning
        case .sunriseGreeting, .sunriseQuestion: self = .sunrise
        }
    }
}

extension RestAppearancePreviewSubject {
    /// The warning stage a rewritten line belongs to.
    static func stage(for line: VoicePack.Line) -> WarningStage? {
        switch line {
        case .thirtyMinutes: .thirtyMinutes
        case .fifteenMinutes: .fifteenMinutes
        case .fiveMinutes: .fiveMinutes
        case .lastMinute: .oneMinute
        default: nil
        }
    }

    /// Minutes before curfew the preview stands at for a warning stage.
    static func minutes(before stage: WarningStage) -> Int {
        switch stage {
        case .thirtyMinutes: 30
        case .fiveMinutes, .twoMinutes: 5
        case .oneMinute: 1
        default: 15
        }
    }
}

/// The real screens, drawn still at full size from the person's current
/// theme and scaled into the pane: the lock and the screen saver through
/// ``RestScreenView``, the warning through Today and the warning notice, and
/// Sunrise through its preview scene. Nothing in it can be pressed.
struct RestAppearancePreview: View {
    @Environment(CurfewAppModel.self) private var model
    let subject: RestAppearancePreviewSubject
    var warningStage: WarningStage = .fifteenMinutes

    static let canvas = CGSize(width: 1440, height: 900)
    static let scale: CGFloat = 0.42

    @State private var display = Self.visibleDisplay()
    @State private var scene = LockScene()
    @State private var notice = WarningNoticeState()

    var body: some View {
        screen
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .scaleEffect(Self.scale, anchor: .topLeading)
            .frame(
                width: Self.canvas.width * Self.scale,
                height: Self.canvas.height * Self.scale,
                alignment: .topLeading
            )
            .clipShape(RoundedRectangle(cornerRadius: CurfewRadius.control, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RestAppearancePreviewDescription.text(
                subject: subject, appearance: model.restAppearance,
                warningStage: warningStage, night: night
            ))
            .accessibilityIdentifier("rest-appearance-preview")
    }

    private var night: RestScreenPreview {
        RestScreenPreview.tonight(
            subject == .screenSaver ? .screenSaver : .lock, near: model.currentTime
        )
    }

    @ViewBuilder
    private var screen: some View {
        switch subject {
        case .lock, .screenSaver:
            RestScreenView(model: model, display: display, scene: scene, preview: night)
                .onAppear { scene.settle(at: night.now) }
        case .warning:
            warning
        case .sunrise:
            SunrisePreviewScene()
        }
    }

    /// Today at the stage's minutes before a 6 PM curfew, with the notice
    /// where it floats over the desktop.
    private var warning: some View {
        let curfew = night.curfew
        let minutes = RestAppearancePreviewSubject.minutes(before: warningStage)
        let now = curfew.addingTimeInterval(-Double(minutes * 60) + 1)
        let moment = HorizonMoment(
            now: now, dayStart: curfew.addingTimeInterval(-11 * 3600), curfew: curfew,
            nextUnlock: night.unlock
        )
        let presentation = TodayPresentation.resolve(TodaySituation(
            setupComplete: true, enforcing: true, phase: .warning,
            warningStage: warningStage, minutesRemaining: minutes, upcomingCurfew: curfew,
            unlockDate: nil, overrideEnds: nil, canRequestExtension: true,
            extensionsRemaining: 2, canCallItADay: true
        ), voice: model.voice)
        return TodaySundownView(
            horizon: moment.frame, presentation: presentation,
            oneThing: TodayOneThing(text: "Ship the billing migration", isDone: false),
            voice: model.voice
        )
        .overlay(alignment: .topTrailing) {
            WarningNoticeView(state: notice, now: now)
                .environment(\.colorScheme, .dark)
                .frame(
                    width: WarningNoticeCoordinator.size.width,
                    height: WarningNoticeCoordinator.size.height
                )
                .padding(CurfewSpacing.xLarge)
        }
        .onAppear { syncNotice(curfew: curfew) }
        .onChange(of: warningStage) { syncNotice(curfew: curfew) }
        .onChange(of: model.restAppearance) { syncNotice(curfew: curfew) }
    }

    private func syncNotice(curfew: Date) {
        notice.stage = warningStage
        notice.curfew = curfew
        notice.voice = model.voice
        notice.palette = model.horizonPalette
    }

    private static func visibleDisplay() -> RestDisplayPresentation {
        let display = RestDisplayPresentation()
        display.isVisible = true
        return display
    }
}

/// What VoiceOver hears for the preview: the screen, the sky and the words
/// on it, so the theme can be judged without seeing it.
enum RestAppearancePreviewDescription {
    static func text(
        subject: RestAppearancePreviewSubject, appearance: RestAppearancePreferences,
        warningStage: WarningStage, night: RestScreenPreview
    ) -> String {
        let voice = appearance.voicePack
        let sky = appearance.background == .atmosphere
            ? "the \(RestAppearanceCopy.paletteName(appearance.palette)) sky"
            : RestAppearanceCopy.backgroundName(appearance.background)
        let clock = "a \(RestAppearanceCopy.clockName(appearance.clockStyle).lowercased()) clock"
        switch subject {
        case .lock:
            return "Preview of the lock over \(sky), with \(clock): "
                + "\(VoicePack.time(night.now)), \(voice.lockedHeadline) "
                + "\(voice.unlocksAt(night.unlock))."
        case .screenSaver:
            let words = appearance.saverMessageEnabled && !appearance.message.isEmpty
                ? " and your words, \(appearance.message)" : ""
            return "Preview of the screen saver over \(sky), with \(clock) "
                + "\(RestAppearanceCopy.positionPhrase(appearance.clockPosition))\(words)."
        case .warning:
            let minutes = RestAppearancePreviewSubject.minutes(before: warningStage)
            return "Preview of Today \(minutes) "
                + "\(minutes == 1 ? "minute" : "minutes") before curfew: "
                + "\(voice.stageLine(warningStage) ?? "")"
        case .sunrise:
            return "Preview of Sunrise: \(voice.gateHeadline) \(voice.gateQuestion)"
        }
    }
}
