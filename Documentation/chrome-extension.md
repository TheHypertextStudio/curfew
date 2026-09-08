# Chrome extension operations

This document addresses the engineer who builds, loads, and releases Curfew's
Chrome extension. The engineer must verify one extension flavor with the matching
app flavor before enabling task-scoped browser enforcement.

## Build and identity

The extension is the `@curfew/chrome-extension` workspace package under
`web/extension`. Run these commands from `web`:

```sh
pnpm install --frozen-lockfile
pnpm --filter @curfew/chrome-extension test
pnpm --filter @curfew/chrome-extension typecheck
pnpm --filter @curfew/chrome-extension build:development
pnpm --filter @curfew/chrome-extension build
```

The development artifact is `web/extension/dist/development`. Load that folder
through `chrome://extensions` after enabling Developer mode. Chrome must show ID
`loammdknmfbkjnckaeeagnmakinknbck`. The development worker calls only
`studio.hypertext.curfew.dev.browser`.

The production artifact is `web/extension/dist/production`. It calls only
`studio.hypertext.curfew.browser`. As of 2026-09-08, both manifests include the
public key from `BrowserNativeInstallation.developmentPublicKey`, so an unpacked
production artifact keeps the pinned development identity. The release engineer
must create the Chrome Web Store draft before shipping. If the store assigns a
different production ID, the engineer must set `CURFEW_BROWSER_EXTENSION_ID` to
that exact ID and verify the signed app's native-host manifest against the
published extension. The engineer must not ship an empty production ID.

## Permissions and rule lifetime

The extension requests `declarativeNetRequest`, `storage`, `tabs`,
`webNavigation`, `nativeMessaging`, and `alarms`. It requests host access only
for HTTP and HTTPS. The `alarms` permission is required because Chrome can
suspend a Manifest V3 worker. A timer in the worker cannot revoke an expired
grant or break. The worker keeps one next-expiry alarm and rebuilds the complete
ruleset against the current clock when that alarm fires. A separate 30-second
alarm reads policy and sends a heartbeat through `browser-host/1`. A returned
session change replaces the complete ruleset before the heartbeat or any later
review can run.

An active policy installs one priority-1 block rule for HTTP and HTTPS
`main_frame` requests. Exact-origin and segment-bounded path-prefix rules use
priority 100. Every rule names only `main_frame`, so images, scripts, API calls,
and other subresources remain outside this release. The worker treats dynamic
rules as derived state. It removes every current rule and adds the replacement
rules in one `updateDynamicRules` call.

The worker caches the latest valid `browser-policy/1` snapshot in
`chrome.storage.local`. It rebuilds rules from that cache before it asks the
native host for fresh policy. A host error leaves the cached restrictive policy
and its block rule in place. The failed refresh does not write a heartbeat, so
Settings can mark the connection unhealthy. A successful empty policy removes
the cache and the rules. Grant and break timestamps never become durable
permission because every ruleset build compares them with the caller's current
clock.

## Blocker privacy and review

Chrome reports a blocked top-level request as `ERR_BLOCKED_BY_CLIENT`. The worker
stores the original URL under a random request ID for at most two minutes. The
blocker URL contains only that ID. The blocker page receives the current task
title, target hostname, and this question:

> What will you do on &lt;host&gt;, and what will you produce for &lt;task&gt;?

The worker sends only a normalized origin and path to `browser-host/1`. It
removes credentials, query strings, fragments, default ports, and dot segments
before review. The blocker keeps the justification and one challenge answer in
page memory. Neither value enters extension storage. A grant must return a
bounded scope and a same-session policy that permits the destination at the
current time. The worker installs that complete policy before it reopens the
original URL. A denial, cooldown, stale session, invalid response, or host error
leaves the tab on the blocker page. A task switch replaces the rules and removes
old-session requests before any tab can reopen.

## Release and rollback

The signed release check must use interactive Chrome. The engineer must prove
that an unknown page never renders, the blocker shows the current task and
hostname, one challenge works, a denial stays blocked, a grant opens only its
returned scope, expiry revokes that scope, a task switch revokes old grants, and
stopping the host leaves unknown destinations blocked. The engineer must also
inspect `chrome.storage.local` and confirm that no justification or challenge
answer exists.

Task 7 owns the Settings connection and interactive blocker capture. The current
automated suite does not claim that signed-app or Web Store acceptance has
passed. Rollback must disable the feature, remove the matching native-host
manifest, and remove every dynamic extension rule. If Settings cannot reach the
worker during rollback, the engineer must disable or uninstall the extension in
Chrome before removing the host.
