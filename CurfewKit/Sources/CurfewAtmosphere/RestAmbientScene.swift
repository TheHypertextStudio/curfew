import CoreGraphics
import CurfewKit
import SwiftUI

/// Shared presentation only. Hosts own image loading, scheduling and the clock cadence.
///
/// The sky is supplied by the host: the app and the screen saver pass their
/// Metal-backed Horizon view, which cannot live in this package. Tests and
/// other hosts can use ``HorizonStillSky`` through the convenience initialiser.
@available(macOS 26.0, *)
public struct RestAmbientScene<Sky: View>: View {
    public let snapshot: RestSceneSnapshot
    public let date: Date
    public let image: CGImage?
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let showsClock: Bool
    public let clockSize: CGFloat
    public let showsMessage: Bool
    private let clockNamespace: Namespace.ID?
    private let sky: (HorizonFrame, Bool) -> Sky
    @Namespace private var localClockNamespace

    /// - Parameter sky: draws the Horizon scene for a frame; the flag says
    ///   whether the day is running, so the bands should drift.
    public init(
        snapshot: RestSceneSnapshot,
        date: Date,
        image: CGImage? = nil,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        showsClock: Bool = true,
        clockSize: CGFloat = 110,
        showsMessage: Bool = true,
        clockNamespace: Namespace.ID? = nil,
        @ViewBuilder sky: @escaping (HorizonFrame, Bool) -> Sky
    ) {
        self.sky = sky
        self.snapshot = snapshot
        self.date = date
        self.image = image
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.showsClock = showsClock
        self.clockSize = clockSize
        self.showsMessage = showsMessage
        self.clockNamespace = clockNamespace
    }

    private var appearance: RestAppearancePreferences {
        snapshot.appearance
    }

    private var frame: RestSceneSnapshot.Frame {
        snapshot.resolve(at: date, timeZone: .current)
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: contentAlignment) {
                // The composite is opaque even for transparent imported pixels.
                Color.black
                background(in: proxy.size)
                    .overlay(shieldsText ? AtmospherePalette.textScrim : .clear)
                if showsClock {
                    VStack(
                        alignment: appearance.clockPosition == .lowerLeft ? .leading : .center,
                        spacing: 16
                    ) {
                        Text(date, style: .time)
                            .font(.system(size: clockSize, weight: .semibold, design: clockDesign))
                            .monospacedDigit()
                            .matchedGeometryEffect(
                                id: "rest-clock", in: clockNamespace ?? localClockNamespace
                            )
                        if showsMessage, !appearance.message.isEmpty {
                            Text(appearance.message)
                                .font(.system(size: max(16, clockSize * 0.19)))
                                .multilineTextAlignment(appearance
                                    .clockPosition == .lowerLeft ? .leading : .center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(AtmospherePalette.warmWhite)
                    .padding(max(24, min(proxy.size.width, proxy.size.height) * 0.065))
                    .padding(
                        .top,
                        appearance.clockPosition == .upperCenter ? proxy.size.height * 0.15 : 0
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var contentAlignment: Alignment {
        switch appearance.clockPosition {
        case .center: .center
        case .upperCenter: .top
        case .lowerLeft: .bottomLeading
        }
    }

    private var clockDesign: Font.Design {
        switch appearance.clockStyle {
        case .rounded: .rounded
        case .standard: .default
        case .serif: .serif
        }
    }

    private func background(in size: CGSize) -> some View {
        ZStack {
            if appearance.background == .image, let image {
                focalImage(image, in: size)
                // Preserve the personal photograph throughout the dawn ramp.
                Color(red: 1, green: 0.79, blue: 0.53)
                    .opacity(frame.sunriseProgress * 0.26)
                    .blendMode(.screen)
            } else if appearance.background == .solid {
                Color(
                    red: appearance.solidRed,
                    green: appearance.solidGreen,
                    blue: appearance.solidBlue
                )
                Color(red: 1, green: 0.79, blue: 0.53)
                    .opacity(frame.sunriseProgress * 0.26)
                    .blendMode(.screen)
            } else {
                // The Horizon night is dark enough for the clock without a scrim.
                sky(resolvedFrame, bandsDrift)
                if appearance.palette == .warmAmber {
                    Color(red: 0.94, green: 0.46, blue: 0.12)
                        .opacity(0.20)
                        .blendMode(.softLight)
                } else if appearance.palette == .coolTwilight {
                    Color(red: 0.20, green: 0.32, blue: 0.75)
                        .opacity(0.25)
                        .blendMode(.softLight)
                }
            }
        }
    }

    /// Bands drift only once the morning has come; they hold still through the
    /// lock, for a static background and under Reduce Motion.
    var bandsDrift: Bool {
        frame.phase == .morning && !appearance.staticBackground && !reduceMotion
    }

    /// The scrim keeps text readable over a photograph or a chosen colour.
    private var shieldsText: Bool {
        appearance.background == .image && image != nil || appearance.background == .solid
    }

    /// The sky for this instant, from the session's curfew and unlock. With no
    /// occurrence the scene rests in the middle of a night.
    var resolvedFrame: HorizonFrame {
        guard frame.phase != .allDay, let lockDate = snapshot.lockDate,
              let unlockDate = snapshot.unlockDate else {
            return HorizonMoment.restingNight(at: date).frame
        }
        return HorizonMoment.scheduled(now: date, curfew: lockDate, nextUnlock: unlockDate).frame
    }

    private func focalImage(_ image: CGImage, in size: CGSize) -> some View {
        let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        let originX = min(0, max(size.width - width, size.width / 2 - width * appearance.focalX))
        let originY = min(
            0,
            max(size.height - height, size.height / 2 - height * appearance.focalY)
        )
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: width, height: height)
            .position(
                x: originX + width / 2,
                y: originY + height / 2
            )
    }
}

@available(macOS 26.0, *)
public extension RestAmbientScene where Sky == HorizonStillSky {
    /// A scene whose sky is the CPU reference render, for tests and hosts
    /// without the Metal shader.
    init(
        snapshot: RestSceneSnapshot,
        date: Date,
        image: CGImage? = nil,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        showsClock: Bool = true,
        clockSize: CGFloat = 110,
        showsMessage: Bool = true,
        clockNamespace: Namespace.ID? = nil
    ) {
        self.init(
            snapshot: snapshot, date: date, image: image, reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency, showsClock: showsClock,
            clockSize: clockSize, showsMessage: showsMessage, clockNamespace: clockNamespace
        ) { frame, _ in
            HorizonStillSky(frame: frame)
        }
    }
}
