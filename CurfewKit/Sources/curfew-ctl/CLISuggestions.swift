import ArgumentParser
import Foundation

enum CLISuggestions {
    static func closest(_ input: String, in candidates: [String]) -> String? {
        guard !input.isEmpty, input.count <= 128 else { return nil }
        let limit = max(1, min(3, input.count / 3))
        return candidates.sorted().map { ($0, distance(input, $0)) }
            .filter { $0.1 <= limit }.min { $0.1 < $1.1 }?.0
    }

    static func parserAction(for message: String) -> String? {
        guard message.hasPrefix("Unexpected argument '"),
              let input = message.split(separator: "'").dropFirst().first,
              let suggestion = closest(String(input), in: commandNames(CurfewCLI.self)) else {
            return nil
        }
        return "Did you mean '\(suggestion)'?"
    }

    private static func commandNames(_ command: any ParsableCommand.Type) -> [String] {
        command.configuration.subcommands.flatMap { [$0._commandName] + commandNames($0) }
    }

    private static func distance(_ first: String, _ second: String) -> Int {
        let left = Array(first)
        let right = Array(second)
        var previous = Array(0 ... right.count)
        for (leftIndex, character) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, other) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (character == other ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? left.count
    }
}
