# Domain migration implementation evidence

October 13, 2026. Production cutover is not complete.

- Protocol PR #13 merged with rebase; v0.0.13 GitHub Packages publication succeeded. All consumers pin the matching immutable version.
- Failing-first protocol portability tests: prior constants rejected alternate domains; 116 contract tests, TypeScript producer/consumer checks, 20 Swift tests and Kotlin build/tests passed.
- Failing-first native endpoint and authorization-retention tests pass; full app unit suite and unsigned Debug/Release builds pass. The built Release Info.plist reports https://thecurfew.app/appcast.xml.
- SwiftFormat and strict SwiftLint pass.
- 55 root script tests and website source/type/lint/build checks pass. 18 browser acceptance tests passed across Chromium, Firefox and WebKit on isolated port 4397; the default test port was occupied by unrelated work.
- Backend verification passes: 521 Worker tests, 52 browser-DOM tests, two Node D1-adapter tests, typecheck, lint and format checks.
- License tests/typecheck and cf production build/dry-run pass with retained KV namespace. Backend and site cf build/dry-runs preserve existing deployment names and storage bindings. No provider mutations are implied by dry-runs.
- Review found cf parameter/mode errors, stale CIMD registration and credential-bearing redirects. Regression tests were observed failing before fixes; they now pass.
- Browser extension tests pass 67/68; the untouched icon-generation byte comparison fails. Manifest and packaging assertions pass. No icon artifacts or test expectations were changed to hide this gap.
- Local production preflight refuses to proceed without CLOUDFLARE_API_TOKEN and an explicit CLOUDFLARE_ACCOUNT_ID. No live routing, identity-provider registrations, account revocation, Stripe changes or release activation have been performed.

Remaining acceptance: authenticated zone/DNS/TLS provisioning, production recovery audit and backup, sender/provider/Stripe verification, signed/notarized release and update installation, same-account device reconnection and encrypted-data readability, real assistant command enforcement/receipt, and post-cutover monitoring.

## Verification commands

Native checks ran with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` for Xcode commands. These prove unsigned source/build behavior, not signing, notarization or installation acceptance.

```sh
swift test --package-path CurfewKit
swiftformat Curfew CurfewTests CurfewUITests --lint
swiftlint lint --strict
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/AccountOAuthEnrollmentTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -derivedDataPath build -only-testing:CurfewTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration Release -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
node --test scripts/*.test.mjs
```

The backend ran `pnpm test`, `pnpm typecheck`, `pnpm lint`, and `pnpm format:check`. Each migrated Worker ran `cf build --mode production` followed by `cf deploy --prebuilt --mode production --dry-run` using the pinned local executable. The backend used the independently pinned artifact identity. The app branch was rebased onto current main and native unit/package, format/lint, script and Release checks were repeated successfully. The Release bundle's feed, configuration commit and hash were compared with the generated artifact.

Review requests: [app/site/license #60](https://github.com/TheHypertextStudio/curfew/pull/60), [backend #56](https://github.com/TheHypertextStudio/curfew-sync/pull/56). Hosted checks were still running at handoff; their outcome is separate from the local evidence above.
