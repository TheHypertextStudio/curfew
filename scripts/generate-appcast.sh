#!/usr/bin/env bash
#
# Produces the Sparkle appcast.xml for a given release. Run from CI after
# the notarized DMG lands at $DMG_PATH.
#
# The appcast is a signed XML feed Sparkle polls to discover new versions.
# One <item> per release; the signature is an Ed25519 signature over the
# DMG bytes, produced by Sparkle's `sign_update` binary.
#
# Usage:
#   VERSION=1.0.1 \
#   DMG_PATH=./Curfew-v1.0.1.dmg \
#   RELEASE_NOTES_URL=https://curfew.hypertext.studio/releases/1.0.1.html \
#   SPARKLE_PRIVATE_KEY="$(cat private.key)" \
#   bash scripts/generate-appcast.sh > appcast.xml
#
# Required:
#   VERSION              — semver, e.g. 1.0.1
#   DMG_PATH             — path to the notarized DMG
#   SPARKLE_PRIVATE_KEY  — base64url-encoded Ed25519 seed (from gen-sparkle-keypair.sh)
#
# Optional:
#   RELEASE_NOTES_URL    — URL Sparkle shows in the update prompt
#   MIN_MACOS_VERSION    — minimum macOS, defaults to 26.0
#   APPCAST_URL_BASE     — where the DMG is hosted, defaults to the GitHub release

set -euo pipefail

VERSION=${VERSION:?VERSION is required}
DMG_PATH=${DMG_PATH:?DMG_PATH is required}
SPARKLE_PRIVATE_KEY=${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}
RELEASE_NOTES_URL=${RELEASE_NOTES_URL:-https://curfew.hypertext.studio/releases/${VERSION}.html}
MIN_MACOS_VERSION=${MIN_MACOS_VERSION:-26.0}
APPCAST_URL_BASE=${APPCAST_URL_BASE:-https://github.com/TheHypertextStudio/curfew/releases/download/v${VERSION}}

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

dmg_filename=$(basename "$DMG_PATH")
dmg_size=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH")
pub_date=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# Sparkle ships a `sign_update` helper as part of its distribution. When
# running in CI we expect the tool on $PATH; when run locally we fall back
# to the SPM-cached copy. Either way, it reads the private key from stdin
# and emits `<ed_signature> <length>` on a single line.
sign_update=$(command -v sign_update || echo "")
if [[ -z "$sign_update" ]]; then
  # SPM cache location after `swift package resolve` on this project.
  candidate=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -name sign_update -type f 2>/dev/null | head -1)
  sign_update="$candidate"
fi
if [[ -z "$sign_update" ]]; then
  echo "sign_update binary not found — install Sparkle or run \`swift package resolve\` first." >&2
  exit 1
fi

ed_signature=$(printf '%s' "$SPARKLE_PRIVATE_KEY" \
  | "$sign_update" -f - "$DMG_PATH" 2>/dev/null \
  | awk -F'"' '/sparkle:edSignature/{print $2}')

if [[ -z "$ed_signature" ]]; then
  echo "sign_update did not return a signature — verify SPARKLE_PRIVATE_KEY." >&2
  exit 1
fi

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Curfew</title>
    <link>https://curfew.hypertext.studio/appcast.xml</link>
    <description>Updates for Curfew</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <link>${RELEASE_NOTES_URL}</link>
      <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_MACOS_VERSION}</sparkle:minimumSystemVersion>
      <enclosure
        url="${APPCAST_URL_BASE}/${dmg_filename}"
        length="${dmg_size}"
        type="application/octet-stream"
        sparkle:edSignature="${ed_signature}" />
    </item>
  </channel>
</rss>
EOF
