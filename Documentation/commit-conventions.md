# Commit conventions

Curfew uses [Conventional Commits](https://www.conventionalcommits.org/).

## Format

```
type(scope): subject
<blank line>
body
<blank line>
Co-Authored-By: …
```

- **Subject**: imperative mood, ≤72 chars
- **Body**: only when the why isn't obvious from the diff; lines ≤80 chars
  (the `commit-msg` hook installed by `just install-hooks` wraps prose
  automatically)

## Scopes

Scopes map to public changelog sections. If a change wouldn't appear as
a named section in release notes, it doesn't get its own scope —
roll it into the feature it serves.

| Scope         | Changelog meaning                                              |
|---------------|----------------------------------------------------------------|
| `enforcement` | Lockout, blocking, key interception, background daemon         |
| `schedule`    | Bedtime configuration and time policy                          |
| `reflection`  | Gates, prompts, log, and export                                |
| `mcp`         | The MCP server Curfew exposes and its tool definitions         |
| `sync`        | iCloud / CloudKit multi-device sync                            |
| `widget`      | WidgetKit extension                                            |
| `cli`         | curfew-ctl command-line tool                                   |
| `build`       | Xcode config, CI, scripts, packaging — dev-internal            |
| `landing`     | Marketing site — dev-internal                                  |
| `docs`        | The published documentation site at curfew.hypertext.studio/docs |

Implementation layers (`storage`, `overlay`, `daemon`) and singleton
concepts (`app`, `sky`) are not scopes.
