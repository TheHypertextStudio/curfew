#!/usr/bin/env bash
set -euo pipefail

APP_PATH=${1:?Usage: verify-release-artifact.sh <Curfew.app>}
CONTENTS="$APP_PATH/Contents"
INFO="$CONTENTS/Info.plist"
EXPECTED_ENTITLEMENTS="Curfew/Curfew-Release.entitlements"
EXPECTED_FEED="https://curfew.hypertext.studio/appcast.xml"
EXPECTED_TEAM="39AB9DY3K8"

fail() {
  echo "artifact verification failed: $*" >&2
  exit 1
}

verify_team() {
  path=$1
  team=$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1 \
    | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2}')
  [[ "$team" == "$EXPECTED_TEAM" ]] || fail "unexpected TeamIdentifier for $path: $team"
}

[[ -d "$APP_PATH" ]] || fail "app bundle not found"
[[ -d "$CONTENTS/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework missing"
[[ -d "$CONTENTS/PlugIns/CurfewWidget.appex" ]] || fail "Widget extension missing"

for tool in curfew-ctl curfew-mcp curfew-daemon; do
  path="$CONTENTS/Resources/$tool"
  [[ -x "$path" ]] || fail "$tool missing or not executable"
  /usr/bin/codesign --verify --strict --verbose=2 "$path"
  verify_team "$path"
done

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
/bin/cp "$tmp/actual.plist" "$tmp/normalized.plist"
# Developer ID signing may inject identity metadata. Remove only those two
# signing-derived keys before enforcing an exact capability comparison.
/usr/libexec/PlistBuddy -c 'Delete :com.apple.application-identifier' \
  "$tmp/normalized.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.team-identifier' \
  "$tmp/normalized.plist" 2>/dev/null || true
/usr/bin/plutil -p "$EXPECTED_ENTITLEMENTS" > "$tmp/expected.txt"
/usr/bin/plutil -p "$tmp/normalized.plist" > "$tmp/actual.txt"
diff -u "$tmp/expected.txt" "$tmp/actual.txt" || fail "release entitlements differ"

/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"
echo "Release artifact verified: $APP_PATH"
