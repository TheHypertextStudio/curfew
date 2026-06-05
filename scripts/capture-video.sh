#!/usr/bin/env bash
# Usage: capture-video.sh [seconds]
#
# Records a short walkthrough clip of the app for marketing. Launches the
# `reel` demo scenario (the full-screen lockout overlay, whose gradient
# animates and whose clock ticks live) and screen-records it for `seconds`
# (default 18) into build/screenshots/curfew-reel.mov.
#
# REQUIRES Screen Recording permission for the controlling terminal
# (System Settings > Privacy & Security > Screen Recording). Local-only:
# headless CI runners cannot screen-record. If `screencapture -V` is
# unavailable on your macOS, the documented fallback is:
#   ffmpeg -f avfoundation -i "Capture screen 0" -t <seconds> out.mov
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Build/Products/Debug/Curfew.app"
BIN="$APP/Contents/MacOS/Curfew"
OUT="$ROOT/build/screenshots"
DURATION="${1:-18}"
SETTLE="${CURFEW_CAPTURE_SETTLE:-3}"

echo "==> Pre-building bundled CLI tools"
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
pkill -x Curfew 2>/dev/null || true
sleep 0.4

echo "==> Launching reel scenario"
CURFEW_DEMO_FIXTURE=1 CURFEW_DEMO_SCENARIO=reel "$BIN" >/dev/null 2>&1 &
sleep "$SETTLE"

echo "==> Recording ${DURATION}s to $OUT/curfew-reel.mov"
if ! screencapture -V "$DURATION" -x "$OUT/curfew-reel.mov"; then
    echo "    !! screen recording failed (Screen Recording permission? old macOS?)"
    echo "    !! fallback: ffmpeg -f avfoundation -i 'Capture screen 0' -t $DURATION out.mov"
fi

pkill -x Curfew 2>/dev/null || true
echo "==> Done."
ls -la "$OUT/curfew-reel.mov" 2>/dev/null || echo "(no video produced)"
