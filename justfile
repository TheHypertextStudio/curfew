# Curfew task runner.
#
# Centralises every repo-level command so contributors (and the CI
# workflow) never have to memorise xcodebuild invocations. Keep recipes
# thin — any non-trivial logic belongs in a script under scripts/ that
# a recipe calls into.
#
# Run `just --list` to see every available recipe.

project := "Curfew.xcodeproj"
scheme := "Curfew"
destination := "platform=macOS"
source_dirs := "Curfew CurfewTests CurfewUITests"

# Default recipe when no target is given. Mirrors the ship-gate from

# AGENTS.md: format check + strict lint + full unit suite + Debug build.
default: check

# -----------------------------------------------------------------------
# Formatting and lint
# -----------------------------------------------------------------------

# Apply SwiftFormat fixes in place.
format:
    swiftformat {{ source_dirs }}

# Verify formatting without rewriting files. Non-zero exit on drift.
format-check:
    swiftformat {{ source_dirs }} --lint

# SwiftLint in strict mode — warnings become errors.
lint:
    swiftlint lint --strict

# -----------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------

# Full unit-test suite on macOS.
test:
    xcodebuild test \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -destination '{{ destination }}' \
        -only-testing:CurfewTests

# Full UI-test suite. Heavier; kept separate from `just test`.
test-ui:
    xcodebuild test \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -destination '{{ destination }}' \
        -only-testing:CurfewUITests

# Run one test case or method (e.g. `just test-one ActivityStoreTests` or

# `just test-one ActivityStoreTests/appendAndFetch`).
test-one target:
    xcodebuild test \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -destination '{{ destination }}' \
        -only-testing:CurfewTests/{{ target }}

# Run the full unit suite with code coverage enabled. Writes the
# xcresult bundle to `build/Coverage.xcresult` and prints the
# per-target line-coverage summary. Pass `--verbose` to the script
# for the full breakdown; use `xcrun xccov view build/Coverage.xcresult`
# directly for machine-readable JSON.
test-coverage:
    mkdir -p build
    rm -rf build/Coverage.xcresult
    xcodebuild test \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -destination '{{ destination }}' \
        -only-testing:CurfewTests \
        -enableCodeCoverage YES \
        -resultBundlePath build/Coverage.xcresult
    xcrun xccov view --report build/Coverage.xcresult

# Report documentation gaps via SwiftLint's `missing_docs` analyzer rule.
# `missing_docs` is opt-in in `.swiftlint.yml`; this recipe runs only
# that rule so the output isn't drowned by normal style warnings.
docs-coverage:
    swiftlint lint --config .swiftlint-docs.yml --only-rule missing_docs --strict --reporter emoji

# -----------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------

# Debug build.
build:
    xcodebuild build \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -configuration Debug \
        -destination '{{ destination }}'

# Release build. Does not sign / notarise; the release workflow handles that.
build-release:
    xcodebuild build \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -configuration Release \
        -destination '{{ destination }}'

# Archive the Release configuration for packaging. Output goes to
# `release/Curfew.xcarchive`. Signing + notarisation happen downstream.
archive:
    mkdir -p release
    xcodebuild archive \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -configuration Release \
        -destination '{{ destination }}' \
        -archivePath release/Curfew.xcarchive

# Build a local (unsigned) DMG to preview the branded installer window —
# background art, volume icon, and drag-to-Applications layout. Picks up the
# assets under scripts/dmg-assets/ when present. Pass a version for the file
# name (default "dev"). The signed/notarised DMG in CI uses the same
# scripts/build-dmg.sh; this recipe is for eyeballing the chrome.
dmg version="dev":
    mkdir -p release
    rm -rf release/dmg-build release/dmg-export-app
    xcodebuild build \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -configuration Release \
        -destination '{{ destination }}' \
        -derivedDataPath release/dmg-build \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    cp -R release/dmg-build/Build/Products/Release/Curfew.app release/dmg-export-app
    rm -f "release/Curfew-{{ version }}.dmg"
    bash scripts/build-dmg.sh release/dmg-export-app "release/Curfew-{{ version }}.dmg"
    rm -rf release/dmg-export-app
    open "release/Curfew-{{ version }}.dmg"

