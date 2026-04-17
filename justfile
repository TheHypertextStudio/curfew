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
        -destination '{{ destination }}' \
        -only-testing:CurfewTests

# Full UI-test suite. Heavier; kept separate from `just test`.
test-ui:
    xcodebuild test \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -destination '{{ destination }}' \
        -only-testing:CurfewUITests

# Run one test case or method (e.g. `just test-one ActivityStoreTests` or

# `just test-one ActivityStoreTests/appendAndFetch`).
test-one target:
    xcodebuild test \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -destination '{{ destination }}' \
        -only-testing:CurfewTests/{{ target }}

# -----------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------

# Debug build.
build:
    xcodebuild build \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -configuration Debug \
        -destination '{{ destination }}'

# Release build. Does not sign / notarise; the release workflow handles that.
build-release:
    xcodebuild build \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -configuration Release \
        -destination '{{ destination }}'

# Archive the Release configuration for packaging. Output goes to
# `release/Curfew.xcarchive`. Signing + notarisation happen downstream.
archive:
    mkdir -p release
    xcodebuild archive \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -configuration Release \
        -destination '{{ destination }}' \
        -archivePath release/Curfew.xcarchive

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
        -configuration Debug \
        -destination '{{ destination }}'
