#!/bin/bash
set -euo pipefail
cd "${SRCROOT:?Xcode SRCROOT is required}"

case "$CONFIGURATION" in
    Debug) EXPECTED_DAEMON_PLIST="studio.hypertext.apps.curfew.dev.daemon.plist" ;;
    Release) EXPECTED_DAEMON_PLIST="studio.hypertext.curfew.daemon.plist" ;;
    *) echo "Unsupported Curfew build configuration: $CONFIGURATION" >&2; exit 1 ;;
esac
if [[ "$CURFEW_DAEMON_PLIST_NAME" != "$EXPECTED_DAEMON_PLIST" ]]; then
    echo "Curfew daemon identity does not match $CONFIGURATION" >&2
    exit 1
fi

build_args=(build --package-path CurfewKit -c release --jobs 2)
# Xcode resolves ARCHS for this build, including active-architecture Debug builds.
# Use the same explicit architecture set for building and locating every product.
read -r -a architectures <<< "${ARCHS:?Xcode ARCHS is required}"
if [[ ${#architectures[@]} -eq 0 ]]; then
    echo "Xcode ARCHS must contain at least one architecture" >&2
    exit 1
fi
for arch in "${architectures[@]}"; do
    build_args+=(--arch "$arch")
done
if [[ -n "${CURFEW_SERVICE_SWIFT_FLAG:-}" ]]; then
    if [[ "$CURFEW_SERVICE_SWIFT_FLAG" != CURFEW_STAGING ]]; then
        echo "Unsupported Curfew service environment: $CURFEW_SERVICE_SWIFT_FLAG" >&2
        exit 1
    fi
    if [[ "$CONFIGURATION" != Debug ]]; then
        echo "CURFEW_STAGING requires an isolated Debug app and helper identity" >&2
        exit 1
    fi
    build_args+=(-Xswiftc -DCURFEW_STAGING)
fi

contents="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH"
mkdir -p "$contents/Resources" "$contents/Library/LaunchDaemons"
for tool in curfew-ctl curfew-mcp curfew-daemon studio.hypertext.curfew.browser; do
    swift "${build_args[@]}" --product "$tool"
    bin_path=$(swift "${build_args[@]}" --product "$tool" --show-bin-path)
    for arch in "${architectures[@]}"; do
        /usr/bin/lipo "$bin_path/$tool" -verify_arch "$arch"
    done
    cp "$bin_path/$tool" "$contents/Resources/$tool"
    echo "Bundled $tool architectures: $(/usr/bin/lipo -archs "$contents/Resources/$tool") (Xcode ARCHS: $ARCHS)"
    if [[ "${CODE_SIGNING_ALLOWED:-}" != NO ]]; then
        /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime "$contents/Resources/$tool"
    fi
done
cp "Curfew/Resources/LaunchDaemons/$CURFEW_DAEMON_PLIST_NAME" "$contents/Library/LaunchDaemons/$CURFEW_DAEMON_PLIST_NAME"
