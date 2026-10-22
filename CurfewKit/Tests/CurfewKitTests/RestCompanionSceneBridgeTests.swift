@testable import CurfewKit
import Foundation
import Testing

/// Contracts for the safe presentation bridge; image metadata fakes do not prove pixel decoding.
struct RestCompanionSceneBridgeTests {
    /// 2026-10-22 06:00 UTC is 23:00 on October 21 in the primary UTC−7 zone.
    private var lock: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 6))!
    }

    private var unlock: Date {
        lock.addingTimeInterval(8 * 3600)
    }

    private var zone: TimeZone {
        TimeZone(secondsFromGMT: -7 * 3600)!
    }

    private let imageBytes = Data([0x43, 0x55, 0x52, 0x46, 0x45, 0x57])

    private func original(includeMessage: Bool = true) -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: 1,
            expiresAt: unlock.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(
                background: .image, palette: .coolTwilight,
                solidRed: 0.2, solidGreen: 0.3, solidBlue: 0.4,
                clockStyle: .serif, clockPosition: .lowerLeft, staticBackground: true,
                message: "Time to rest",
                ownedImageFilename: "12345678-1234-1234-1234-123456789abc.png",
                focalX: 0.25, focalY: 0.75, saverMessageEnabled: includeMessage,
                sunriseWakeEnabled: true, sunriseLeadMinutes: 45,
                sunriseOnBatteryEnabled: true
            ),
            lockDate: lock, unlockDate: unlock
        )
    }

    private func decoded(includeMessage: Bool = true) throws -> RestCompanionExport {
        let expectedBytes = imageBytes
        let inspect: (Data) throws -> RestCompanionExport.ImageDimensions = { bytes in
            #expect(bytes == expectedBytes)
            return .init(width: 640, height: 480)
        }
        let bytes = try RestCompanionExport.encode(
            snapshot: original(includeMessage: includeMessage), imageData: imageBytes,
            inspectImageHeader: inspect
        )
        return try RestCompanionExport.decode(bytes, inspectImageHeader: inspect)
    }

    @Test(
        "Validated image keeps visual choices without ownership or operations"
    )
    func preservesVisualAppearanceOnly() throws {
        let presentation = try decoded()
        let bridge = RestSceneSnapshot(presentation: presentation)
        let values = bridge.appearance
        #expect(presentation.imageData == imageBytes)
        #expect(values.background == .image)
        #expect(values.palette == .coolTwilight)
        #expect(values.solidRed == 0.2)
        #expect(values.solidGreen == 0.3)
        #expect(values.solidBlue == 0.4)
        #expect(values.clockStyle == .serif)
        #expect(values.clockPosition == .lowerLeft)
        #expect(values.staticBackground)
        #expect(values.focalX == 0.25)
        #expect(values.focalY == 0.75)
        #expect(values.message == "Time to rest")
        #expect(values.sunriseLeadMinutes == 45)
        #expect(values.ownedImageFilename == nil)
        #expect(!values.saverMessageEnabled)
        #expect(!values.sunriseWakeEnabled)
        #expect(!values.sunriseOnBatteryEnabled)
        #expect(bridge.version == presentation.version)
        #expect(bridge.expiresAt == presentation.expiresAt)
        #expect(bridge.lockDate == presentation.lockDate)
        #expect(bridge.unlockDate == presentation.unlockDate)
    }

    @Test(
        "Message crosses with consent without enabling operations"
    )
    func messageConsent() throws {
        for consent in [false, true] {
            let presentation = try decoded(includeMessage: consent)
            let bridge = RestSceneSnapshot(presentation: presentation)
            #expect(bridge.appearance.message == (consent ? "Time to rest" : ""))
            #expect(!bridge.appearance.saverMessageEnabled)
        }
    }

    @Test(
        "Original, export and bridge agree across overnight clock boundaries"
    )
    func absoluteDateParity() throws {
        let source = original()
        let presentation = try decoded()
        let bridge = RestSceneSnapshot(presentation: presentation)
        // Deliberately nonmonotonic calls exercise recomputation after forward/backward jumps.
        let instants = [
            lock.addingTimeInterval(-1), lock, lock.addingTimeInterval(4 * 3600),
            unlock.addingTimeInterval(-2701), unlock.addingTimeInterval(-2700),
            unlock.addingTimeInterval(-1350), unlock.addingTimeInterval(-1), unlock,
            unlock.addingTimeInterval(1), lock.addingTimeInterval(60),
            source.expiresAt, source.expiresAt.addingTimeInterval(1),
            unlock.addingTimeInterval(-600)
        ]
        for now in instants {
            for timeZone in try [zone, #require(TimeZone(secondsFromGMT: 0))] {
                #expect(bridge.resolve(at: now, timeZone: timeZone) ==
                    source.resolve(at: now, timeZone: timeZone))
                #expect(bridge.resolve(at: now, timeZone: timeZone) ==
                    presentation.resolve(at: now, timeZone: timeZone))
            }
        }
    }

    @Test("Missing occurrence context remains neutral without inventing restriction state")
    func missingOccurrenceIsNeutral() throws {
        let source = RestSceneSnapshot(
            version: 1, expiresAt: unlock.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(), lockDate: nil, unlockDate: nil
        )
        let bytes = try RestCompanionExport.encode(
            snapshot: source, imageData: nil,
            inspectImageHeader: { _ in Issue.record("No image expected"); return .init(
                width: 1,
                height: 1
            ) }
        )
        let presentation = try RestCompanionExport.decode(
            bytes, inspectImageHeader: { _ in Issue.record("No image expected"); return .init(
                width: 1,
                height: 1
            ) }
        )
        let bridge = RestSceneSnapshot(presentation: presentation)
        #expect(bridge.lockDate == nil)
        #expect(bridge.unlockDate == nil)
        #expect(bridge.resolve(at: lock, timeZone: zone).phase == .allDay)
    }
}
