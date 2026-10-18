#!/usr/bin/env bash
set -euo pipefail

APP_PATH=${1:?Usage: verify-release-artifact.sh <Curfew.app> <release-configuration.json> <0.0.x-version>}
CONFIGURATION_PATH=${2:?configuration artifact is required}
EXPECTED_VERSION=${3:?0.0.x version is required}
CONTENTS="$APP_PATH/Contents"
INFO="$CONTENTS/Info.plist"
EXPECTED_ENTITLEMENTS="Curfew/Curfew-Release.entitlements"
EXPECTED_FEED=$(node "$(dirname "$0")/deployment-config.mjs" get appcast)
EXPECTED_TEAM="T95VDD3A4W"

fail() {
  echo "artifact verification failed: $*" >&2
  exit 1
}

verify_team() {
  path=$1
  signature=$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1)
  team=$(printf '%s\n' "$signature" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2}')
  [[ "$team" == "$EXPECTED_TEAM" ]] || fail "unexpected TeamIdentifier for $path: $team"
  printf '%s\n' "$signature" | /usr/bin/grep -Eq '^Authority=Developer ID Application: .+ \(T95VDD3A4W\)$' \
    || fail "Developer ID Application authority missing for $path"
}

[[ -d "$APP_PATH" ]] || fail "app bundle not found"
node "$(dirname "$0")/release-candidate.mjs" verify-app "$APP_PATH" "$CONFIGURATION_PATH" "$EXPECTED_VERSION"
[[ -d "$CONTENTS/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework missing"
[[ -d "$CONTENTS/PlugIns/CurfewWidget.appex" ]] || fail "Widget extension missing"

embedded_tools=$(node "$(dirname "$0")/release-candidate.mjs" embedded-tools "$APP_PATH")
while IFS= read -r tool; do
  path="$CONTENTS/Resources/$tool"
  [[ -x "$path" ]] || fail "$tool missing or not executable"
  /usr/bin/codesign --verify --strict --verbose=2 "$path"
  verify_team "$path"
done <<< "$embedded_tools"

/usr/bin/codesign --verify --strict --verbose=2 "$CONTENTS/Frameworks/Sparkle.framework"
/usr/bin/codesign --verify --strict --verbose=2 "$CONTENTS/PlugIns/CurfewWidget.appex"
/usr/bin/codesign --verify --strict --verbose=2 "$APP_PATH"
verify_team "$CONTENTS/PlugIns/CurfewWidget.appex"
verify_team "$APP_PATH"

feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO")
[[ "$feed" == "$EXPECTED_FEED" ]] || fail "unexpected SUFeedURL: $feed"
public_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO")
[[ -n "$public_key" && "$public_key" != REPLACE_* ]] || fail "Sparkle public key missing"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
/usr/bin/codesign -d --entitlements :- "$APP_PATH" > "$tmp/actual.plist" 2>/dev/null
node "$(dirname "$0")/release-entitlements.mjs" \
  "$tmp/actual.plist" "$EXPECTED_ENTITLEMENTS"

/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"
/usr/bin/xcrun stapler validate "$APP_PATH"
echo "Release artifact verified: $APP_PATH"
