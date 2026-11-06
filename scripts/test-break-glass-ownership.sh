#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$EUID" -eq 0 ]]; then
  echo "Run this fixture driver as the CI user. It resolves that user's IDs before invoking sudo." >&2
  exit 1
fi
printf '%s\n' 'Step 1: Verify passwordless sudo for the isolated ownership fixture.'
sudo -n true
printf '%s\n' 'Step 2: Copy package sources into a disposable test tree.'
mkdir -p "$repo_root/build"
run_root="$(mktemp -d "$repo_root/build/curfew-ownership-run-XXXXXX")"
cleanup() {
  script_status=$?
  trap - EXIT
  case "$run_root" in
    "$repo_root"/build/curfew-ownership-run-*)
      printf '%s\n' 'Step 6: Remove only the disposable package, scratch data, and fixture.'
      sudo -n /bin/rm -rf -- "$run_root" || script_status=1
      ;;
    *)
      echo "Refusing to remove an unexpected fixture path." >&2
      script_status=1
      ;;
  esac
  exit "$script_status"
}
trap cleanup EXIT
package_copy="$run_root/CurfewKit"
fixture="$run_root/curfew-recovery-ownership-home"
mkdir -p "$package_copy" "$fixture" "$run_root/cache" "$run_root/config" "$run_root/security"
cp "$repo_root/CurfewKit/Package.swift" "$package_copy/Package.swift"
if [[ -f "$repo_root/CurfewKit/Package.resolved" ]]; then
  cp "$repo_root/CurfewKit/Package.resolved" "$package_copy/Package.resolved"
fi
cp -R "$repo_root/CurfewKit/Sources" "$repo_root/CurfewKit/Tests" "$package_copy/"
protocol_override="${CURFEW_PROTOCOLS_LOCAL_PATH-}"
if [[ -n "$protocol_override" && "$protocol_override" != /* ]]; then
  protocol_override="$(cd "$repo_root/CurfewKit/$protocol_override" && pwd)"
fi
fixture_uid="$(id -u)"
fixture_gid="$(id -g)"
swift_binary="$(xcrun --find swift)"
common=(
  --package-path "$package_copy"
  --scratch-path "$run_root/scratch"
  --cache-path "$run_root/cache"
  --config-path "$run_root/config"
  --security-path "$run_root/security"
  --manifest-cache local
)
printf '%s\n' 'Step 3: Build the isolated test runner as the ordinary CI user.'
CURFEW_PROTOCOLS_LOCAL_PATH="$protocol_override" \
  "$swift_binary" build "${common[@]}" --build-tests --jobs 2 -Xswiftc -j2
printf '%s\n' 'Step 4: Exercise real credential switching in that tree with a fake shutdown canceller.'
sudo -n /usr/bin/env \
  CURFEW_PROTOCOLS_LOCAL_PATH="$protocol_override" \
  CURFEW_ROOT_OWNERSHIP_FIXTURE="$fixture" \
  CURFEW_ROOT_OWNERSHIP_UID="$fixture_uid" \
  CURFEW_ROOT_OWNERSHIP_GID="$fixture_gid" \
  "$swift_binary" test "${common[@]}" --skip-build --disable-automatic-resolution \
  --filter PrivilegedBreakGlassOwnershipAcceptance
printf '%s\n' 'Step 5: Confirm the fixture returned to an empty user-owned directory.'
rmdir "$fixture"
