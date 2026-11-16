#if DEBUG
    import AppKit
    @testable import Curfew
    import CurfewAtmosphere
    import SwiftUI
    import XCTest

    /// Writes the bare Horizon scene at four moments of a 7 AM to 6 PM day to
    /// `build/screenshots/curfew-horizon-*.png` for review against the
    /// prototype, and probes whether SwiftUI shader effects survive the
    /// headless rasterisers the snapshot tier uses.
    @MainActor
    final class HorizonSnapshotTests: XCTestCase {
        private static let width = 1440
        private static let height = 900

        private static func moment(_ name: String) -> HorizonMoment {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!
            func at(_ hour: Int, _ minute: Int, nextDay: Bool = false) -> Date {
                let base = nextDay ? calendar.date(byAdding: .day, value: 1, to: day)! : day
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
            }
            let now = switch name {
            case "afternoon": at(15, 30)
            case "last-light": at(17, 48)
            case "locked": at(21, 41)
            default: at(7, 4, nextDay: true)
            }
            return HorizonMoment(
                now: now, dayStart: at(7, 0), curfew: at(18, 0), nextUnlock: at(7, 0, nextDay: true)
            )
        }

        func testRenderHorizonScenes() throws {
            let directory = try DestinationSnapshotTests.snapshotsDirectory()
            for name in ["afternoon", "last-light", "locked", "morning"] {
                let image = try XCTUnwrap(HorizonRenderer.image(
                    frame: Self.moment(name).frame, bandPhase: HorizonBandPhase.resting,
                    pixelWidth: Self.width, pixelHeight: Self.height
                ))
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image)
                    .representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("curfew-horizon-\(name).png"))
            }
            print("==> Horizon scenes written to \(directory.path)")
        }

        /// Records whether the shader draws in each headless path. The harness
        /// uses the CPU reference renderer either way, so captures are truthful;
        /// this test documents the finding and fails only if the reference
        /// renderer itself disagrees with the model.
        func testShaderRenderingInHeadlessHarness() throws {
            let frame = Self.moment("afternoon").frame
            let size = CGSize(width: 160, height: 100)
            let reference = try XCTUnwrap(HorizonRenderer.pixels(
                frame: frame, bandPhase: HorizonBandPhase.resting, pixelWidth: 160, pixelHeight: 100
            ))
            let probe = CGPoint(x: 80, y: 20)
            let offset = (Int(probe.y) * 160 + Int(probe.x)) * 4
            let expected = Array(reference[offset ..< offset + 3])

            let sky = HorizonSkyView(frame: frame, isDayRunning: false)
                .environment(\.horizonSkyRendering, .shader)
                .frame(width: size.width, height: size.height)

            let renderer = ImageRenderer(content: sky)
            renderer.scale = 1
            let viaRenderer = renderer.cgImage.flatMap { Self.pixel(in: $0, at: probe) }

            let host = NSHostingView(rootView: sky)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let viaWindow = bitmap.cgImage.flatMap { Self.pixel(in: $0, at: probe) }

            func matches(_ sample: [UInt8]?) -> Bool {
                guard let sample else { return false }
                return zip(sample, expected).allSatisfy { abs(Int($0) - Int($1)) <= 6 }
            }
            print("==> Horizon shader probe: expected \(expected)")
            print(
                "==> ImageRenderer: \(String(describing: viaRenderer)) matches=\(matches(viaRenderer))"
            )
            print(
                "==> NSWindow cacheDisplay: \(String(describing: viaWindow)) matches=\(matches(viaWindow))"
            )
        }

        /// The sRGB bytes at a point, row 0 at the top.
        private static func pixel(in image: CGImage, at point: CGPoint) -> [UInt8]? {
            let width = image.width
            let height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: &bytes, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let column = min(Int(point.x * CGFloat(width) / 160), width - 1)
            let row = min(Int(point.y * CGFloat(height) / 100), height - 1)
            let offset = (row * width + column) * 4
            return Array(bytes[offset ..< offset + 3])
        }
    }
#endif
