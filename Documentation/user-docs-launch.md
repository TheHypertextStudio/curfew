# User help and the Plus launch

The Mintlify site in `web/docs/` is end-user help. Its primary journeys are
setup, scheduling, lockout, deliberate exceptions, reflections, Plus activation,
assistant setup, and recovery. License signing, API shapes, and provisioning
remain operator material; see `license-worker-bootstrap.md`.

## Publication boundary

The owner requested publication of the user-help rewrite on 2026-10-13 before
activation-flow work. Publish these docs with the existing notices that Plus
is not on sale, iCloud sync and Calendar are unavailable, and the public Mac
installer has not been released. Feature and purchase-flow launch claims remain
blocked on the acceptance rows below. This publication does not enable a
feature, open checkout, or deploy a new app or license service.

The activation instructions use the release candidate's About panel labels.
Link to the public `/download` and `/restore` pages on `https://thecurfew.app`;
checkout activation starts from the customer's own confirmation page. Draft
GitHub asset URLs and private checkout session or restore-token URLs must not
appear in help. Keep the unavailable-installer and Plus-sale notices until the
cutover owner confirms the corresponding publication. Docs preparation does
not authorize a site, appcast, account, license-service, or billing cutover.

Publishing uses the existing Mintlify Git integration. Current published routes
`install`, `schedules`, `accounts`, `mcp-guide`, `cli`, and `licensing` are retained.
`docs.site.json` owns navigation; regenerate `docs.json` with `pnpm docs:config`.
The first-party `/docs/licensing` path proxies the published Mintlify guide.
Verify both the product-site path and Mintlify host after docs publication;
the product-site proxy is a separate deployment from publishing Mintlify docs.

Before publishing launch availability claims, complete the rows below against
the exact signed release and approved purchase environment. Record the artifact,
environment, date, result, and evidence here or link to existing release evidence.
Until then retain availability notes, including those on the home page and in
troubleshooting. Remove the launch-status regression assertion only alongside
recorded launch evidence; continue testing routes, metadata, and recovery copy.

| Acceptance | Evidence/status |
| --- | --- |
| Install and complete setup; confirm actual UI labels, permission behavior, and first boundary | Pending signed-release walkthrough |
| Lifetime checkout → confirmation key → activation → offline relaunch | Pending approved purchase and signed-release proof |
| Subscription checkout → activation → renewal → canceled/unpaid expiry; free boundaries remain | Pending approved purchase and signed-release proof |
| Missing, delayed, malformed, and unverifiable license recovery | Copy covered by `scripts/user-docs.test.mjs`; runtime cases pending |
| iCloud setup on two Macs, schedule propagation, offline reconnect, pending-change handling, and privacy | Pending provisioning and two-Mac proof; feature disabled in current release |
| Widget addition, supported sizes, state refresh, and deactivation | Pending signed-build widget-gallery proof |
| Calendar grant/deny/revoke, today's events, and no automatic extension promise | Pending signed-build proof; feature disabled in current release |
| Assistant add/restart/read, approval/denial, and disconnect | Pending real assistant walkthrough; source labels checked |
| CLI examples from distributed bundle, including snapshot/budget limitations | Local bundled help checked; published-release installation remains pending |
| Safe fixture screenshots for setup, schedule, and activation; no real journal/key data | Setup and schedule captured manually from the ephemeral Debug fixture; activation screenshot held until conflicting in-app copy is corrected; release comparison pending |
| Rendered Mintlify pages at desktop/narrow widths, light/dark, keyboard navigation, and links | Local licensing/setup review passed, including 390-pixel layout and keyboard navigation; search needs Mintlify login and hosted verification |
| Actual Mintlify `/docs` hosting, bookmarked routes, assets, and navigation after publication | Mintlify successfully published `bdd703f1a6832da1f2ab99e222908a07b37d0bf5` on 2026-10-13. All 16 pages and both screenshots returned 200; titles, rendered navigation, activation anchor, and hosted search were verified at `https://curfew.mintlify.dev/docs`. First-party `/docs/licensing` remains 404. |

## Claims requiring launch review

- Current source supports lifetime and subscription keys. Plans, prices, billing
  cadence, cancellation handling, and license coverage must agree with checkout
  and the owner-reviewed terms. Guides link to prices rather than inventing them.
- `landing/src/pages/terms.astro` and `refund.astro` still contain legal-review TODOs,
  including subscription cancellation/refund treatment. They also describe
  Stripe as merchant of record; verify the actual commercial arrangement before
  launch. This rewrite does not ratify that claim or change legal policy.
