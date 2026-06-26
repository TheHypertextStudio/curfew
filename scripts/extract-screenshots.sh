#!/usr/bin/env bash
# Usage: extract-screenshots.sh
#
# CI / debug screenshot tier. Runs the MarketingCaptureTests UI tests to a
# fixed result bundle, then exports their screenshot attachments into
# build/screenshots/ as curfew-<scenario>.png. Unlike the local
# `capture-marketing.sh`, this path needs no Screen Recording permission — it
# uses XCUIScreen.screenshot(), so it works on headless GitHub runners.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUNDLE="$ROOT/build/screenshots.xcresult"
RAW="$ROOT/build/screenshots-raw"
OUT="$ROOT/build/screenshots"

echo "==> Pre-building bundled CLI tools"
swift build --package-path CurfewKit -c release --product curfew-ctl --product curfew-mcp --product curfew-daemon

rm -rf "$BUNDLE" "$RAW"
mkdir -p "$OUT"
rm -f "$OUT"/curfew-*.png

echo "==> Running MarketingCaptureTests"
# `|| true`: a single scenario failing should not block exporting the rest.
xcodebuild test \
    -project Curfew.xcodeproj \
    -scheme Curfew \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath build \
    -only-testing:CurfewUITests/MarketingCaptureTests \
    -resultBundlePath "$BUNDLE" \
    || true

echo "==> Exporting attachments from result bundle"
xcrun xcresulttool export attachments \
    --path "$BUNDLE" \
    --output-path "$RAW"

# The exporter writes opaque filenames plus a manifest mapping each to the
# `suggestedHumanReadableName` we set in the test (curfew-<scenario>). Rename
# to those stable names so the landing page / docs can reference them.
echo "==> Renaming to stable scenario names"
python3 - "$RAW" "$OUT" <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
manifest_path = os.path.join(raw, "manifest.json")
if not os.path.exists(manifest_path):
    print("    !! no manifest.json found; leaving raw exports in place")
    sys.exit(0)
with open(manifest_path) as f:
    manifest = json.load(f)
# XCUITest appends "_<index>_<uuid>.png" to our attachment name — strip it
# back to the clean "curfew-<scenario>.png".
suffix = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?=\.png$)")
count = 0
for entry in manifest:
    for att in entry.get("attachments", []):
        exported = att.get("exportedFileName")
        name = att.get("suggestedHumanReadableName") or exported or ""
        # Only our scenario screenshots — skip the auto session recording.
        if not name.startswith("curfew-"):
            continue
        src = os.path.join(raw, exported) if exported else None
        if not src or not os.path.exists(src):
            continue
        clean = suffix.sub("", name)
        if not clean.lower().endswith(".png"):
            clean += ".png"
        shutil.copyfile(src, os.path.join(out, clean))
        count += 1
print(f"    exported {count} screenshot(s) to {out}")
PY

echo "==> Done. Screenshots in $OUT"
ls -1 "$OUT"/*.png 2>/dev/null || echo "(no PNGs produced)"
