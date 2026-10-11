# Curfew frontend source acceptance — October 10, 2026

This record covers source preparation and local runtime acceptance. It does not
establish registry publication, authenticated provider delivery, hosting cutover,
observation, or legacy-host retirement.

The original source commit is recorded in `content-baseline.json`. Red checks
observed the missing site Worker module and missing Astro outputs before the
implementation. The first parity build detected a new viewport tag on the
historical MCP redirect; the layout now preserves that page's original metadata.

## Observed local checks

| Command or check | Observed result |
| --- | --- |
| `pnpm exec ./run setup` | Passed shared bootstrap and frontend frozen install against exact local package tarballs |
| `pnpm exec ./run doctor` | All tool/runtime checks passed with declared managed Node 24.20.0 |
| `pnpm exec ./run check` | Shared conformance, site validation and native Mintlify checks passed |
| `pnpm exec ./run build` | Assembled prebuilt modules/assets/config with pinned Wrangler local dry run; no deploy |
| Worker and existing landing contract tests | 12 passed, including POST search, upstream failure, credential/header boundaries and release identity |
| Astro typecheck | 11 files; no errors, warnings or hints |
| Shared ESLint/Prettier configuration | Passed for new Worker, tooling, config and shared layout |
| Original-content parity | Nine pages retain text, anchors, links, metadata, image attributes, body classes and inline-script hashes; four original CSS/image assets retain exact bytes |
| `pnpm site:test:acceptance` | 18 Chromium/Firefox/WebKit scenarios passed against the prebuilt candidate in local workerd with bundling disabled |
| `pnpm docs:config:check`, `pnpm docs:check` | Deterministic config, native Mintlify build, links/anchors/redirects/snippets and accessibility passed |
| `pnpm --dir landing peers check` | No peer dependency issues |
| `actionlint .github/workflows/website.yml` | Passed |
| Original/Astro screenshot comparison | All 12 full-page Chromium PNG comparisons byte-identical; see `visual-comparison.json` |
| `swiftformat Curfew CurfewTests CurfewUITests Sources Tests --lint` | 0/375 files require formatting, 6 skipped; formatter application also changed zero files |
| `swiftlint lint --strict` | Zero violations in 272 files |
| `xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests -derivedDataPath build/website-native-check CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` | TEST SUCCEEDED; 937 passing test-case observations in the retained log |
| `xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Debug -destination 'platform=macOS' -derivedDataPath build/website-native-check CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` | BUILD SUCCEEDED |

Mintlify reports the approved primary orange `#b25e30` at 4.63:1 on white, which
meets WCAG AA. It recommends AAA contrast as a warning; native MDX accessibility
validation reports no issues. Existing marketing colors remain unchanged.

The initial browser pass exposed test assumptions about Firefox conditional 304
responses, the native system font spelling, and macOS WebKit's Option+Tab link
navigation. The final tests accept valid 200/304 caching, verify the original
system-font stack, and use platform link traversal without changing product
markup or styles. Traces/screenshots from the initial failures are local ignored
evidence; they are not provider failures.

## Setup boundaries

An initial root pnpm workspace conflicted with the existing independent `web/`
lockfile. The final frontend workspace lives in `landing/`; root pnpm scripts are
thin facades. An initial repository-wide conformance check encountered the native
release workflow. The final root `./run` delegates to the checksum-pinned
`landing/run`, whose declaration and conformance scope are frontend-only.
`landing/bootstrap` reuses the original repository preparation engine. Native
release and backend workspace files were not rewritten or exempted from guards.

Shared packages are exact packed 0.1.0 artifacts in a temporary ignored validation
overlay. That overlay and its file-resolved lock are excluded from committed
source. The actual `landing/pnpm-lock.yaml` must be generated from the published
registry and accepted on a fresh checkout. The root facade's independent lock
contains only its managed Node runtime. It is not evidence of frontend registry
installation.

## Remaining gates

- Publish shared packages, generate/commit the actual frontend registry lock,
  verify read-only clean frozen setup and hosted required checks.
