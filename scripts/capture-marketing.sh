#!/usr/bin/env bash
# Usage: capture-marketing.sh
#
# Local, high-fidelity marketing screenshots. Builds the Debug app, then for
# each demo-fixture scenario launches an isolated process, drives it into a
# curated state, and captures only that process's window into build/screenshots/.
# It never stops an already-running Curfew app and never falls back to a desktop
# grab, so it cannot capture someone else's screen or background windows.
#
# REQUIRES Screen Recording permission for the controlling terminal:
#   System Settings > Privacy & Security > Screen Recording.
# Without it `screencapture` produces "could not create image from display".
# The CI / debug tier (`just capture`) uses XCUITest instead and needs no
# permission — see scripts/extract-screenshots.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Build/Products/Debug/Curfew.app"
BIN="$APP/Contents/MacOS/Curfew"
OUT="$ROOT/build/screenshots"
SETTLE="${CURFEW_CAPTURE_SETTLE:-3}"

SCENARIOS=(overview configuration settings getting-started this-week warning lockout)
CAPTURE_PID=""

echo "==> Pre-building bundled CLI tools (so the app's bundle step succeeds)"
swift build -c release --product curfew-ctl --product curfew-mcp --product curfew-daemon

echo "==> Building Debug app"
xcodebuild build \
    -project Curfew.xcodeproj \
    -scheme Curfew \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath build \
    >/dev/null

mkdir -p "$OUT"

launch() {
    CURFEW_DEMO_FIXTURE=1 CURFEW_DEMO_SCENARIO="$1" "$BIN" >/dev/null 2>&1 &
    CAPTURE_PID="$!"
    sleep "$SETTLE"
}

stop() {
    if [[ -n "$CAPTURE_PID" ]] && kill -0 "$CAPTURE_PID" 2>/dev/null; then
        kill "$CAPTURE_PID" 2>/dev/null || true
        wait "$CAPTURE_PID" 2>/dev/null || true
    fi
    CAPTURE_PID=""
    sleep 0.3
}

for scenario in "${SCENARIOS[@]}"; do
    echo "==> Capturing window: $scenario"
    launch "$scenario"
    if window_id="$(swift "$ROOT/scripts/window-id.swift" Curfew "$CAPTURE_PID" 2>/dev/null)"; then
        screencapture -x -l "$window_id" "$OUT/curfew-$scenario.png" || \
            echo "    !! screencapture failed (Screen Recording permission?)"
    else
        echo "    !! no window found for the capture process; skipped"
    fi
    stop
done

echo "==> Done. Screenshots in $OUT"
ls -1 "$OUT"/*.png 2>/dev/null || echo "(no PNGs produced — check Screen Recording permission)"
