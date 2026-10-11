# Curfew website and documentation

Curfew's marketing frontend lives in `landing/` and uses Astro's static profile.
The canonical origin remains `https://curfew.hypertext.studio`. Product docs live
in `web/docs/` and remain a Mintlify project. The native app, Curfew Sync, license
issuer, Stripe webhook, signed downloads, and Homebrew cask retain their existing
release owners. Website checks never issue licenses or mutate customer data.

## Checkout setup

Run `./bootstrap worktree prepare` for the native checkout, then use the shared
website lifecycle from the repository root:

```sh
./run setup
./run doctor
./run dev
./run check
./run build
```

Root `./run` delegates to the frontend-owned `landing/run`. That launcher
downloads checksum-pinned release-engineering `v0.1.8`; it delegates
to the existing bootstrap engine and native pnpm commands. Python 3.11+, Node
24.20.0, and pnpm 11.9.0 are declared in `landing/studio.yaml`. Marketing/docs dependencies and their lockfile live in the independent `landing/`
workspace. Root `package.json` provides thin `pnpm --dir landing` command facades;
the existing `web/` licensing/extension workspace and lockfile stay independent.
The lifecycle declaration and conformance guard are scoped to `landing/`; they
do not absorb the independent native release workflow. `landing/bootstrap`
delegates to the original repository bootstrap. Future shared candidate callers
must invoke the root facade or use `--root landing`, preserving candidate paths
relative to the frontend declaration.
Native app setup and checks
continue to use `bootstrap` and `just check`; the website component does not
replace native setup. `./run dev` starts Astro at `http://127.0.0.1:4321`.