# -----------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------

# Kill any running Curfew process immediately.
kill:
    pkill -x Curfew || true

# Build Debug and launch the app locally for development.
dev:
    xcodebuild build \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -configuration Debug \
        -destination '{{ destination }}' \
        -derivedDataPath build
    just kill
    open -n build/Build/Products/Debug/Curfew.app

# -----------------------------------------------------------------------
# Capture (marketing + debug screenshots / video)
# -----------------------------------------------------------------------

# CI / debug screenshots via XCUITest. Needs no Screen Recording permission,
# so it also works on headless runners. Output: build/screenshots/*.png.
capture:
    scripts/extract-screenshots.sh

# Local high-fidelity marketing stills (per-window, with shadow) via
# `screencapture`. Requires Screen Recording permission for the terminal.
# Output: build/screenshots/*.png.
capture-hero:
    scripts/capture-marketing.sh

# Local walkthrough video of the lockout overlay. Requires Screen Recording
# permission. Pass a duration in seconds (default 18). Output:
# build/screenshots/curfew-reel.mov.
capture-video seconds="18":
    scripts/capture-video.sh {{ seconds }}

# Headless SwiftUI snapshots of the main-window destinations. Renders via
# ImageRenderer in a plain unit test — no UI-test runner, no Screen Recording,
# no desktop takeover, CI-friendly. Output: build/snapshots/curfew-*.png.
snapshot:
    swift build -c release --product curfew-ctl --product curfew-mcp --product curfew-daemon
    xcodebuild test \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -configuration Debug \
        -destination '{{ destination }}' \
        -derivedDataPath build \
        -only-testing:CurfewTests/DestinationSnapshotTests

# Serve the landing page with live reload and open it in the browser.
# `live-server` injects a WebSocket client that auto-refreshes on every
# edit to landing/*.{html,css} — saves the round-trip of manual reloads
# while iterating on copy or CSS. Requires Node (npx); if it's not
# available on the machine, fall back to `just landing-static`.
# Ctrl+C stops the server. Pass a different port via `just landing 4000`.
landing port="8765":
    npx --yes live-server landing --port={{ port }} --host=127.0.0.1 --no-css-inject=false

# Dependency-free alternative that serves without live reload. Useful
# when the machine has no Node, or for confirming production-ish
# behaviour without the live-reload script in the page.
landing-static port="8765":
    @echo "→ http://localhost:{{ port }}"
    @open "http://localhost:{{ port }}" >/dev/null 2>&1 || true
    python3 -m http.server {{ port }} --directory landing --bind 127.0.0.1

# -----------------------------------------------------------------------
# Localization
# -----------------------------------------------------------------------

# Export the String Catalog to an XLIFF bundle for translator round-trips.
# Swift → XLIFF happens in the Xcode build (STRING_CATALOG_GENERATE_SYMBOLS
# auto-extracts); this recipe wraps `xcodebuild -exportLocalizations` so
# the output lives in `localization/` for version control.
xliff:
    mkdir -p localization
    xcodebuild -exportLocalizations \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -localizationPath localization \
        -exportLanguage en

# -----------------------------------------------------------------------
# Composite gates
# -----------------------------------------------------------------------
# Ship-gate alias — the exact chain AGENTS.md requires before any
# completion claim. Fails loudly on the first problem rather than
# reporting all four at once, because the fixes usually build on each
# other.
check: format-check lint test build

# Quick pre-commit sanity — lint + unit tests only, skips the Debug
# build. Useful when you've just written pure-logic code and don't want
# to wait for Xcode to link.
quick: format-check lint test

# -----------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------

# Wipe DerivedData for this project and local release artefacts.
clean:
    rm -rf release build
    xcodebuild clean \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -allowProvisioningUpdates \
        -configuration Debug \
        -destination '{{ destination }}'
