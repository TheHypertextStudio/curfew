# Remote MCP acceptance evidence

Snapshot: 2026-10-12. This is an evidence ledger, not a claim that the full
download-to-phone-control flow is released. No new lock or foreground UI
interaction was used for this audit.

## Verified staging evidence

- Curfew Sync PR #42 was rebase-merged as `0d08fc64cf1c029cec0f18825bcd166dd37951aa`.
  Deployment run `38217175834` succeeded, publishing Worker version
  `6a600727-030b-4cda-bae8-113bd08c4209`. All 454 Worker and 7 DOM tests passed,
  together with typecheck, lint, formatting, and deployment checks.
- Live authenticated `list_devices` reported Studio Dev Mac online, with native
  status received at `2026-10-12T07:25:03.318Z`. Before deployment, the same
  listing incorrectly reported offline despite a fresh native heartbeat.
- Live authorization-server metadata advertises the account staging issuer,
  authorization and token endpoints, S256 PKCE, and CIMD support. This is
  discovery evidence, not proof of every OAuth or MCP conformance requirement.
- `launchctl print system/studio.hypertext.curfew.studio.dev.daemon` reports the
  registered Studio helper, 15-second run interval, and last exit code zero.
  Its exited state between scheduled runs is not an installation failure.
- Read-only lookup of the earlier authorized command
  `d5c310ce-7bcf-4ce8-9cd0-87c98ba3a50a` returns applied at
  `2026-10-12T07:00:55Z`, with deadline `2026-10-12T07:05:55Z`.
  The Studio app audit stream records a locked-to-working transition and
  lockout end at that deadline. Neither observation proves visible blocking.

## Remaining acceptance and provisioning

- Claude phone execution remains unverified. Codex was used because Claude was
  out of quota. Do not label that substitute as a phone test.
- Visible physical enforcement and remote-unlock behavior remain unverified.
  Do not issue another lock, launch UI automation, or take focus to obtain proof
  while the user's no-lock/background-only constraint remains active.
- No downloadable GitHub release exists at this snapshot. The Curfew repository
  exposes only `SPARKLE_PRIVATE_KEY` among repository secret names; its release
  workflow also requires Apple signing/notarization and Cloudflare credentials.
  A locally installed company-signed development build is not a notarized
  downloadable release. Do not export signing credentials or create replacements
  as an implicit audit step.
- The production coordinator's GitHub environment has no secret names configured,
  and `curfew-account.hypertext.studio` does not resolve from this Mac. Production
  account onboarding therefore cannot be claimed operational. Staging deployment
  does not satisfy production provisioning.
- Configurable Apple sign-in and its required TOTP flow need real provider
  acceptance; source configuration and automated tests are not provider proof.
- The coordinator still retains Dynamic Client Registration as a compatibility
  bridge for Claude. Its architecture documentation explicitly defers retirement
  until replacement client onboarding has real connector acceptance. CIMD
  discovery and Codex sign-in alone do not close that deprecation task.
- Device-neutral coordinator schemas and daemon-injected local/remote backends
  exist in source. That is an architectural foundation, not Windows runtime
  acceptance or full specification-conformance certification.

## Change and rollback boundaries

This audit changes documentation only: no app behavior, credentials, package
versions, migrations, permissions, or wire shapes. Existing automated coverage
stays unchanged. Revert the documentation commit if its snapshot is wrong;
update this ledger when stronger evidence becomes available rather than marking
the incomplete acceptance items complete.
