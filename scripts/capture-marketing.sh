#!/usr/bin/env bash
# Usage: capture-marketing.sh
#
# Local, high-fidelity marketing screenshots. Builds the Debug app, then for
# each demo-fixture scenario launches it, drives it into a curated state, and
# captures a PNG into build/screenshots/. Windowed scenarios are captured
# per-window (with the macOS drop shadow); the full-screen lockout / warning
# overlays are captured as a full-screen grab.
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

# Windowed surfaces: capture just the app window (keeps the drop shadow).
WINDOWED_SCENARIOS=(overview configuration settings getting-started this-week)
# Overlay surfaces: full-screen grab (the overlay covers the whole display).
FULLSCREEN_SCENARIOS=(warning lockout)

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
    pkill -x Curfew 2>/dev/null || true
    sleep 0.4
    CURFEW_DEMO_FIXTURE=1 CURFEW_DEMO_SCENARIO="$1" "$BIN" >/dev/null 2>&1 &
    sleep "$SETTLE"
}

stop() {
    pkill -x Curfew 2>/dev/null || true
    sleep 0.3
}

for scenario in "${WINDOWED_SCENARIOS[@]}"; do
    echo "==> Capturing window: $scenario"
    launch "$scenario"
    if window_id="$(swift "$ROOT/scripts/window-id.swift" Curfew 2>/dev/null)"; then
        screencapture -x -l "$window_id" "$OUT/curfew-$scenario.png" || \
            echo "    !! screencapture failed (Screen Recording permission?)"
    else
        echo "    !! no Curfew window found; falling back to full screen"
        screencapture -x "$OUT/curfew-$scenario.png" || \
            echo "    !! screencapture failed (Screen Recording permission?)"
    fi
    stop
done

for scenario in "${FULLSCREEN_SCENARIOS[@]}"; do
    echo "==> Capturing full screen: $scenario"
    launch "$scenario"
    screencapture -x "$OUT/curfew-$scenario.png" || \
        echo "    !! screencapture failed (Screen Recording permission?)"
    stop
done

echo "==> Done. Screenshots in $OUT"
ls -1 "$OUT"/*.png 2>/dev/null || echo "(no PNGs produced — check Screen Recording permission)"
