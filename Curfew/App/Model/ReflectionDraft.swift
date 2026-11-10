import CurfewKit
import Foundation
import Observation

/// One in-memory editing session shared by every display. Prompt snapshots
/// remain stable while editing; this is not a claim of crash-safe persistence.
@Observable
final class ReflectionDraft {
    let prompts: [ReflectionPrompt]
    var values: [UUID: ReflectionValue] = [:]

    init(prompts: [ReflectionPrompt]) {
        self.prompts = prompts
    }
}
