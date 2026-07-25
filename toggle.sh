#!/usr/bin/env bash
# toggle.sh — enable/disable autowake (no schedule change)
#
# Reads ENABLED from config.sh and loads or unloads the launchd agents.
# Does NOT touch pmset wake schedule. Use ./sync.sh for schedule changes.
#
# Usage:
#   ./toggle.sh on     — set ENABLED=true in config.sh, then load the agents
#   ./toggle.sh off    — set ENABLED=false in config.sh, then unload them
#   ./toggle.sh        — act on whatever ENABLED already says in config.sh
#
# First-time setup or schedule change: run ./sync.sh (requires sudo for pmset).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

# ── Argument ──────────────────────────────────────────────────────────
# The on/off argument writes ENABLED into config.sh rather than only acting for
# this one run, because config.sh has to stay the single source of truth: if
# `off` merely unloaded the agents, the next ./sync.sh would read ENABLED=true
# and load them again — the argument and the file would disagree, and the file
# would win without saying so.
#
# An unrecognised argument is a hard error. Silently ignoring it is how
# `./toggle.sh off` used to *enable* autowake.
DESIRED=""
case "${1:-}" in
    on)  DESIRED=true  ;;
    off) DESIRED=false ;;
    "")  ;;
    -h|--help|help)
        echo "Usage: ./toggle.sh [on|off]"
        echo "  on   set ENABLED=true in config.sh, then load the launchd agents"
        echo "  off  set ENABLED=false in config.sh, then unload them"
        echo "  (no argument)  act on whatever ENABLED already says"
        exit 0
        ;;
    *)
        echo "toggle.sh: unknown argument '$1'" >&2
        echo "Usage: ./toggle.sh [on|off]" >&2
        exit 2
        ;;
esac

if [[ -n "$DESIRED" ]]; then
    # BSD sed (macOS) requires an explicit empty suffix for in-place editing.
    sed -i '' "s/^ENABLED=.*/ENABLED=$DESIRED/" "$CONFIG_FILE"
    echo "config.sh: ENABLED=$DESIRED"
    echo ""
fi

source "$CONFIG_FILE"

PLIST_LABEL="com.autowake.ping"
CAFFEINATE_LABEL="com.autowake.caffeinate"

echo "=== Claude Autowake Toggle ==="
echo "  ENABLED:    ${ENABLED:-false}"
echo "  PING_TIMES: ${PING_TIMES[*]}"
echo ""

if [[ "${ENABLED:-false}" != "true" ]]; then
    echo "Disabling autowake (unloading launchd agents)..."

    if launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null; then
        echo "  Unloaded: $PLIST_LABEL"
    else
        echo "  (not currently loaded: $PLIST_LABEL)"
    fi

    if launchctl bootout "gui/$(id -u)/${CAFFEINATE_LABEL}" 2>/dev/null; then
        echo "  Unloaded: $CAFFEINATE_LABEL"
    else
        echo "  (not currently loaded: $CAFFEINATE_LABEL)"
    fi

    echo ""
    echo "Disabled. plist files retained on disk; pmset wake kept (harmless)."
    echo "To re-enable: ./toggle.sh on"
    exit 0
fi

# ENABLED=true — delegate to sync.sh for plist regen + load.
# Pass AUTOWAKE_SKIP_PMSET=1 so daily toggles don't re-prompt for sudo.
echo "Enabling autowake (regenerating plists and loading agents)..."
echo ""
AUTOWAKE_SKIP_PMSET=1 exec "$SCRIPT_DIR/sync.sh"
