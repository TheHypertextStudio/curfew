import CoreGraphics
import CurfewKit
import SwiftUI

/// Shared presentation only. Hosts own image loading, scheduling and the clock cadence.
@available(macOS 26.0, *)
public struct RestAmbientScene: View {
    public let snapshot: RestSceneSnapshot
    public let date: Date
    public let image: CGImage?
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let showsClock: Bool
    public let clockSize: CGFloat
    public let showsMessage: Bool

    public init(
        snapshot: RestSceneSnapshot,
        date: Date,
        image: CGImage? = nil,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        showsClock: Bool = true,
        clockSize: CGFloat = 110,
        showsMessage: Bool = true
    ) {
        self.snapshot = snapshot
        self.date = date
        self.image = image
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.showsClock = showsClock
        self.clockSize = clockSize
        self.showsMessage = showsMessage
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
                    .overlay(AtmospherePalette.textScrim)
                if showsClock {
                    VStack(
                        alignment: appearance.clockPosition == .lowerLeft ? .leading : .center,
                        spacing: 16
                    ) {
                        Text(date, style: .time)
                            .font(.system(size: clockSize, weight: .semibold, design: clockDesign))
                            .monospacedDigit()
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
                AtmosphereSky(
                    moment: resolvedMoment,
                    date: date,
                    reduceMotion: reduceMotion || appearance.staticBackground
                )
                // Sundown retains the original unmodified palette.
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

    var resolvedMoment: AtmosphereMoment {
        guard frame.phase != .allDay else { return .night }
        let hasOccurrence = true
        return AtmosphereMoment.resolve(
            now: date,
            lockDate: hasOccurrence ? snapshot.lockDate : nil,
            unlockDate: hasOccurrence ? snapshot.unlockDate : nil,
            phase: hasOccurrence ? .locked : .dayOff,
            sunriseLeadMinutes: appearance.sunriseLeadMinutes
        )
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
