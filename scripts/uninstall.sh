#!/usr/bin/env bash
#
# Curfew uninstaller — removes every bit of local state Curfew writes.
#
# Paired with `UninstallCoordinator.swift`: both clean the same four
# locations so a user who never launches the app (CLI-only install, or
# installed and never opened) can still get a clean removal.
#
# Usage:
#   bash scripts/uninstall.sh          # interactive, confirms before each step
#   bash scripts/uninstall.sh --force  # skip confirmation
#
# The /Applications/Curfew.app bundle is intentionally left for the user
# to drag to the Trash — matches macOS convention and avoids sudo prompts.

set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
  FORCE=1
fi

confirm() {
  if (( FORCE == 1 )); then return 0; fi
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

say() { printf '%s\n' "$1"; }

AGENT_PLIST="$HOME/Library/LaunchAgents/studio.hypertext.curfew.lockdown.plist"
APP_SUPPORT="$HOME/Library/Application Support/Curfew"
CACHES="$HOME/Library/Caches/studio.hypertext.curfew"
PREFS="$HOME/Library/Preferences/studio.hypertext.curfew.plist"
APP_BUNDLE="/Applications/Curfew.app"

say "→ Curfew uninstall"
say ""

# 1. LaunchAgent — unload first so launchd doesn't respawn the app
#    between the unload and the plist removal.
if [[ -f "$AGENT_PLIST" ]]; then
  if confirm "Unload and remove LaunchAgent at $AGENT_PLIST?"; then
    /bin/launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
    say "  removed: $AGENT_PLIST"
  fi
else
  say "  (no LaunchAgent to remove)"
fi

# 2. Application Support — activity SQLite, MCP request queue, Unix socket.
if [[ -d "$APP_SUPPORT" ]]; then
  if confirm "Remove application support directory $APP_SUPPORT?"; then
    rm -rf "$APP_SUPPORT"
    say "  removed: $APP_SUPPORT"
  fi
else
  say "  (no application support directory)"
fi

# 3. Caches — bundle-ID keyed, OS-created.
if [[ -d "$CACHES" ]]; then
  if confirm "Remove caches directory $CACHES?"; then
    rm -rf "$CACHES"
    say "  removed: $CACHES"
  fi
else
  say "  (no caches directory)"
fi

# 4. UserDefaults — schedule, budgets, license key, settings.
if [[ -f "$PREFS" ]]; then
  if confirm "Clear preferences at $PREFS?"; then
    /usr/bin/defaults delete studio.hypertext.curfew 2>/dev/null || true
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
