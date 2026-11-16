# Development

Curfew is a macOS app built with Xcode. This page takes a fresh clone to a passing build and test run. Nothing here needs a Studio account, sign-in, token, or signing certificate.

## Quickstart

Install Xcode 26 or later (the app's deployment target is macOS 26) and [Homebrew](https://brew.sh). The repository pins Swift 6.0 in `.swift-version`, SwiftFormat 0.64.1 in `scripts/swiftformat.sh`, and Node.js 24 in `package.json`.

```sh
brew install just swiftlint node@24
git clone https://github.com/TheHypertextStudio/curfew
cd curfew
export CURFEW_XCODEBUILD_SETTINGS='CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO'
just check
```

`just check` is the same gate pull requests run: the release-policy tests, SwiftFormat in check mode, SwiftLint in strict mode, the unit-test suite, and a Debug build. The first run downloads the pinned SwiftFormat release and builds the Swift packages, so it needs network access and takes several minutes. `CURFEW_XCODEBUILD_SETTINGS` turns code signing off, which lets a build run without the Studio signing team.

Run `just --list` to see the other recipes. While you work, `just quick` skips the build, `just format` applies formatting, and `just test-one ActivityStoreTests` runs a single test case.

Before you push, read [CONTRIBUTING.md](../CONTRIBUTING.md) for the workflow and style rules. Pull request checks decide formatting and tests for contributions from forks.
