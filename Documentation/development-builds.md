# Curfew development builds

There are two supported apps:

| App | Configuration | Bundle ID | Service environment |
| --- | --- | --- | --- |
| Curfew | Release | `studio.hypertext.apps.curfew` | Production |
| Curfew Dev | Debug | `studio.hypertext.apps.curfew.dev` | Staging |

The development widget appends `.widget`. Both app configurations use the Studio
signing team. Debug produces `Curfew Dev.app`; it must never overwrite `Curfew.app`.
`just build` builds the development app. `just build-release` builds production.

## Existing internal installations

Curfew Dev continues to use the former Studio Dev preferences, Application Support
folder, Keychain services/access group, App Group and background state. The helper registration uses
`studio.hypertext.apps.curfew.dev.daemon`; the old helper must be unregistered
before installing it so macOS cannot reuse an obsolete app path.
These compatibility identifiers are private storage contracts, not additional
build flavors. Renaming them would otherwise disconnect encrypted account data
or lose active deadlines. The old personal-development store is left untouched;
there is no automatic merge and no deletion of its history.

Before replacing an installed build, back up its preferences and databases using
SQLite backup, verify no active lockout is interrupted, and disconnect background
protection through the old app. Current builds put these controls in Settings → Protection,
with removal visible beside connection status. Install the signed replacement at
`/Applications/Curfew Dev.app`, connect background protection through the normal
macOS approval flow, then verify account connectivity, unchanged schedule/history,
assistant consent, login behavior and update trust. Retain a rollback copy until
these checks pass. Never erase retained state to repair a failed upgrade.

Only unsigned Debug binaries accept demo fixtures for isolated captures. Signed
Curfew Dev arms normally and requires explicit schedule consent just as the
installed predecessor did. Development root shutdown remains suppressed. Chrome
task-browser enforcement remains unavailable in the development app until its
extension identity is explicitly provisioned; ordinary account and local MCP
features remain available.

Apple service IDs and sign-in key associations must point to the canonical dev
App ID before obsolete app registrations are retired. Keep the existing key
material, service IDs, callbacks, App Groups and credential access groups.
