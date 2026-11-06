#!/usr/bin/env bash
set -euo pipefail

[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == macOS ]]
[[ "$(id -un)" == runner && "$PWD" == "$RUNNER_TEMP" ]]
mode=${1:?Expected fresh-install or upgrade}
candidate=${2:?Expected the verified candidate directory}
source_root=${3:?Expected the exact candidate source checkout}
[[ "$mode" == fresh-install || "$mode" == upgrade ]]
app=/Applications/Curfew.app
tap=thehypertextstudio/tap
token="$tap/curfew"
[[ ! -e "$app" ]]
for tool in curfew-ctl curfew-mcp; do
  if command -v "$tool"; then
    echo "$tool already exists on PATH" >&2
    exit 1
  fi
done

version=$(jq -er .version "$candidate/candidate.json")
digest=$(jq -er .dmgSHA256 "$candidate/candidate.json")
image="$candidate/Curfew-v$version.dmg"
[[ "$version" =~ ^0\.0\.[0-9]+$ && "$digest" =~ ^[a-f0-9]{64}$ ]]
xcrun stapler validate "$image"
spctl --assess --type open --context context:primary-signature --verbose=2 "$image"

brew --version
sw_vers
brew tap "$tap"
tap_dir=$(brew --repository "$tap")
cask="$tap_dir/Casks/curfew.rb"
recipe=$(mktemp "$RUNNER_TEMP/curfew-candidate-cask.XXXXXX")
trap 'rm -f "$recipe"' EXIT
script_dir=$(dirname "$0")
prior_version=$(python3 "$script_dir/prepare-homebrew-candidate-cask.py" "$cask" "$recipe" "$image" "$version" "$digest")
printf 'Public Curfew %s at tap commit %s\n' "$prior_version" "$(git -C "$tap_dir" rev-parse HEAD)"

if [[ "$mode" == upgrade ]]; then
  brew install --cask "$token"
  brew list --cask --versions | grep -Fx "curfew $prior_version"
  curfew-ctl --help | grep 'curfew-ctl'
fi
cp "$recipe" "$cask"

operation=install
if [[ "$mode" == upgrade ]]; then operation=upgrade; fi
brew "$operation" --cask "$token"
brew list --cask --versions | grep -Fx "curfew $version"
(
  cd "$source_root"
  bash scripts/verify-release-artifact.sh "$app" "$candidate/release-configuration.json" "$version"
)
codesign --verify --strict --deep "$app"

for tool in curfew-ctl curfew-mcp; do
  command_file=$(command -v "$tool")
  [[ -L "$command_file" && -x "$command_file" ]]
  actual=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$command_file")
  [[ "$actual" == "$app/Contents/Resources/$tool" ]]
  printf '%s resolves through PATH at %s\n' "$tool" "$command_file"
done

[[ "$(curfew-ctl --version)" == "curfew-ctl $version" ]]
curfew-ctl --help | grep -F 'Curfew command line (beta).' > /dev/null
for command_path in status setup completion explain schedule 'schedule show' 'schedule set' budget activity audit reflections override extension request 'request status' 'request prune' work 'work claim' 'work list' 'work release' break-glass; do
  read -r -a args <<< "$command_path"
  curfew-ctl "${args[@]}" --help | grep -F 'Curfew command line (beta).' > /dev/null
done
curfew-ctl status --json | jq -e '.schema_version == 1 and .status == "ok" and .phase == "unknown"'
curfew-ctl schedule show --json | jq -e '.schema_version == 1 and .status == "ok" and (.days | length == 7)'
curfew-ctl request status 00000000-0000-4000-8000-000000000001 --json \
  | jq -e '.schema_version == 1 and .status == "ok" and .request_status == "not_found"'
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | curfew-mcp \
  | jq -e '.id == 1 and .result.serverInfo.name == "curfew-mcp"'

link_state() {
  stat -f '%i:%m:%N' "$(command -v curfew-ctl)" "$(command -v curfew-mcp)"
}
before=$(link_state)
brew "$operation" --cask "$token"
[[ "$(link_state)" == "$before" ]]
printf 'Signed Curfew %s passed Homebrew %s, 22 beta help paths, JSON reads, and an unchanged repeat.\n' \
  "$version" "$mode" | tee -a "$GITHUB_STEP_SUMMARY"
