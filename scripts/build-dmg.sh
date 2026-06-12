#!/usr/bin/env bash
# Usage: build-dmg.sh <path/to/Curfew.app> <output/Curfew-vX.Y.Z.dmg>
#
# Builds the distributable disk image with `create-dmg`. When the branded
# assets exist under scripts/dmg-assets/ they are layered in automatically:
#
#   scripts/dmg-assets/background.png   1160×800 (@2x of the 580×400 window)
#   scripts/dmg-assets/volume.icns      mounted-volume icon
#
# Both are optional — without them the DMG still builds, just with the plain
# Finder chrome — so CI never breaks if the art isn't checked in yet. The icon
# positions below are fixed so the background art can be designed against them:
# the app glyph sits left (140,180), the Applications drop-link sits right
# (440,180), with room for a "drag to install" arrow between them.
set -euo pipefail

APP_PATH="${1:?Usage: build-dmg.sh <Curfew.app> <output.dmg>}"
OUTPUT_PATH="${2:?Usage: build-dmg.sh <Curfew.app> <output.dmg>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/dmg-assets"
BACKGROUND="$ASSETS_DIR/background.png"
VOLICON="$ASSETS_DIR/volume.icns"

VOLUME_NAME="Curfew"
STAGING="$(mktemp -d)/staging"
mkdir -p "$STAGING"

cp -R "$APP_PATH" "$STAGING/"
# Note: the Applications alias is created by create-dmg's `--app-drop-link`
# below (positioned to match the background art). Do not also `ln -s` it here —
# create-dmg would then fail with "Applications: File exists".

# Assemble create-dmg flags, folding in the branded assets only when present.
args=(
  --volname "$VOLUME_NAME"
  --window-pos 200 120
  --window-size 580 400
  --icon-size 128
  --icon "Curfew.app" 140 180
  --hide-extension "Curfew.app"
  --app-drop-link 440 180
  --no-internet-enable
)

if [[ -f "$BACKGROUND" ]]; then
  args+=(--background "$BACKGROUND")
  echo "Using branded DMG background: $BACKGROUND"
else
  echo "No dmg-assets/background.png found — building a plain DMG."
fi

if [[ -f "$VOLICON" ]]; then
  args+=(--volicon "$VOLICON")
  echo "Using volume icon: $VOLICON"
fi

create-dmg "${args[@]}" "$OUTPUT_PATH" "$STAGING"

echo "DMG written to $OUTPUT_PATH"