- The shared Workers adapter and scoped caller are published and pinned at v0.1.8.
  Configure the marketing candidate/promotion caller after registry, isolated
  preview, and recovery acceptance.
- Connect and reconcile the existing Mintlify `curfew` project and Git integration;
  obtain a successful reviewed source-bound deployment. Keep `DOCS_MODE=html-guide`
  until `/docs` HTML, assets, search, redirects, canonical URLs and anchors pass
  through the actual Mintlify proxy.
- Reconcile current production source and routes. `/account` and arbitrary unknown
  URLs currently return the same homepage bytes via Pages SPA fallback; no
  production account Worker was found. The link destination remains `/account`;
  account availability needs explicit disposition and unknown site URLs must return 404.
- Coordinate the old Pages Git publisher before source conversion merges. Its
  current raw-landing output is incompatible with Astro source unless its interim
  build/output is explicitly adapted or publication is disabled at cutover.
- Provision isolated frontend preview, capture complete prior route/deployment
  recovery state, verify the artifact/provider, and execute explicit production
  promotion/cutover. Keep license, webhook, download and native-release services
  on their current owners.
- Complete public acceptance, the 24-hour observation gate, 14-day prior-host
  recovery retention, and final obsolete-host retirement.

Context7 documentation lookup failed with a monthly quota error; this is retained
as a tooling limitation. Implementation used inspected pinned shared templates,
Wrangler's installed schema/source and observed native runtime behavior. Raising
the Context7 limit requires `npx ctx7@latest login` or `CONTEXT7_API_KEY`; no key or
subscription change was made.

## Published lifecycle pin follow-up

The frontend launcher/lock now use published release-engineering `v0.1.7`, immutable
revision `0e6c0313904316e893a8e606a2557f016571412e`, archive SHA-256
`016e239daa6c30d48198648d97d36f52ad5d28fb3c04cc4cd67a1700d30fa6ad`. The shared
pin updater verified the hosted archive checksum and tag identity. Root/native pins
and the root facade remain unchanged. The website workflow records exact future
candidate/promote references; callers remain inactive pending scoped-root support
and the existing registry/provider gates.

`pnpm exec ./run setup`, `doctor`, `check`, and `build` pass against the same ignored
exact-tarball overlay under managed Node 24.20.0/pnpm 11.9.0. Doctor reports every
tool/runtime check true; check includes 12 unit/contract cases, Astro type/lint/format,
nine-page/four-asset parity, and native Mintlify build/link/a11y; build assembles the
prebuilt modules/assets/config without provider deployment. The first check build
encountered a transient enclosing-checkout tsconfig resolver failure during that
checkout's dependency install; direct build and the strict lifecycle rerun pass
unchanged afterward. No workaround or dependency alteration was introduced.

Browser/native product code is unchanged from the acceptance above, so their passing
evidence is retained. Registry publication/frozen installation and provider/auth/cutover
acceptance remain open; this pin update does not satisfy them.


## v0.1.8 marketing declaration and retained archive

The published pin updater verified v0.1.8 against the actual release assets and
immutable tag: revision `878260def7229cd3df7f752b32e5581230c5db2d`, engine SHA-256
`61f746429fc0ffc7826df2bde61ee4d41323fb5fa0c9f8661255040e7838afd4`.
The landing declaration now selects the shared Workers adapter, exact Wrangler
4.148.0, and archive-relative `modules/worker.js` and `assets/`. Shared callers
support `root: landing`; activation remains pending.

The intended marketing preview is `curfew-site-staging.hypertext.studio`, Worker
`curfew-site-staging`. The existing `curfew-staging.hypertext.studio` belongs to the
account backend and is excluded from marketing. Both marketing environments still
have empty routes, workers.dev disabled, and `DOCS_MODE=html-guide`. No provider,
Pages publisher, Mintlify Git project, native app, backend, or auth settings changed.

Failing-first checks recorded the missing deployment declaration and old package
pins before implementation. All 15 unit/contract tests now pass. Astro checks all
11 source files without diagnostics, ESLint/Prettier pass, all nine original page
contracts and four asset digests match, Mintlify checks pass, and all 18 existing
Chromium/Firefox/WebKit acceptance scenarios pass against the prebuilt Worker.

