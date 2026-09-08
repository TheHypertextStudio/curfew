# Task-scoped browser enforcement

This document tells Curfew maintainers how to preserve the policy and privacy
boundary across the macOS app, native host, and Chrome extension. Maintainers
must keep Curfew as the only owner of access rules and grants.

## Decision

Curfew keeps one local work session. Docket reports the current work, and
Athena reviews an unknown destination. Neither service can install an allow
rule. Curfew validates Athena's proposed scope and sets a maximum lifetime of
30 minutes or the end of the current session, whichever comes first.

The current implementation covers the domain reducer, direct Docket OAuth/MCP
client, signed native host, `@curfew/chrome-extension`, and the Task Browser
Enforcement Settings panel. Signed-app/Web Store verification and audit
projection remain deferred. The sequence diagram in
`Documentation/browser-policy-sequence.mmd` shows the implemented review boundary.

## Session rules

Docket's `active-work/1` observation starts or continues a session when it
contains a task. Any observation with a null task retains the prior task locally,
whether tracking says running, paused, or idle. Curfew then reads that exact
task's ordinary Docket resource. A completed or canceled state ends the session.
An `archivedAt` timestamp also ends it. Missing or unauthorized task resources
leave the retained session unhealthy and fail closed. A different task creates
a new session and revokes old grants. Any terminal task in an active-work
observation ends retained work, even when its identifier differs.

Curfew permits one 15-minute break after each transition into paused or idle.
Starting the break consumes that eligibility. More paused or idle observations
cannot renew it. A running observation cancels an active break and resets the
transition detector.

## Destination and mapping rules

Curfew accepts only HTTP and HTTPS. It lowercases the host, removes credentials,
queries, fragments, and default ports, and resolves dot segments. It retains a
normalized path because Athena may recommend a path-prefix grant.

A persistent mapping selects exactly one task ID, project ID, or label ID. Its
scope is one exact origin or one path prefix. The initial allowlist is the union
of matching mappings, normalized task references, and the configured Docket web
origin. One validated constructor handles mapping, reference, and Athena scopes.
It rejects credentials, queries, fragments, relative paths, default-port drift,
and cross-origin grants. A root path prefix covers only its exact origin.
Unknown destinations remain blocked during Docket or Athena failure.

## OAuth and service boundary

Curfew does not hardcode a Docket client ID. It registers a public OAuth client
through `/api/auth/oauth2/register` and stores the issued ID before it starts
authorization. The client requests only `work:read`, `agents:run`, and
`offline_access`. Curfew stores the client ID, access token, refresh token, and
expiration in the `studio.hypertext.curfew.docket` Keychain service. The
staging build uses a separate endpoint set and Keychain service.

The MCP transport sends `initialize`, `notifications/initialized`,
`resources/read`, and `tools/call` over Streamable HTTP. It accepts one
`event: message` SSE event with one `data` field. It rejects malformed frames
and responses that do not use JSON-RPC 2.0. It matches each response to the
request identifier captured before the network wait. It requires Docket to
negotiate the requested MCP protocol version, and concurrent first calls share
one initialization. OAuth
registration and token responses have a 32 KiB limit. MCP responses have a
1 MiB limit.

One HTTP 401 resets the MCP session, refreshes OAuth, and retries the operation
once. One HTTP 404 or 410 from an established MCP session resets that session,
initializes a new one, and retries once. A second failure does not loop. Curfew
reads `docket://hub/active-work` every 30 seconds without a session and every
five seconds while it retains a session. Curfew rejects a Docket observation
whose `observedAt` value is older than the last accepted value. Exact-task reads
use the retained session and task identifiers. Their Mac timestamps do not
change the active-work observation watermark.

## Settings and local setup state

Settings stores Docket-connected-once and Chrome-connected-once facts in the
same local defaults suite as the app. An authenticated active-work response
records the Docket fact even when Docket returns no current task. A fresh
extension heartbeat records the Chrome fact. Curfew does not erase either fact
when Docket, Chrome, or the native host later becomes unavailable.

The enforcement toggle stays off and disabled until both facts exist. After
setup, live health and setup history remain separate. Settings marks a missing
authorization, failed host installation, unavailable host, or heartbeat older
than 60 seconds as unhealthy without clearing the retained policy. Turning the
toggle off publishes an empty policy so the extension removes its rules.
Turning it on republishes the current or retained session.

Settings stores each validated task, project, or label mapping locally. It does
not sync mappings or infer them from task content. The fixed break control calls
the same reducer as native review and publishes the resulting 15-minute expiry.
Running work, a missing session, and a consumed paused-session break disable the
control.

## Privacy

Curfew sends Athena the normalized origin and path, the task and organization
identifiers, and the user's current justification or challenge answer. Curfew
must not persist the justification or challenge answer. It must not send URL
credentials, queries, or fragments. Later audit work may store the hostname,
decision, and scope kind. It must not store the full path or justification.
The extension may persist that a challenge exists and the reviewer's targeted
question. It retains the initial justification only while that challenged
request can continue across a reload. The follow-up sends that original value
as `justification` and sends only the new value as `challengeAnswer`. The
extension never persists the challenge answer. It clears both fields when the
review resolves, expires, changes session or destination, or is abandoned.

The browser policy snapshot contains only the task ID and title. It keeps
expiring grants separate from base scopes, and consumers evaluate grant and
break expiry against their current time after restoring a cached snapshot. It
does not
contain task descriptions, workspace names, project summaries, label names, or
raw reference URLs. The system does not inspect page subresources in this
release. It reviews only top-level destinations. Curfew stores OAuth secrets in
Keychain. It must not place them in the policy snapshot, extension storage,
logs, or audit records.

Curfew binds each destination review to the session ID that existed before the
Athena request. A task change during that request discards any grant, challenge,
or denial. The discarded result cannot add a grant or cooldown to the new task.
Curfew also rejects a decision that contains fields from more than one outcome.
Every required decision string must contain a non-whitespace value.

The extension keeps one bounded native-host policy wait open against the
revision in Curfew's signed record. Curfew publishes a new random revision in
the same atomic write as each policy. The extension installs that policy's
rules before storing its revision. It also reads policy and sends a native-host
heartbeat every 30 seconds.
It serializes policy refreshes, expiry rebuilds, review preparation, and review
response application. It does not hold that queue while it waits for the native
reviewer. A changed session can install its rules at once, and the late review
response fails its session check. A host failure writes no heartbeat and leaves the cached
restrictive policy in force. The next alarm refresh restarts the single policy
watch after the host recovers.

Debug builds provide isolated Settings and blocker fixtures for automated tests
and screenshots. The Settings fixture uses a temporary signed browser store,
in-memory Docket credentials, and shutdown-disabled app settings. The blocker
fixture accepts only `curfew-demo=1` in development output. It never calls the
native host and never stores or sends the text field. Production blocker output
contains no fixture task data.

## Release and rollback

The release must keep browser enforcement off until Docket authorization and
the extension connection both succeed once. Release verification must prove
that an unknown page never loads before the extension blocks it. It must also
prove stale-heartbeat and offline behavior with the native host absent.

Rollback must disable browser enforcement, remove the flavor's native-host
manifest, and remove the extension's dynamic rules before uninstall. Docket can
retain its generic active-work resource and reviewer. This slice does not add or
change Curfew Sync or `curfew-protocols` contracts.

## Open work

The next slice must add privacy-minimal audit events. Release work must create
the Chrome Web Store draft, set the production identity in the signed app,
verify the packaged host and extension together, and run the rollback drill.
Administrator-level bypass prevention, other browsers, mobile enforcement, and
network filtering remain outside the first release.
