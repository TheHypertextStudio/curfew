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
contains a running or paused task. An idle observation retains the prior task
locally. Curfew then reads that task's ordinary Docket resource. A completed,
canceled, or archived state ends the session. A different task creates a new
session and revokes old grants.

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
origin. Unknown destinations remain blocked during Docket or Athena failure.

## OAuth and service boundary

Curfew does not hardcode a Docket client ID. It registers a public OAuth client
through `/api/auth/oauth2/register` and stores the issued ID before it starts
authorization. The client requests only `work:read`, `agents:run`, and
`offline_access`. Curfew stores the client ID, access token, refresh token, and
expiration in the `studio.hypertext.curfew.docket` Keychain service. The
staging build uses a separate endpoint set and Keychain service.

The MCP transport sends `initialize`, `notifications/initialized`,
`resources/read`, and `tools/call` over Streamable HTTP. Curfew reads
`docket://hub/active-work` every 30 seconds without a session and every five
seconds while it retains a session. Curfew rejects a Docket observation whose
`observedAt` value is older than the last accepted value.

## Privacy

Curfew sends Athena the normalized origin and path, the task and organization
identifiers, and the user's current justification or challenge answer. Curfew
must not persist the justification or challenge answer. It must not send URL
credentials, queries, or fragments. Later audit work may store the hostname,
decision, and scope kind. It must not store the full path or justification.

The system does not inspect page subresources in this release. It reviews only
top-level destinations. Curfew stores OAuth secrets in Keychain. It must not
place them in the policy snapshot, extension storage, logs, or audit records.

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
