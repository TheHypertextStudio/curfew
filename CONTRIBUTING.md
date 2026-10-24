# Contributing

Bug reports, design critique, and pull requests are welcome.

## Development setup

```bash
brew install just swiftlint
git clone https://github.com/TheHypertextStudio/curfew
cd curfew
./bootstrap worktree prepare
open Curfew.xcodeproj
```

Worktree preparation installs the pinned formatting tools and composes the local
commit hooks, including the existing commit-message wrapping. To reinstall only
formatting tools and hooks, run `just install-hooks`. Commits format the staged
source and configuration while retaining unstaged edits; the hook does not
install dependencies or download tools.

The full ship-gate is `just check`: SwiftFormat lint → SwiftLint → unit tests → Debug build. CI runs the same command on every push. PRs must pass `just check` before review.

## Workflow

- Open an issue before a large change to align on scope.
- Keep PRs focused — one concern per PR.
- Add or update tests for any behavior change in `CurfewKit/Sources/CurfewKit/`. UI changes don't require tests but must not break existing ones.
- `AGENTS.md` describes the TDD contract for Core modules in detail.

## Code style

SwiftFormat and SwiftLint configs live at `.swiftformat` and `.swiftlint.yml`. Run `just format` before committing — CI will fail if the formatter would change any file.

Local commands and CI use SwiftFormat 0.63.1 through `scripts/swiftformat.sh`.
The wrapper verifies the official release archive and extracted executable by
SHA-256, then reuses one user cache across checkouts. The first invocation
requires network access; a verified cached executable works offline. Updating
the formatter requires reviewing its version and both digests together.

Key conventions:

- `@MainActor` on all types that read/write UI or AppKit state.
- `nonisolated init()` when the designated init needs no actor-isolated state.
- No comments on _what_ the code does — only _why_, when non-obvious.
- No `T?` for "collaborator might be absent" — use null-object pattern or sentinels.

## Commit messages

See [Documentation/commit-conventions.md](Documentation/commit-conventions.md).

## License

By contributing you agree that your changes will be released under the [MIT License](LICENSE).
