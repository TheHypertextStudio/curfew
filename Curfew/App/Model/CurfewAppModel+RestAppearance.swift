import CurfewKit
import Foundation

extension CurfewAppModel {
    /// Companion-only schedule presentation; never a source of restriction authority.
    var restCompanionSnapshot: RestSceneSnapshot {
        var occurrence: ScheduleWindow?
        // Include the previous night through its stable morning expiry. This
        // is presentation from the local schedule, independent of wake opt-in.
        for offset in -1 ... 8 {
            guard let day = sunriseCalendar.date(byAdding: .day, value: offset, to: currentTime),
                  let candidate = settings.schedule.scheduleWindow(
                      for: day,
                      calendar: sunriseCalendar
                  ),
                  candidate.lockDate.timeIntervalSince1970.isFinite,
                  candidate.unlockDate.timeIntervalSince1970.isFinite,
                  candidate.lockDate < candidate.unlockDate,
                  candidate.unlockDate.addingTimeInterval(3600) > currentTime
            else { continue }
            if let occurrence, occurrence.unlockDate <= candidate.unlockDate {
                continue
            }
            occurrence = candidate
        }
        return RestSceneSnapshot(
            version: 1, expiresAt: occurrence?.unlockDate.addingTimeInterval(3600) ?? .distantPast,
            appearance: restAppearance, lockDate: occurrence?.lockDate,
            unlockDate: occurrence?.unlockDate
        )
    }

    var restBackgroundDirectory: URL {
        isDemoSession
            ? FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-demo-rest-backgrounds")
            : SharedPaths.applicationSupport.appendingPathComponent("rest-backgrounds")
    }

    /// A lightweight local-store adapter; appearance never enters synced settings.
    var restAppearanceStore: RestAppearancePreferencesStore {
        RestAppearancePreferencesStore(defaults: settingsStore.storageDefaults)
    }
}
