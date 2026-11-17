@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// The Debug demo fixture carries Journal sample history so snapshots have
/// something to draw, and nothing else can reach it.
@MainActor
struct JournalDemoWiringTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("The demo model's Journal holds about eleven months of sample days")
    func demoModelHasSampleHistory() {
        let model = CurfewAppModel.demoModel()
        let now = Date()
        let records = model.journalDayRecords(
            in: now.addingTimeInterval(-400 * 86400) ... now
        )
        #expect(records.count > 200)
        #expect(records.contains { !$0.overrideReasons.isEmpty })
        #expect(records.contains { $0.oneThing != nil && $0.readiness != nil })
        #expect(records.contains { !$0.eveningAnswers.isEmpty })
    }

    @Test("A model that is not a demo session starts with an empty Journal")
    func ordinaryModelHasNoSampleHistory() throws {
        let model = try CurfewAppModel(
            settingsStore: CurfewSettingsStore(
                defaults: #require(
                    UserDefaults(suiteName: "JournalDemoWiring-\(UUID().uuidString)")
                )
            ),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        let now = Date()
        #expect(!model.isDemoSession)
        #expect(model.journalDayRecords(in: now.addingTimeInterval(-400 * 86400) ... now)
            .isEmpty)
    }

    @Test("Sample data is referenced only from Debug-only demo code")
    func sampleDataStaysInTheDemoFixture() throws {
        let allowed: Set = [
            "Curfew/App/Demo/JournalSampleData.swift",
            "Curfew/App/Model/CurfewAppModel+Demo.swift"
        ]
        let appRoot = repositoryRoot.appendingPathComponent("Curfew")
        let enumerator = try #require(FileManager.default.enumerator(
            at: appRoot,
            includingPropertiesForKeys: nil
        ))
        var referencing: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("JournalSampleData") else { continue }
            let relative = String(url.path.dropFirst(repositoryRoot.path.count + 1))
            referencing.append(relative)
            #expect(source.contains("#if DEBUG"), "\(relative) must be Debug-only")
        }
        #expect(Set(referencing) == allowed)
    }
}