An ignored native acceptance harness verifies the cached engine checksum, packs
then extracts the candidate ZIP outside the source checkout, and calls actual
v0.1.8 `workers_site_inputs` for staging and production. Both native Wrangler
no-bundle dry runs succeed and retain identical Worker bytes. workerd serves all
17 page/HTML alias routes from that extracted archive, returns the injected
synthetic local release identity with `no-store`, and returns 404 for an unknown
route. The fixture has no source tree, credentials, or provider calls. Evidence:
`.studio/acceptance/retained-site/{summary.json,marketing.zip,*-dry-run.log,workerd.log}`.
These are local fixture bytes, not an immutable hosted candidate or provider release.

The intended initial shared package pins are **0.0.1**, per the release decision.
The first v0.1.8 checkpoint used the previously accepted exact **0.1.0 local
tarballs**. Its results establish Curfew source/artifact behavior with that graph.
The subsequent 0.0.1 shipping acceptance below supersedes that package limitation;
registry acceptance still requires actual publication, the real registry lock,
and a fresh frozen install before activating the hosted candidate caller. No file
overrides or fake registry entries are committed.

Provider prerequisites remain: the isolated marketing Worker/hostname, scoped
credentials, complete prior Pages and route/DNS recovery evidence, real staging
metadata and runtime checks, public account-route disposition, successful Mintlify
Git publishing before enabling delegation, explicit cutover, observation, and
retention. The existing backend staging host cannot satisfy marketing acceptance.
Context7 again reported monthly quota exhaustion; its login/API-key upgrade remains
available. Installed exact contracts and official Workers references were inspected.


The v0.1.8 `./run doctor`, `./run check`, and `./run build` pass on the retained
local graph. Canonical fresh registry setup remains blocked by the unpublished
intended 0.0.1 registry dependencies. Native checks also rerun successfully: SwiftFormat changed
0/375 files (six skipped), lint found no formatting violations, SwiftLint found
zero violations across 272 files, CurfewTests completed with `TEST SUCCEEDED`,
and the Debug build completed with `BUILD SUCCEEDED` using the existing isolated
`build/website-native-check` derived data and `CODE_SIGNING_ALLOWED=NO`. Native
logs remain under `.studio/acceptance/`; these do not prove signed distribution.
The marketing product release version remains 0.1.0; the 0.0.1 release decision
applies to the three consumed shared packages.


## Actual 0.0.1 shipping-package acceptance

Curfew consumed the actual package tarballs from shared candidate
`38116243716-1`, source `a108b4fec7d1fca02fb59afb09237cf9b52a1ca6`, manifest
SHA-256 `097bb8cd7f4bb7341bb9bfdc48c79cc0c855a95c3b25a225374c1f9da3f58fa4`.
Each of the three consumed tarball digests was verified against the candidate
record before installation. Installed package versions are all 0.0.1, resolved
inside this checkout's native pnpm store rather than workspace links.

The ignored file-tarball overlay passed native install, peers, shared `setup`
(including frozen replay), `doctor`, `check`, `build`, all 18 browser scenarios,
and repeated native archive acceptance. This includes all 15 source/unit checks,
nine-page/four-asset parity, and actual Mintlify validation. Both shared-adapter
Wrangler dry runs and all 17 extracted-archive page/alias routes pass again,
alongside synthetic release identity and unknown-route 404 checks. The local
archive SHA-256 is
`6288f589ff953bad2f4f04009124c6ba27ffdf9bcfc0132d59f9470b54850a69`, assembled
from Curfew source checkpoint `da3e9e022f81a09f67ecc2caa6389ba9b4a1ced0`.

The first setup attempt found the global pnpm 10.33.0 during bootstrap's probe
outside the repository cwd. Selecting the already installed pnpm 11.9.0 binary
in PATH corrected the environment; no bootstrap/native source changed. The
failure log is retained. The overlay restored the canonical workspace and all
frontend/root/backend lockfile bytes in `finally`; no local file resolution or
registry integrity was committed. Detailed evidence is retained under
`.studio/acceptance/shipping-001/` and `.studio/acceptance/retained-site/`.

