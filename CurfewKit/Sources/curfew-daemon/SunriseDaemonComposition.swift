import CurfewKit
import Foundation

/// Root-only composition of the tested journal, ownership policy and native adapter.
enum SunriseDaemonComposition {
    static func prepare(owner: String, power: SunrisePowerIO) throws -> SunriseWakeScheduler {
        let url = try SunriseWakeJournal.prepareDirectory(
            in: URL(fileURLWithPath: "/private/var/db", isDirectory: true),
            namespace: owner, requiredOwnerUserID: 0
        )
        let journal = SunriseWakeJournal(url: url, owner: owner, requiredOwnerUserID: 0)
        return SunriseWakeScheduler(
            owner: owner, load: journal.load, save: journal.save,
            schedule: { event in
                try power.schedule(.init(
                    owner: event.owner, date: event.wakeAt, type: event.eventType
                ))
            },
            cancel: { event in
                try power.cancel(.init(
                    owner: event.owner, date: event.wakeAt, type: event.eventType
                ))
            }
        )
    }
}
