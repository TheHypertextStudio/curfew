# Curfew website and documentation

Curfew's marketing frontend lives in `landing/` and uses Astro's static profile.
The canonical origin remains `https://curfew.hypertext.studio`. Product docs live
in `docs/` and remain a Mintlify project. The native app, Curfew Sync, license
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
passed in run `38116980056`; local Curfew acceptance uses those exact shipping
tarballs in an ignored validation overlay. The final
registry lockfile, fresh frozen install, and clean `./run setup` acceptance remain
required before this source change can be merged or published. Do not commit
file-based package overrides or represent the local validation lock as a registry
lock. All consumed private packages now grant this repository GitHub Actions Read
access. CI uses only its ephemeral `github.token` with `packages: read`, through
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
| `landing/public/style.css`, `landing/public/images/` | Existing product appearance and original asset bytes |
| `landing/wrangler.site.json` | Independent site Worker, asset routing, separate staging/production identities |
| `docs/docs.site.json` | Product-owned Mintlify branding/navigation/overrides |
| `docs/docs.json` | Generated committed Mintlify configuration |

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
Registry installation must be accepted before enabling it as a required merge
check. Review configuration with content; inspect keyboard use and narrow layouts
in local previews. Keep native release ordering, sale gate, and distribution
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
adoption. The current source phase has not produced its Curfew hosted receipt.

Normal website/docs jobs are skipped while this draft-only proposal job runs.
After the lock is reviewed and adopted, a ready-for-review event invokes the normal
website/docs checks; the manual refresh mode also remains available once registered.
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
source-bound deployment. The intended repository is this repo, source `docs/`,
branch `main`; those Git settings must be verified when connecting the existing
project. Preserve that project and its subscription. Contributor access, actual
connected branch, project ID, and deployment ID/source SHA remain provider gates.
The authenticated dashboard reports the Pro trial ended and hosted previews are
unavailable; use the pinned local preview. No subscription change is required
for local adoption.

Public `/docs` currently serves the HTML MCP guide. The Worker deliberately keeps
that guide until Mintlify publishes the reviewed source and the complete proxy
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
marketing release. Caller activation remains gated on the actual registry lock,
provider preview, and recovery evidence. The source declaration now selects the
shared Workers adapter, exact Wrangler 4.148.0, `modules/worker.js`, and `assets/`
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
and prior artifact/configuration. Anonymous production `/account` currently returns
the same homepage bytes as `/` and an arbitrary unknown URL: the existing Pages
SPA fallback reports a false 200. Read-only provider inventory found no production
account Worker. The frontend keeps the `/account` link destination; it does not
implement a nonexistent account backend or reproduce the generic SPA fallback.
Account availability and the current source/production mismatch need an explicit
product disposition before cutover acceptance; unknown site URLs must return 404. Current observed Pages recovery deployment is
`f902590f-fd0c-4bee-9bfc-19f7522c825b`; revalidate the live prior deployment at
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
