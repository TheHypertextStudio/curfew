#!/usr/bin/env bash
#
# Curfew uninstaller — removes every bit of local state Curfew writes.
#
# Paired with `UninstallCoordinator.swift`: both clean the same five
# locations so a user who never launches the app (CLI-only install, or
# installed and never opened) can still get a clean removal.
#
# Usage:
#   bash scripts/uninstall.sh          # interactive, confirms before each step
#   bash scripts/uninstall.sh --force  # skip confirmation
#
# The /Applications/Curfew.app bundle is intentionally left for the user
# to drag to the Trash — matches macOS convention and avoids sudo prompts.

# Kept sourceable so path cleanup can be exercised only against a temporary tree.
remove_shared_storage() {
  local user_home="$1"
  local shared_support
  for shared_support in \
    "$user_home/Library/Group Containers/group.studio.hypertext.curfew/Curfew" \
    "$user_home/Library/Group Containers/group.studio.hypertext.apps.curfew/Curfew"; do
    if [[ -d "$shared_support" ]]; then
      if confirm "Remove shared storage directory $shared_support?"; then
        rm -rf "$shared_support"
        say "  removed: $shared_support"
      fi
    else
      say "  (no shared storage directory at $shared_support)"
    fi
  done
}

# Sourcing exposes only the isolated helper, never the actual uninstall flow.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

set -euo pipefail

FORCE=0
DEVELOPMENT=0
APP_BUNDLE=""
while (( $# )); do
  case "$1" in
    --force|-f) FORCE=1; shift ;;
    --development) DEVELOPMENT=1; shift ;;
    --app-bundle)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--app-bundle requires a path" >&2; exit 64; }
      APP_BUNDLE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

confirm() {
  if (( FORCE == 1 )); then return 0; fi
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

say() { printf '%s\n' "$1"; }

AGENT_PLIST="$HOME/Library/LaunchAgents/studio.hypertext.curfew.lockdown.plist"
STORAGE_SUFFIX=""
DISPLAY_SUFFIX=""
EXPECTED_IDENTIFIER="studio.hypertext.apps.curfew"
if (( DEVELOPMENT )); then
  STORAGE_SUFFIX=".studio.dev"
  DISPLAY_SUFFIX=" (Studio Dev)"
  EXPECTED_IDENTIFIER="studio.hypertext.apps.curfew.dev"
  APP_BUNDLE="${APP_BUNDLE:-/Applications/Curfew Dev.app}"
else
  APP_BUNDLE="${APP_BUNDLE:-/Applications/Curfew.app}"
fi
APP_SUPPORT="$HOME/Library/Application Support/Curfew$DISPLAY_SUFFIX"
PREFERENCE_DOMAIN="studio.hypertext.curfew$STORAGE_SUFFIX"
CACHES="$HOME/Library/Caches/$PREFERENCE_DOMAIN"
PREFS="$HOME/Library/Preferences/$PREFERENCE_DOMAIN.plist"
DAEMON_LABEL="studio.hypertext.curfew.daemon"
ROOT_SUPPORT="/Library/Application Support/Curfew"

say "→ Curfew uninstall"
INFO="$APP_BUNDLE/Contents/Info.plist"
IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null) || exit 1
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO" 2>/dev/null) || exit 1
if [[ "$IDENTIFIER" != "$EXPECTED_IDENTIFIER" || -z "$EXECUTABLE" || "$EXECUTABLE" == */* || "$EXECUTABLE" == .* ]]; then
  say "The selected app does not match the requested Curfew flavor." >&2
  exit 1
fi
if [[ ! -x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" ]]; then
  say "Curfew must be present to unregister its background service before uninstall." >&2
  exit 1
fi
confirm "Stop background recovery and remove this Curfew flavor's state?" || exit 0
# Recovery must stop before any saved state is removed.
if ! "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" --unregister-background-service; then
  say "Background recovery could not be disabled. Curfew's saved state was kept." >&2
  exit 1
fi

# 1. Privileged daemon — boot out before removing its root-owned state.
if (( DEVELOPMENT == 0 )) && confirm "Remove the privileged Curfew helper and root-owned state?"; then
  sudo /bin/launchctl bootout "system/$DAEMON_LABEL" 2>/dev/null || true
  sudo rm -rf "$ROOT_SUPPORT"
  say "  removed: system/$DAEMON_LABEL and $ROOT_SUPPORT"
fi

# 2. LaunchAgent — unload first so launchd doesn't respawn the app
#    between the unload and the plist removal.
if (( DEVELOPMENT == 0 )) && [[ -f "$AGENT_PLIST" ]]; then
  if confirm "Unload and remove LaunchAgent at $AGENT_PLIST?"; then
    /bin/launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
    say "  removed: $AGENT_PLIST"
  fi
else
  say "  (no LaunchAgent to remove)"
fi

# 3. Application Support — MCP request queue, Unix socket, legacy local files.
if [[ -d "$APP_SUPPORT" ]]; then
  if confirm "Remove application support directory $APP_SUPPORT?"; then
    rm -rf "$APP_SUPPORT"
    say "  removed: $APP_SUPPORT"
  fi
else
  say "  (no application support directory)"
fi

# 4. Shared group-container storage — legacy activity history and widget snapshots.
if (( DEVELOPMENT )); then
  SHARED_SUPPORT="$HOME/Library/Group Containers/group.studio.hypertext.curfew.studio.dev/Curfew"
  if [[ -d "$SHARED_SUPPORT" ]] && confirm "Remove shared storage directory $SHARED_SUPPORT?"; then
    rm -rf "$SHARED_SUPPORT"
  fi
else
  remove_shared_storage "$HOME"
fi

# 5. Caches — bundle-ID keyed, OS-created.
if [[ -d "$CACHES" ]]; then
  if confirm "Remove caches directory $CACHES?"; then
    rm -rf "$CACHES"
    say "  removed: $CACHES"
  fi
else
  say "  (no caches directory)"
fi

# 6. UserDefaults — schedule, budgets, license key, settings.
if [[ -f "$PREFS" ]]; then
  if confirm "Clear preferences at $PREFS?"; then
    /usr/bin/defaults delete "$PREFERENCE_DOMAIN" 2>/dev/null || true
    rm -f "$PREFS"
    say "  removed: $PREFS"
  fi
else
  say "  (no preferences file)"
fi

say ""
if [[ -d "$APP_BUNDLE" ]]; then
  say "→ The app bundle is still at $APP_BUNDLE."
  say "  Drag Curfew.app to the Trash to finish removing the app:"
  say "    open -R $APP_BUNDLE"
else
  say "→ No app bundle found at $APP_BUNDLE. Uninstall is complete."
fi
