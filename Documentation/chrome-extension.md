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
```

The extension icons are Chrome-sized exports of the shipping Curfew app icon,
not a separate illustration. Regenerate them from the repository root after
changing `Curfew/AppIcon.icon`:

```sh
swift scripts/generate-extension-icons.swift
```

The generator compiles the Icon Composer source, then writes the 16, 32, 48,
and 128 pixel PNGs with transparent outer padding. The 128 pixel export keeps
the visible mark inside Chrome's 96 pixel artwork area. The extension test suite
rejects committed icons that no longer match the app icon source.

The development artifact is `web/extension/dist/development`. Load that folder
through `chrome://extensions` after enabling Developer mode. Chrome must show ID
`loammdknmfbkjnckaeeagnmakinknbck`. The development worker calls only
`studio.hypertext.curfew.dev.browser`.

For an isolated blocker screenshot, open
`chrome-extension://loammdknmfbkjnckaeeagnmakinknbck/blocker.html?curfew-demo=1`
from the loaded development bundle. That explicit fixture shows the LVBT task,
`instagram.com`, and the initial question without contacting the native host or
storing the answer field. Production builds remove the fixture data and ignore
that query. Do not use the screenshot fixture as enforcement acceptance.

The production artifact is `web/extension/dist/production`. It calls only
`studio.hypertext.curfew.browser`. The production build requires the separate
Web Store public key and the matching 32-character extension ID:

```sh
pnpm --filter @curfew/chrome-extension package:draft

# Upload the draft ZIP, then copy its Web Store public key and item ID.
CURFEW_BROWSER_EXTENSION_PUBLIC_KEY='<Web Store public key>' \
CURFEW_BROWSER_EXTENSION_ID='<Web Store item ID>' \
pnpm --filter @curfew/chrome-extension package:production
```

The draft command writes `web/extension/dist/curfew-browser-draft.zip` without a
manifest key. That artifact exists only to create the first Web Store item. The
production command parses the assigned public key as an RSA DER SPKI key. It derives the
extension ID and rejects a mismatch. It also rejects the development key or ID
when either appears in a production build. It writes the built extension to
`web/extension/dist/production` and the upload archive to
`web/extension/dist/curfew-browser-production.zip`. The archive contains only
the current build files and repeats byte for byte when those files do not
change. Both manifests require Chrome 120 or later. The release
engineer must copy the public key and item ID from the Chrome Web Store draft
before building. The engineer must then set the same item ID as
`CURFEW_BROWSER_EXTENSION_ID` in the signed app build.

The exact dashboard copy and permission declarations live in
`web/extension/store-listing.md`. The release engineer must use that file rather
than rewriting the privacy claims during submission.

## Permissions and rule lifetime

The extension requests `declarativeNetRequest`, `storage`, `tabs`,
`webNavigation`, `nativeMessaging`, and `alarms`. It requests host access only
for HTTP and HTTPS. The `alarms` permission is required because Chrome can
suspend a Manifest V3 worker. A timer in the worker cannot revoke an expired
grant or break. The worker keeps one next-expiry alarm and rebuilds the complete
ruleset against the current clock when that alarm fires. A separate 30-second
alarm reads policy and sends a heartbeat through `browser-host/1`. The worker
also keeps one bounded `get_policy` native-message wait open with the revision
of its installed signed policy. Curfew ends the wait when it publishes a new
revision. The worker replaces the complete ruleset before it stores that
revision as active. A host failure stops the wait without changing cached rules.
The next alarm refresh starts one new wait after the host recovers. Repeated
alarm events cannot create duplicate waits.

An active policy installs one priority-1 block rule for HTTP and HTTPS
`main_frame` requests. Exact-origin and segment-bounded path-prefix rules use
priority 100. Path matching is case-sensitive, while URL parsing still
canonicalizes origin hosts. Every rule names only `main_frame`, so images,
scripts, API calls, and other subresources remain outside this release.

The worker treats dynamic rules as derived state. When the base block is absent,
it first replaces every current rule with that block. It then refuses more than
999 allow rules and checks each allow expression through Chrome's regex support
API. When the base block already exists, the worker validates first and installs
the complete set in one atomic replacement. An unsupported expression, an
oversized expression, a quota overflow, or a rejected full update falls back to
the base block. Only the first active policy needs two successful updates, since
its fail-closed invariant outranks transient access to an existing allowed site.

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
worker ignores that event when its current policy already allows the target,
because another extension can produce the same Chrome error. The blocker URL
contains only that ID. The blocker page receives the current task
title, target hostname, and this question:

> What will you do on &lt;host&gt;, and what will you produce for &lt;task&gt;?

The worker observes top-level HTTP and HTTPS navigation while enforcement is
active. It does not inspect page content or subresources. Known destinations
stay local. For an unknown destination only, the worker sends a normalized
origin and path through `browser-host/1` to Curfew, which sends them to Docket
and Athena for review. The
initial justification must contain 20 through 1,000 JavaScript characters after
trimming. A challenge answer must contain 1 through 1,000 characters. The worker
shows these errors before native messaging, so invalid text does not become a
host failure or cooldown. It
removes credentials, query strings, fragments, default ports, and dot segments
before review. The worker accepts at most 8,192 UTF-8 bytes for each answer, and
the blocker page applies the same byte limit before native messaging. A
challenge replaces the one visible question and clears the one answer field.
The worker retains the original justification with the pending challenged
request, so a reload can send it unchanged as `justification`. The worker sends
only the new text as `challengeAnswer`. It never persists the challenge answer.
It does not persist a completed justification. It removes the pending request
and both strings after a grant, denial, task or
destination change, expiry, or abandonment. A grant must return a
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
inspect `chrome.storage.local` and confirm that a justification exists only for
one live challenged request and that no challenge answer exists.

Task 7 owns the Settings connection and interactive blocker capture. The current
automated suite does not claim that signed-app or Web Store acceptance has
passed. Rollback must disable the feature, remove the matching native-host
manifest, and remove every dynamic extension rule. If Settings cannot reach the
worker during rollback, the engineer must disable or uninstall the extension in
Chrome before removing the host.
