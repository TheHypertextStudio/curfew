# Task-scoped browser enforcement

This document tells Curfew maintainers how to preserve the policy and privacy
boundary when they connect the native host and Chrome extension. The next
implementation must keep Curfew as the only owner of access rules and grants.

## Decision

Curfew keeps one local work session. Docket reports the current work, and
Athena reviews an unknown destination. Neither service can install an allow
rule. Curfew validates Athena's proposed scope and sets a maximum lifetime of
30 minutes or the end of the current session, whichever comes first.

The current implementation covers the domain reducer and the direct Docket
OAuth/MCP client. The Chrome extension, native messaging host, Settings health,
and audit projection remain deferred. The sequence diagram in
`Documentation/browser-policy-sequence.mmd` shows the complete boundary that
those later slices must preserve.

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

## Privacy

Curfew sends Athena the normalized origin and path, the task and organization
identifiers, and the user's current justification or challenge answer. Curfew
must not persist the justification or challenge answer. It must not send URL
credentials, queries, or fragments. Later audit work may store the hostname,
decision, and scope kind. It must not store the full path or justification.

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

## Release and rollback

The release must keep browser enforcement off until Docket authorization and
the extension connection both succeed once. Release verification must prove
that an unknown page never loads before the extension blocks it. It must also
prove stale-heartbeat and offline behavior with the native host absent.

Rollback disables browser enforcement and removes the extension's dynamic
rules. Docket can retain its generic active-work resource and reviewer. This
slice does not add or change Curfew Sync or `curfew-protocols` contracts.

## Open work

The next slices must persist the latest policy snapshot, add the signed native
messaging queue, install and remove the native-host manifest, implement the MV3
extension, expose setup health in Settings, and add privacy-minimal audit events.
Administrator-level bypass prevention, other browsers, mobile enforcement, and
network filtering remain outside the first release.