- `LicenseView.swift` still suggests keys may arrive by email; delivery currently
  shows the key on the confirmation page and emails only the payment receipt.
  Correct the app helper copy with a failing-first UI/copy test before launch.
- Calendar currently displays events; documentation must not promise automatic
  schedule exceptions. CLI status ignores temporary extensions/overrides, and
  its budget read uses the calendar-week boundary rather than custom reset days.
- Historical `PRIVACY.md` and the landing privacy policy contain older network
  and storage statements. Reconcile them with actual subscription refresh,
  updates, assistant-provider processing, and release sync behavior before launch.
- Remote account/phone control is outside these local assistant instructions.
  Add a separate guide only once its end-user setup is present and verified.
- Disabling the MCP app toggle does not gate direct local read tools. User help
  requires removing the assistant's server configuration and restarting it;
  any future claim that the toggle revokes read access needs a product fix.
- Journal's GUI export covers only the current week. User help supplies a CLI
  date-range export for older retained entries before destructive uninstall.
  Legacy CLI override requests are rejected by the app; the guide directs users
  to the lockout screen. Assistant countdowns have saved-schedule limitations.

## Rewrite record

- Approved plan: replace developer docs with task-oriented user help; prepare
  the upcoming Plus launch and retain existing public routes.
- Failing-first proof: `node --test scripts/user-docs.test.mjs` failed all six
  cases against the old site: missing journeys, developer API links, stale
  activation location, misleading receipt/payment recovery, assistant privacy,
  and absent launch availability notes.
- Implementation: 15 guides, five navigation groups, corrected confirmation
  help and recovery messages, and updated repository documentation.
- Verification on 2026-10-13: all 21 repository Node script tests passed,
  including 11 public-help regressions; the new CI job runs the public-help
  suite. `mint validate` and `mint broken-links --check-anchors --check-external`
  passed. Desktop, phone-width, light/dark, and keyboard navigation were inspected
  in the actual local Mintlify preview. Local search requires Mintlify login;
  it was not represented as verified.
- Required native checks passed: SwiftFormat apply/check, strict SwiftLint
  (157 files, zero violations), all 292 unit tests, and the Debug build.
  SwiftFormat corrected five pre-existing comment markers in
  `SundownPalette.swift`; this is a comment-only edit with no runtime effect.
- Automated screenshot capture was attempted with the two existing
  `MarketingCaptureTests` methods for configuration and Getting Started. The
  UI runner failed before executing tests: “Timed out while enabling automation
  mode.” No passing UI-test result is claimed. Setup and schedule images were
  instead captured and inspected through native UI control of the ephemeral
  Debug demo fixture, with no enforcement enabled or real settings accessed.
- Fresh reviewer found four documentation inaccuracies above. Four focused
  regressions were observed failing before correcting disconnection, older
  reflection export, CLI override behavior, and assistant countdown claims.
- Ruling: public instructions target the actual available behavior and label
  the upcoming launch; they do not describe desired automatic calendar
  extensions, remote control setup, or a working CLI override. If those product
  capabilities change, update the guides and their regression cases together.
- Ruling: screenshots are explanatory fixture images, not signed-release
  acceptance. The required comparison with the launch artifact remains pending.

## Risk and rollback

The copy audit on 2026-10-13 removed self-narration and unnecessary comparisons
across all 15 guides and the purchase-confirmation page, including commentary
about what the subscription date does not confirm. Launch availability is now
stated directly. Regression coverage checks editorial phrases while retaining
the factual disconnection, export, countdown, billing, and launch limitations.
The audit changes wording, not product behavior or commercial policy. All
22 repository script tests pass, including 12 public-help regressions.
Mintlify build validation and anchor/external link checks pass; the shortened
activation section was inspected in the live preview.

The primary risk is publishing launch instructions before the corresponding
features or purchase flows work. Availability notes and the publication boundary
above mitigate that risk. No pricing, protocol, app behavior, feature flag, or
production setting is changed. Existing route names remain stable. Revert this
documentation change set to restore the prior content; no data migration is needed.

## Publication reconciliation

Current main renamed native Settings sections to General, Limits, Warnings, and
Connections. Public instructions now use those labels and the current license
field. Preserve the newer account guide and the unavailable-installer notice.
The docs commit is replayed alone onto current main; no historical native
changes are included. The landing confirmation copy follows its Astro source
location. Publishing the docs does not deploy the landing site.
