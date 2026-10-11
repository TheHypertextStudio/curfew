import Foundation
import Testing

struct SettingsTypographyTests {
    @Test("Product labels preserve sentence case instead of becoming overlines")
    func noAllCapsOverlines() throws {
        let root = URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let paths = [
            "Curfew/UI/SettingsView.swift",
            "Curfew/UI/Destinations/JournalReflectionsView.swift",
            "Curfew/UI/Destinations/JournalSundownView.swift",
            "Curfew/UI/LockoutScreenView.swift"
        ]
        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            #expect(!source.contains(".uppercased()"), "No forced uppercase in \(path)")
            #expect(!source.contains("Text(\"CURFEW\")"), "Use the product name's normal case")
            #expect(!source.contains(".tracking("), "No letterspaced overlines in \(path)")
        }
    }
}
