import CurfewKit
#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewAtmosphere
    import SwiftUI
    import XCTest

    /// The theme editor and the surfaces a theme changes, written to
    /// `build/screenshots/curfew-theme-*.png` for review: the Rest screen pane
    /// in light and dark with each palette and with "Your own words" open; the
    /// lock in each built-in voice; and every palette on the bare sky at day,
    /// last hour, dusk and night, on Today, on the lock and on Sunrise. The
    /// headless rasteriser draws the CPU reference sky and no Liquid Glass,
    /// so captures use the Reduce Transparency alternative where glass shows.
    extension DestinationSnapshotTests {
        private static let themeCalendar = Calendar.current

        private static func themeAt(_ hour: Int, _ minute: Int, nextDay: Bool = false) -> Date {
            let base = themeCalendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!
            let day = nextDay ? themeCalendar.date(byAdding: .day, value: 1, to: base)! : base
            return themeCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        private static let palettes: [(String, RestAppearancePreferences.Palette)] = [
            ("sundown", .sundown), ("desert", .warmAmber), ("polar", .coolTwilight)
        ]

        private func themePaneModel(
            _ change: (inout RestAppearanceDraft) -> Void = { _ in }
        ) -> CurfewAppModel {
            let model = Self.demoModel()
            model.currentTime = Self.themeAt(15, 30)
            model.updateTheme(change)
            return model
        }

        private func renderPane(
            _ model: CurfewAppModel, named name: String, ownWords: Bool = false,
            appearances: [NSAppearance.Name] = [.aqua]
        ) throws {
            for appearance in appearances {
                let suffix = appearance == .darkAqua ? "-dark" : ""
                try renderHosted(
                    SettingsView(initialSection: .restScreen)
                        .environment(model)
                        .curfewTheme(model)
                        .environment(\.restOwnWordsInitiallyOpen, ownWords)
                        .transaction { $0.disablesAnimations = true },
                    named: "theme-editor\(name)\(suffix)", width: 900,
                    height: ownWords ? 2000 : 1500, settlingTime: 0.6,
                    appearance: appearance, to: Self.snapshotsDirectory()
                )
            }
        }

        func testRenderThemeEditor() throws {
            try renderPane(themePaneModel(), named: "", appearances: [.aqua, .darkAqua])
            try renderPane(themePaneModel { $0.palette = .warmAmber }, named: "-desert")
            try renderPane(
                themePaneModel {
                    $0.palette = .coolTwilight
                    $0.voice = .playful
                    $0.clockStyle = .serif
                },
                named: "-polar", appearances: [.darkAqua]
            )
            let ownWords = themePaneModel {
                $0.voice = .gentle
                $0.customLines = VoiceCustomLines([
                    .lockedHeadline: "Go see the kids.",
                    .lastMinute: "Off you go."
                ])
                $0.saverMessageEnabled = true
            }
            try renderPane(
                ownWords, named: "-own-words", ownWords: true, appearances: [.aqua, .darkAqua]
            )
        }

        private func renderThemeRest(_ model: CurfewAppModel, named name: String) throws {
            let display = RestDisplayPresentation()
            display.isVisible = true
            let scene = LockScene()
            scene.settle(at: model.currentTime)
            try renderHosted(
                RestScreenView(model: model, display: display, scene: scene)
                    .curfewTheme(model)
                    .environment(\._accessibilityReduceTransparency, true)
                    .transaction { $0.disablesAnimations = true },
                named: name, width: 1440, height: 900, settlingTime: 0.6,
                appearance: .darkAqua, to: Self.snapshotsDirectory()
            )
        }

        func testRenderThemeLockVoices() throws {
            for voice in RestAppearancePreferences.Voice.allCases {
                let model = LockSnapshotTests.lockedModel(now: Self.themeAt(21, 41))
                model.updateTheme { $0.voice = voice }
                try renderThemeRest(
                    model,
                    named: "theme-lock-\(VoicePack(voice).name.lowercased())"
                )
            }
            for (name, palette) in Self.palettes.dropFirst() {
                let model = LockSnapshotTests.lockedModel(now: Self.themeAt(21, 41))
                model.updateTheme { $0.palette = palette }
                try renderThemeRest(model, named: "theme-lock-\(name)")
                let lead = LockSnapshotTests.lockedModel(now: Self.themeAt(6, 48, nextDay: true))
                lead.updateTheme { $0.palette = palette }
                try renderThemeRest(lead, named: "theme-lock-lead-in-\(name)")
            }
        }

        /// The bare sky in every palette at the four moments a palette must
        /// hold up: day, the last hour, dusk and night.
        func testRenderThemeSkies() throws {
            let directory = try Self.snapshotsDirectory()
            let moments: [(String, Date)] = [
                ("day", Self.themeAt(12, 30)), ("last-hour", Self.themeAt(17, 30)),
                ("dusk", Self.themeAt(18, 25)), ("night", Self.themeAt(21, 41))
            ]
            for (paletteName, choice) in Self.palettes {
                for (momentName, now) in moments {
                    let frame = HorizonMoment(
                        now: now, dayStart: Self.themeAt(7, 0), curfew: Self.themeAt(18, 0),
                        nextUnlock: Self.themeAt(7, 0, nextDay: true)
                    ).frame
                    let image = try XCTUnwrap(HorizonRenderer.image(
                        frame: frame, bandPhase: HorizonBandPhase.resting,
                        pixelWidth: 720, pixelHeight: 450, palette: HorizonPalette(choice)
                    ))
                    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image)
                        .representation(using: .png, properties: [:]))
                    try png.write(to: directory.appendingPathComponent(
                        "curfew-theme-sky-\(paletteName)-\(momentName).png"
                    ))
                }
            }
        }

        /// Today in the afternoon and the last half hour, in each other palette.
        func testRenderThemeToday() throws {
            let directory = try Self.snapshotsDirectory()
            for (name, choice) in Self.palettes.dropFirst() {
                for (moment, now, minutes, stage) in [
                    ("afternoon", Self.themeAt(15, 30), 150, WarningStage.none),
                    ("last-half-hour", Self.themeAt(17, 48), 12, .fifteenMinutes)
                ] {
                    let frame = HorizonMoment(
                        now: now, dayStart: Self.themeAt(7, 0), curfew: Self.themeAt(18, 0),
                        nextUnlock: Self.themeAt(7, 0, nextDay: true)
                    ).frame
                    let presentation = TodayPresentation.resolve(TodaySituation(
                        setupComplete: true, enforcing: true,
                        phase: stage == .none ? .working : .warning, warningStage: stage,
                        minutesRemaining: minutes, upcomingCurfew: Self.themeAt(18, 0),
                        unlockDate: nil, overrideEnds: nil, canRequestExtension: true,
                        extensionsRemaining: 2, canCallItADay: true
                    ))
                    try render(
                        TodaySundownView(
                            horizon: frame, presentation: presentation,
                            oneThing: TodayOneThing(
                                text: "Ship the billing migration",
                                isDone: false
                            )
                        )
                        .environment(\.horizonPalette, HorizonPalette(choice))
                        .transaction { $0.disablesAnimations = true },
                        named: "theme-today-\(moment)-\(name)", width: 832, height: 720,
                        to: directory
                    )
                }
            }
        }

        /// The Sunrise gate in each other palette, in the gentle voice.
        func testRenderThemeSunrise() throws {
            for (name, palette) in Self.palettes.dropFirst() {
                let model = Self.demoModel()
                let unlock = Self.themeAt(7, 0, nextDay: true)
                model.currentTime = unlock.addingTimeInterval(4 * 60)
                model.reflectionState.scheduledInterval = DateInterval(
                    start: Self.themeAt(18, 0), end: unlock
                )
                model.state = CurfewEvaluation(
                    phase: .working, warningStage: .none, minutesRemaining: 656,
                    canRequestExtension: true, lockDate: Self.themeAt(18, 0, nextDay: true),
                    unlockDate: nil
                )
                model.reflectionState.recorder = InMemoryReflectionRecording()
                model.updateTheme {
                    $0.palette = palette
                    $0.voice = .gentle
                }
                model.prepareSunriseGate(pages: model.currentSunrisePages())
                model.reflectionState.isDaybreakPresented = true
                try renderThemeRest(model, named: "theme-sunrise-\(name)")
            }
        }
    }
#endif
