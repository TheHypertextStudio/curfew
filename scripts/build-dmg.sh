#!/usr/bin/env bash
# Usage: build-dmg.sh <path/to/Curfew.app> <output/Curfew-vX.Y.Z.dmg>
set -euo pipefail

APP_PATH="${1:?Usage: build-dmg.sh <Curfew.app> <output.dmg>}"
OUTPUT_PATH="${2:?Usage: build-dmg.sh <Curfew.app> <output.dmg>}"

VOLUME_NAME="Curfew"
STAGING="$(mktemp -d)/staging"
mkdir -p "$STAGING"

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

create-dmg \
  --volname "$VOLUME_NAME" \
  --window-pos 200 120 \
  --window-size 580 400 \
  --icon-size 128 \
  --icon "Curfew.app" 140 180 \
  --hide-extension "Curfew.app" \
  --app-drop-link 440 180 \
  --no-internet-enable \
  "$OUTPUT_PATH" \
  "$STAGING"

echo "DMG written to $OUTPUT_PATH"
