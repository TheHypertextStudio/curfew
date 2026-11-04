# Private package setup

Curfew contributors should use this procedure when preparing a new machine or worktree. GitHub CLI login alone does not configure pnpm to authenticate with GitHub Packages.

Run these commands after GitHub CLI has package-read access to Hypertext Studio:

```sh
./bootstrap packages setup
./bootstrap packages check @thehypertextstudio/web-tokens
./bootstrap worktree prepare
```

Setup verifies package access and installs a user-level pnpm credential helper. The helper asks GitHub CLI for the current credential when pnpm needs it. Setup stores no token, preserves unrelated npm settings, and leaves unchanged files and modification times intact on repeat runs. Every worktree for the same user reuses the helper without shell exports. Setup migrates the exact legacy `${NODE_AUTH_TOKEN}` setting to the helper because pnpm 10 ignores an auth file containing that unset placeholder. The helper still honors an explicit token before the local login. CI and custom user-config files retain their explicit credentials. Setup refuses conflicting credentials and custom user-config overrides instead of replacing them.

Online preparation checks every private Studio package in its frozen lockfile before installation. Python 3 and curl are required for those checks. The current landing lock includes web-tokens 0.0.1, web-config 0.0.3, web-docs 0.0.1, and format-config 0.0.1. A failed check reports the package and recovery commands. Installs use native pnpm limits of two network requests and two child jobs, a 900000ms request timeout, and zero automatic retries. These command-level defaults support large pinned runtime downloads without changing user configuration. Frozen locks, native caches, checkout-local dependencies, and lifecycle-script policy remain unchanged. `worktree check`, `worktree plan`, `--no-install`, and offline preparation do not probe the registry.

CI keeps its explicit registry configuration, workflow token with `packages: read`, and package-specific Actions access. Machine setup refuses CI execution. Missing provider grants remain failures; setup cannot grant access. The checker handles pnpm 10's delegated npm commands, which do not understand pnpm's credential helper.

The shared bootstrap release contains the installer, probes, and regression tests. Its [credential-flow record](https://github.com/TheHypertextStudio/bootstrap/blob/main/docs/github-packages-auth.md) explains the sequence and the trust boundary. Curfew's `scripts/bootstrap-auth.test.mjs` verifies checkout anchoring, argument preservation, and failure propagation without using real credentials. The shared test suite verifies configuration preservation, no token in process arguments, failed-probe safety, repeat permissions and modification times, effective local/CI authentication, and offline behavior. Real fresh-worktree installation verifies the package path separately from those fixtures.

To disable local helper routing, remove only the managed Hypertext Studio block from `~/.npmrc`. Preserve unrelated npm settings and shared caches. Reverting the launcher pin restores the previous setup engine without changing application state.
