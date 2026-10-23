import CryptoKit
import Foundation

public extension SunriseWakePlanner {
    /// Resolves a local presentation occurrence without authorizing helper operations.
    /// The occurrence survives scheduled unlock through its five-minute display hold.
    func presentationPlan(
        schedule: WeeklySchedule,
        appearance: RestAppearancePreferences,
        at date: Date,
        calendar: Calendar
    ) -> SunriseWakePlan? {
        guard appearance.sunriseWakeEnabled,
              date.timeIntervalSince1970.isFinite else { return nil }
        // Looking back only through the hold retains the previous scheduled night
        // after unlock without extending its restriction authority.
        let reference = date.addingTimeInterval(-300)
        var occurrence: ScheduleWindow?
        for offset in 0 ... 8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: reference),
                  let candidate = schedule.scheduleWindow(for: day, calendar: calendar),
                  candidate.lockDate.timeIntervalSince1970.isFinite,
                  candidate.unlockDate.timeIntervalSince1970.isFinite,
                  candidate.unlockDate > candidate.lockDate,
                  candidate.unlockDate.addingTimeInterval(300) > date else { continue }
            if let current = occurrence, current.unlockDate <= candidate.unlockDate {
                continue
            }
            occurrence = candidate
        }
        guard let occurrence else { return nil }
        let leadInterval = Double(appearance.sunriseLeadMinutes) * 60
        let wakeAt = occurrence.unlockDate.addingTimeInterval(-leadInterval)
        return SunriseWakePlan(
            owner: owner,
            occurrenceID: presentationIdentity(for: occurrence),
            wakeAt: wakeAt,
            holdUntil: occurrence.unlockDate.addingTimeInterval(300),
            allowsBattery: appearance.sunriseOnBatteryEnabled
        )
    }

    private func presentationIdentity(for occurrence: ScheduleWindow) -> UUID {
        // Stable across launches and timezone identifiers that resolve the same
        // absolute window. Lead-in and battery choices do not create a new night.
        let canonical = "curfew.sunrise.v1|\(owner.utf8.count):\(owner)|"
            + "\(occurrence.lockDate.timeIntervalSince1970.bitPattern)|"
            + "\(occurrence.unlockDate.timeIntervalSince1970.bitPattern)"
        var bytes = Array(SHA256.hash(data: Data(canonical.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
