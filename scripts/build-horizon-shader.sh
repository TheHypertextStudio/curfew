#!/bin/sh
# Regenerate Curfew/UI/Horizon/HorizonSky.metallib from HorizonSky.metal and
# record the source's SHA-256 beside it. The app and screen saver bundle the
# checked-in library, so ordinary builds never need the Metal toolchain; run
# this only after editing the shader, and commit both outputs.
#
# Flags match what Xcode passes when it compiles a SwiftUI stitchable shader
# for the macOS 26 deployment target (taken from a real build log), without
# the debug-only line tables and embedded sources.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
horizon="$root/Curfew/UI/Horizon"
source="$horizon/HorizonSky.metal"
library="$horizon/HorizonSky.metallib"
target=air64-apple-macos26.0

sdk=$(xcrun --sdk macosx --show-sdk-path)

# Xcode can ship without a Metal toolchain matching its build. Try the default
# lookup first, then any installed Metal toolchain by identifier.
metal() {
  if xcrun -sdk macosx metal --version > /dev/null 2>&1; then
    xcrun -sdk macosx metal "$@"
    return
  fi
  for identifier in $(xcodebuild -showComponent MetalToolchain 2> /dev/null |
    awk -F': *' '/Toolchain Identifier/ { print $2 }'); do
    if TOOLCHAINS="$identifier" xcrun metal --version > /dev/null 2>&1; then
      TOOLCHAINS="$identifier" xcrun metal "$@"
      return
    fi
  done
  echo "No Metal toolchain is installed. Install it with:" >&2
  echo "  xcodebuild -downloadComponent MetalToolchain" >&2
  echo "then run this script again." >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

metal -c -target "$target" -isysroot "$sdk" \
  -fmetal-math-mode=fast -fmetal-math-fp32-functions=fast \
  -o "$work/HorizonSky.air" "$source"
metal -target "$target" -o "$work/HorizonSky.metallib" "$work/HorizonSky.air"

mv "$work/HorizonSky.metallib" "$library"
shasum -a 256 "$source" | awk '{ print $1 }' > "$horizon/HorizonSky.metal.sha256"
echo "Wrote $library"