**Adoption status:** `@thehypertextstudio/web-config`, `web-docs`, and `web-tokens`
are pinned to the published 0.0.1 release. Shared read-only registry acceptance
passed in run `38116980056`. Curfew's native run `38119577450` then resolved a
fresh graph with its ephemeral job token, performed a script-disabled frozen
install, and passed peer validation. `landing/pnpm-lock.yaml` adopts that reviewed
artifact byte-for-byte; its three shared package integrities match published
shipping bytes. Website/docs run
[38161233241](https://github.com/TheHypertextStudio/curfew/actions/runs/38161233241)
passed frozen installation, source/parity checks, native docs validation and the
local Worker browser suite at `680f50c943be80ee1dec30376fb78008fc79f570`.
Native CI run
[38161233239](https://github.com/TheHypertextStudio/curfew/actions/runs/38161233239)
also passed. Main `a5b5a699bcce3d136a0d312789384f8180cb08c0` integrates that
reviewed tree through linear history. These checks do not establish provider
publication or a fresh local `./run setup` result. Do not commit file-based package
overrides or represent earlier local validation as registry acceptance. All consumed
private packages now grant this repository GitHub Actions Read access. CI uses only its ephemeral `github.token` with `packages: read`, through
trusted `actions/setup-node` user configuration; do not create classic personal
access tokens or move browser/CLI credentials into npm. Provider authentication
uses workload identity where supported. Do not add credential values to
`landing/.npmrc`.

`doctor` checks command availability and declared runtime versions. A Node
version failure means the shell is using another Node: run the lifecycle through
the declared managed runtime (for example `pnpm exec ./run doctor` after install).
Setup does not provision Workers, connect Mintlify, or change DNS/routes.

## Configuration

| File | Ownership and purpose |
| --- | --- |
| `landing/studio.yaml`, `landing/studio.lock.json`, `landing/run`, root `run` | Native lifecycle component and checksum-pinned shared release |
| `landing/package.json`, `landing/pnpm-workspace.yaml` | Exact site/docs toolchain pins and reviewed build-script allowlist |
| `landing/astro.config.mjs` | Static output, existing HTML aliases and canonical site origin |
| `landing/src/layouts/Page.astro` | Shared page metadata and shared token import |
| `landing/style.css`, `landing/images/` | Existing product appearance and original asset bytes |
| `landing/wrangler.site.json` | Independent site Worker, asset routing, separate staging/production identities |
| `web/docs/docs.site.json` | Product-owned Mintlify branding/navigation/overrides |
| `web/docs/docs.json` | Generated committed Mintlify configuration |

The shared foundations supply configuration and opt-in tokens. Curfew keeps its
system typography, marketing palette, layout, and content. Docs primary orange is
the approved accessible `#b25e30`; its existing light/dark variants remain.

| Runtime input | Purpose | Current value or rule |
| --- | --- | --- |
| `ASSETS` | Immutable built Astro assets | Bound only to this site's artifact |
| `DOCS_MODE` | Select retained HTML guide or accepted Mintlify proxy | `html-guide` in both environments |
| `DOCS_UPSTREAM` | Explicit independent Mintlify origin | `https://curfew.mintlify.site` |
| `STUDIO_SOURCE_SHA` | Reviewed source identity | Injected by shared release owner |
| `STUDIO_ARTIFACT_SHA256` | Complete artifact ZIP identity | Injected after archive hashing |
| `STUDIO_CANDIDATE_ID` | Approved immutable workflow candidate | Injected by shared release owner |

There are no database, license-signing, Stripe, production-write, or app-auth
bindings in the frontend. The current success page's license URL is intentionally
empty and its visible support error remains intact. Opening a synthetic checkout
URL during tests must not call the license issuer. Do not open the sale gate as
part of hosting migration.

## Local site and docs development

```sh
pnpm dev                     # Astro source preview, port 4321
pnpm site:build              # Static HTML/assets
pnpm site:preview            # Local workerd frontend, port 4325
pnpm site:check              # Worker tests, product contracts, typecheck, lint, build, parity
pnpm site:test:acceptance    # Chromium, Firefox and WebKit against local workerd
pnpm docs:config
pnpm docs:config:check
pnpm docs:dev                # Pinned Mintlify local preview, normally port 3000
pnpm docs:check
```

`docs:config` merges the versioned Mintlify base with `docs.site.json` and writes
sorted `docs.json`. Change product inputs, regenerate, and review both files.
Navigation arrays remain product-owned. `docs:check` rejects drift, validates
Mintlify MDX/config, checks local links/anchors/redirects/snippets, and runs native
accessibility validation. The exact local `mint@4.2.854` is used. Its matching
ReactDOM dependency correction is documented in `landing/pnpm-workspace.yaml`.

The HTML content baseline in `verification/website/content-baseline.json` was
captured before conversion. `site-parity.py` compares all nine outputs' text,
links, images, anchors, metadata, body classes, inline-script hashes, and original
asset digests. The browser suite verifies direct routes, `.html` aliases, reload,
Back/Forward, keyboard navigation, reduced motion, safe license error behavior,
release metadata, and unknown-route 404s. Native app behavior remains covered by
its existing suites; no native code changes are part of this frontend migration.

## CI and review

The `Website validation` and `Docs validation` checks are required before merge
to the Mintlify publishing branch, along with existing native checks. The website
workflow uses package-read permission and no production provider credentials.
The reviewed registry lock and these checks passed in the source acceptance
record above. Review configuration with content; inspect keyboard use and narrow
layouts in local previews. Keep native release ordering, sale gate, and distribution
checklists intact.

### Proposing the real registry lock

`website.yml` has an artifact-only `Proposed frontend registry lock` job. Once the
workflow is registered on the default branch, run its manual dispatch with
`refresh_dependency_lock=true`. Before registration, the explicitly authorized
fallback runs only for a **draft** pull request whose head and base repositories
match and whose head is exactly `codex/company-website-standardization` in this
repository. Forks, other branches and ready pull requests cannot enter that
fallback. It checks out the exact head SHA with credential persistence disabled.

The job uses declared Node 24.20.0/pnpm 11.9.0 and a temporary consumer containing
only `landing/package.json` and `landing/pnpm-workspace.yaml`. It copies no prior
lock, backend workspace, dependency directory, environment file or pnpm hook.
It generates a new registry lock, performs an independent script-disabled frozen
install, then runs native `pnpm peers check`. The job token exists only in that
resolution step; setup-node's user config contains a literal environment
placeholder and is removed at step exit. No provider token, Actions write
permission, source commit or deployment is involved.

The artifact contains the proposed lock, exact manifest/policy inputs, installed
direct-dependency report, peer report and successful acceptance receipt with the
source SHA, workflow run/attempt and SHA256 input/lock digests. A failed job may
retain a partial lock and diagnostic report; absence of a successful receipt is
not acceptance. Download and review that artifact before any canonical lock
adoption. Run `38119577450` produced the successful reviewed receipt; its exact
lock is now adopted. Lock SHA256 is
`56a7f31e90f34abb7e66a910e870d3699d2a8f81d9d5dc071b413a535b0ee122`.
The original receipt source is `1cc3b241d5fb894cb75eac6371b9761f127ce57b`;
rebasing the six migration commits onto current production/main
`3efbd4fd3b4a9786e7eabd90904259fdb0990448` preserved the exact manifest and
workspace policy hashes, all three upstream native commits, and both docs sides.
The native receipt establishes registry resolution/frozen replay/peers with scripts
disabled; it does not establish frontend lifecycle, browser or provider acceptance.

After the exact trusted checkout, the proposal job checks whether the canonical
frontend lock is tracked. If present, the resolver/toolchain/upload steps skip and
normal website/docs checks run against the frozen lock while the PR stays in draft.
A missing lock retains artifact-only proposal mode. Explicit manual refresh still
resolves a fresh proposal once the workflow is registered. Frozen installation
checks dependency and policy consistency; no fixed input-hash gate blocks future
reviewed dependency updates.
Main integration stays a separate decision because the existing Pages publisher
may react to it. No main merge, production cutover or provider write is authorized
by this workflow.

pnpm 11 retains its default 1440-minute release-age protection. The workspace
exempts only the exact approved immutable internal releases
`@thehypertextstudio/web-config@0.0.1`, `web-docs@0.0.1` and `web-tokens@0.0.1`;
there is no scope wildcard, third-party exception or lockfile trust bypass.
Candidate `38116243716-1`, promotion `38116605945` and fresh registry verification
`38116980056` established that these published 0.0.1 packages match the reviewed
shipping bytes. Manifest SHA256 is
`097bb8cd7f4bb7341bb9bfdc48c79cc0c855a95c3b25a225374c1f9da3f58fa4`.
The [version-specific exclusion policy](https://pnpm.io/settings/dependency-resolution#minimumreleaseageexclude)
is needed only to consume that approved release during its first 24 hours.

## Mintlify publishing and routing

Authenticated inventory identified the existing project `curfew` in organization
`hypertextstudio` and upstream `https://curfew.mintlify.site`. On October 10, 2026,
it was **unconnected**, its initial update failed, and there was no successful
source-bound deployment. The selected repository is `TheHypertextStudio/curfew`,
source `web/docs/`, branch `main`. On October 11, Chrome confirmed the existing GitHub authorization
and Studio installation already include Curfew; no new installation or consent
was required. The unsaved project form selects organization `thehypertextstudio`,
repository `Curfew`, branch `main`, source `web/docs` (UI renders `/web/docs`).
The form was not saved; no connection or source-bound publication was accepted.
Reviewed main `a5b5a699bcce3d136a0d312789384f8180cb08c0` now contains
`web/docs/docs.json`, the approved accessible primary `#b25e30`, and licensing
navigation. Confirm those exact Git settings when saving the existing connection;
preserve project `hypertextstudio/curfew` and its subscription. Repository access
discovery is complete. The saved integration and actual successful deployment
identity/source SHA remain provider gates.
The authenticated dashboard reports the Pro trial ended and hosted previews are
unavailable; use the pinned local preview. No subscription change is required
for local adoption.

At 2026-10-11 08:33 UTC, production `/docs` returned a Mintlify 404 through
the Pages middleware introduced by the then-current main `2c56e068`. Both the
previously verified `.site` upstream and the new `.dev` target return the same 404 body.
Integrated source restores HTML-guide mode by default in the Pages middleware
and Worker. The accepted filtered Pages preview serves that guide, but the retained
production deployment still uses the older source; its separately reviewed Pages
repair awaits production approval. This is not a claim that the live route has
recovered or that Mintlify has published the new source.
Keep that guide until Mintlify publishes reviewed source and the complete proxy
passes acceptance. Setting `DOCS_MODE=mintlify` activates delegation of `/docs`,
`/docs/*`, `/_mintlify/*`, `/mintlify-assets/*`, and `/api/request` (mapped to the
Mintlify search endpoint). It always fetches the explicit Mintlify origin,
preserves path/query, forwards the actual public host/protocol, removes frontend
cookies/authorization, preserves upstream errors, and rewrites redirects that
name the upstream to the requesting frontend origin. External redirects remain
external. No generic fallback converts unknown routes to a successful page.

Before activation, verify Mintlify's subpath setup/canonical origin, HTML, static
assets, search GET/POST, redirects, anchor links, and mobile/keyboard behavior
through the public `/docs` prefix. Capture the exact successful Mintlify deployment
and reviewed source SHA separately from the Workers artifact identity. A passing
local docs check does not prove hosted publishing or proxy delivery.

## Candidate deployment and recovery

`./run build` performs Astro build/parity and Wrangler's local dry-run bundling,
then assembles `landing/build/site-candidate/{modules,assets,wrangler.site.json}`. This is
candidate construction; promotion must use the same archive bytes without another
build. `GET /__studio/release` returns all three release fields with `no-store`;
it returns 503 until the shared owner injects a complete identity.

GitHub Actions is the release owner. The frontend launcher and lock now use published
release-engineering `v0.1.8`, revision `878260def7229cd3df7f752b32e5581230c5db2d`,
archive SHA-256 `61f746429fc0ffc7826df2bde61ee4d41323fb5fa0c9f8661255040e7838afd4`.
The pin helper verified the release checksum and immutable tag. Native lifecycle pins
and the root wrapper retain their existing owner/version. The root website workflow
records the exact future candidate/promote references at that same revision.

The shared v0.1.8 reusable callers support `root: landing`; the default root
selects Curfew's independent native declaration and must never be used for the
marketing release. The actual registry lock is accepted; caller activation remains
gated on an isolated Workers provider preview and recovery evidence. The source
declaration now selects the shared Workers adapter, exact Wrangler 4.148.0, `modules/worker.js`, and `assets/`
inside the retained archive. It does not introduce another deployment adapter.
The immutable source configuration is retained separately by the shared candidate;
promotion freezes its file paths to the extracted archive and injects release identity.

The intended marketing preview is `curfew-site-staging.hypertext.studio`, owned
by Worker `curfew-site-staging`. The existing `curfew-staging.hypertext.studio`
is the account backend preview and must not be reused. Production's intended
Worker is `curfew-site-production` at `curfew.hypertext.studio`. These are source
identities, not claims that the marketing resources exist. Both Worker environments
still have empty routes, workers.dev disabled, and HTML-guide docs mode. Provision
and capture the isolated marketing preview explicitly before any promotion,
preserving account `2500680a3b2b0fe6a011c1c25fed5008`. Production routing and the
existing Pages publisher remain unchanged until reviewed cutover.

Before cutover, retain the current Pages deployment, complete route/DNS snapshot,
and prior artifact/configuration. The earlier anonymous production baseline observed `/account` returning
the same homepage bytes as `/` and an arbitrary unknown URL: the existing Pages
SPA fallback reports a false 200. Read-only provider inventory found no production
account Worker. The frontend keeps the `/account` link destination; it does not
implement a nonexistent account backend or reproduce the generic SPA fallback.
Account availability and the current source/production mismatch need an explicit
product disposition before cutover acceptance; unknown site URLs must return 404. Current observed Pages recovery deployment is
`a4d2490c-3620-491f-b868-e44131a36597` (main `2c56e068`, observed October 11); revalidate the live prior deployment at
cutover. Promote only the reviewed immutable candidate after source/config/digest,
workerd, provider preview, download/link, error, and routing acceptance. Switch
hosting through the shared guarded cutover process. Verify public metadata and
critical routes immediately. Observe 24 hours before the next company cutover,
disable competing Pages auto-publication, and retain the old host/recovery data
for 14 days. No cutover, observation, or legacy-host retirement is complete yet.

Recover the prior complete frontend release and matching route/domain state using
release-engineering's guarded recovery commands and retained artifact/config;
verify canonical URLs, unknown 404s, CSS/images, success error behavior, and docs
prefix afterward. Keep the license/download services on their existing hosts.
For Mintlify, restore a reviewed config/content revision through its verified Git
integration and verify the resulting provider deployment and public proxy. Revert
shared dependencies, product inputs, and generated config together.

## Ownership and troubleshooting

The Curfew repository owns marketing and product documentation. The shared
`web-platform` repo owns package/config conventions; `release-engineering` owns
immutable deployment/promotion and recovery. Native release incidents continue
to use `Documentation/RELEASE.md` and `scripts/release-checklist.md`.

| Failure | Action |
| --- | --- |
| Registry 404/permission error | Confirm initial package publication and existing package-read access; do not substitute a floating source URL |
| Frozen lockfile unavailable | Verify package-read access and commit the actual registry-resolved lockfile |
| Generated config drift | Run `pnpm docs:config`, review both JSON files, rerun checks |
| Mintlify framework extraction error | Preserve failure evidence; retry serially after download/cache is healthy |
| Docs upstream 404 or recursive configuration | Keep `html-guide`; fix the existing project/subpath, never fetch the public frontend recursively |
| Missing release metadata | Use the shared candidate owner injection; do not hardcode a digest into the artifact |
| Product parity mismatch | Restore missing content/links/assets/script behavior and rerun the baseline gate |

## Current production source reconciliation — October 11

The earlier hosted website/docs run `38120078658` passed against migration head
`f6277a5` and the earlier main `3efbd4f`. Production subsequently deployed main
`2c56e0680605533a953f90cc6f3268e3ecec6d43` at 07:25 UTC. All 55 intervening
upstream commits, including native application, CurfewKit relocation, backend,
UI capture and release/appcast work, are preserved beneath the eight rebased
migration commits. Earlier acceptance receipts are historical; current source
and provider acceptance must be recorded independently.

The five changed current HTML contracts (index, privacy, refund, success, terms)
are ported to Astro. Four guide/redirect/security/retention pages are unchanged.
The latest sky/reveal scripts, styles, metadata, JSON-LD, canonical origin,
legal/licensing copy, Plus sale boundary and account/download URLs are retained.
The current HTML references `images/lockout-overlay.png`, which was absent from
main. The intended 3024×1964, 798,009-byte screenshot was recovered from tracked
commit `0efe52d`; SHA256 is
`80cbf81a47d601e802615dd5d8c6c188cf0df8aeae3f465d29d4f919bcd4b3be`.
Its visible content matches the retained alt; no replacement artwork or copy
change was introduced. This restored asset is the explicit source-tree correction.

The physical raw Pages files remain in `landing/` for the current publisher and
native appcast owner. `prepare-site-assets.mjs` copies a fixed public allowlist to
ignored `landing/.site-assets` for Astro. With `--pages`, it stages raw HTML,
functions, headers/redirects/routes and the current appcast to ignored
`landing/.pages-output`. It rejects symlink/nonregular inputs and never copies
toolchain files, package metadata, locks, source modules or prior build outputs.
The existing `web/landing` dev/deploy wrappers and setup publisher use this
filtered directory. Native release still copies the signed appcast into the
physical raw root before publishing and verifies live bytes afterward; its
ordering, workflow and backend dependency graph are unchanged.

The canonical `landing/404.html` uses existing 404 wording and Curfew's shared
legal-page styles. Both filtered outputs include it, preventing Pages' implicit
SPA fallback from reporting a missing appcast or source path as homepage success.
The current feed baseline is missing/invalid; a native release is not required
by this migration. A native-staged `appcast.xml` remains a regular public file.
Preserve its generation/signing owner and reconcile its eventual Worker upload
before cutover; the current native release publisher targets Pages.

The Git-connected Pages publisher must also be reconciled before main integration:
the recorded provider configuration has root `landing`, output `.`. In that
root, its build command must be `node scripts/prepare-site-assets.mjs --pages`
and output must select `.pages-output`, or competing publication must be disabled
at explicit cutover. Reconfirm current provider configuration before changing it. These provider settings have not been changed.
Neither a successful local build nor safe native wrapper proves Git publisher
configuration or hosted delivery. `just landing` retains the Pages preview;
`just landing-static` retains the physical dependency-free preview.
`just landing-astro` and `just landing-worker` provide the standardized source
and local candidate previews.

Frontend/root lock bytes retain the accepted migration graph; the backend lock
retains current main, including upstream changes. This reconciliation changes no
dependency versions or lock bytes. Mintlify source/config now live together in `web/docs`, preserving
the upstream relocation and licensing guide. Common root docs commands delegate
there through the unchanged independent frontend toolchain. No native/backend
workspace absorption, production publication or Mintlify project change occurred.