This establishes local consumption of the actual intended shipping bytes. Package
publication, a registry-backed lock and fresh frozen setup, hosted caller checks,
provider preview/recovery, Mintlify publishing, and cutover remain separate gates.


## Published initial shared release

The user approved the exact 0.0.1 manifest above. Promotion `38116605945`
published all four shared packages without rebuilding. Fresh read-only registry
consumer run `38116980056` passed all four package installs, frozen replay, peers,
and clean Astro/Next builds; registry integrity matches every reviewed tarball.
This supersedes earlier publication-pending notes. Curfew package-read access,
its actual canonical registry lock and fresh hosted setup/CI remain unverified.
No Curfew source behavior, package pins, provider routing or credentials changed.


## Native Curfew registry lock adoption

Run [38119577450](https://github.com/TheHypertextStudio/curfew/actions/runs/38119577450)
succeeded on the exact trusted draft PR head
`1cc3b241d5fb894cb75eac6371b9761f127ce57b`, with Node 24.20.0/pnpm 11.9.0,
ephemeral `github.token` and `packages: read`. Its disposable consumer copied
only the reviewed frontend manifest and workspace policy, generated a fresh lock,
performed a separate frozen install with dependency scripts disabled, and reported
`No peer dependency issues found`. No credential was transferred to local npm.

The adopted `landing/pnpm-lock.yaml` is the actual artifact's unmodified 429,963
bytes (13,197 lines; 1,372 package entries and 1,374 snapshots). SHA256 is
`56a7f31e90f34abb7e66a910e870d3699d2a8f81d9d5dc071b413a535b0ee122`.
Artifact `11694795906` ZIP SHA256 is
`abe132c5429dd1852836163d00a71d9520afa28a22ce512d9ed0684a26d62f67`.
All three company 0.0.1 package SHA512 integrities match the published shipping
manifest; there are no local/file/git resolutions or trust bypasses. The declared
Node 24.20.0 binary variants retain their upstream SHA256 integrity values.
Existing Mintlify transitive deprecations remain for glob, inflight,
prebuild-install and puppeteer; the native peer check has no issues.

The six migration commits were rebased onto actual production/main
`3efbd4fd3b4a9786e7eabd90904259fdb0990448`, preserving all three newer native
commits, native CI modernization and both documentation additions. Every own
commit is unchanged in range-diff. The rebased manifest SHA256 remains
`2c3f688e980354dc984a059b8aa94efd1374116b88c1c3ed4161df7d9300d1a0` and workspace
policy SHA256 remains
`65f5bb893ffb54dc7c60114b031743ab8ff145bb1bee4631422df32acd493390`, so the native
receipt still applies to those exact dependency inputs. Detailed source, native
receipt, full proposed-lock diff and independent review are retained in the
standardization workspace's `acceptance/task5-curfew-registry/`.

This supersedes the earlier Curfew package-read/registry-lock pending notes.
Full website/docs CI, fresh lifecycle setup, hosted candidate acceptance, isolated
provider preview/recovery, Mintlify publishing and cutover remain open. This phase
adds no tests and runs no local product suite; actionlint and diff checks cover
the workflow source, and the hosted registry checks above cover its actual token
and dependency graph. Revert the lock and this CI selection change to return to
artifact-only proposal mode. No main merge or provider write is included.


## First full native CI after registry adoption

Run `38119975204` correctly selected the tracked canonical lock and skipped fresh
proposal resolution/upload. Docs validation passed against the actual registry;
website frozen installation, source/type/lint/format checks, original-page parity
and immutable artifact build also passed. Browser setup failed before tests began
because the workflow invoked Playwright from the root facade, where it is not a
dependency. The workflow now runs the same pinned CLI from its owning `landing/`
workspace. No manifest, lock, browser cases or product behavior changed. Full
three-browser acceptance remains pending a successful subsequent hosted run.
