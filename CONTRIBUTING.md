# Contributing

Bug reports, design critique, and pull requests are welcome.

## Development setup

```bash
brew install just swiftlint swiftformat
git clone https://github.com/TheHypertextStudio/curfew
cd curfew
just install-hooks   # symlinks scripts/hooks/commit-msg into .git/hooks/
open Curfew.xcodeproj
```

The full ship-gate is `just check`: SwiftFormat lint → SwiftLint → unit tests → Debug build. CI runs the same command on every push. PRs must pass `just check` before review.

## Workflow

- Open an issue before a large change to align on scope.
- Keep PRs focused — one concern per PR.
- Add or update tests for any behavior change in `Sources/CurfewKit/`. UI changes don't require tests but must not break existing ones.
- `AGENTS.md` describes the TDD contract for Core modules in detail.

## Code style

SwiftFormat and SwiftLint configs live at `.swiftformat` and `.swiftlint.yml`. Run `just format` before committing — CI will fail if the formatter would change any file.

Key conventions:
- `@MainActor` on all types that read/write UI or AppKit state.
- `nonisolated init()` when the designated init needs no actor-isolated state.
- No comments on *what* the code does — only *why*, when non-obvious.
- No `T?` for "collaborator might be absent" — use null-object pattern or sentinels.

## Commit messages

See [Documentation/commit-conventions.md](Documentation/commit-conventions.md).

## License

By contributing you agree that your changes will be released under the [MIT License](LICENSE).
