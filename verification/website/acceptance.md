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
- Publish the shared release-engineering version containing the Workers adapter;
  pin actual bytes and configure the shared candidate/promotion caller. Keep
  `v0.1.6`'s existing checksum truthful.
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
