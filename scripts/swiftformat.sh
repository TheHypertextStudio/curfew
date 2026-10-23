#!/bin/sh
# Keep local and CI formatting on the same reviewed official release.
set -eu

version=0.63.1
archive_sha256=385ef1a263ba28685157b98c5536b9c9105e124518f28b7ef8a2bee4b167eaeb
binary_sha256=136d4a990a7c63f313baa9081ffa451cb1988eacac3128e810564ca1efbf3083
url="https://github.com/nicklockwood/SwiftFormat/releases/download/$version/swiftformat.zip"

fail() { printf '%s\n' "swiftformat: $*" >&2; exit 1; }
matches() {
    [ -f "$1" ] || return 1
    digest=$(/usr/bin/shasum -a 256 < "$1")
    [ "${digest%% *}" = "$2" ]
}

[ "$(uname -s)" = Darwin ] || fail 'The pinned formatter requires macOS.'
cache="${XDG_CACHE_HOME:-${HOME:?HOME is required}/.cache}/curfew/swiftformat/$version"
tool="$cache/swiftformat"
if ! matches "$tool" "$binary_sha256"; then
    mkdir -p "$cache"
    staging=$(mktemp -d "$cache/.download.XXXXXXXX")
    trap 'rm -rf "$staging"' EXIT HUP INT TERM
    curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
        --connect-timeout 20 --max-time 120 "$url" -o "$staging/swiftformat.zip"
    matches "$staging/swiftformat.zip" "$archive_sha256" ||
        fail 'Official archive SHA-256 does not match the release pin.'
    /usr/bin/unzip -p "$staging/swiftformat.zip" swiftformat > "$staging/swiftformat"
    matches "$staging/swiftformat" "$binary_sha256" ||
        fail 'Extracted binary SHA-256 does not match the release pin.'
    chmod 755 "$staging/swiftformat"
    [ "$("$staging/swiftformat" --version)" = "$version" ] ||
        fail "Expected SwiftFormat $version."
    # Concurrent checkouts install identical verified bytes with one rename.
    mv -f "$staging/swiftformat" "$tool"
    rm -rf "$staging"
    trap - EXIT HUP INT TERM
fi
[ "$("$tool" --version)" = "$version" ] || fail "Expected SwiftFormat $version."
exec "$tool" "$@"
