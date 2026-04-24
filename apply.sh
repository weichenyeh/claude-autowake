#!/usr/bin/env bash
# apply.sh — daily toggle for claude-autowake
#
# Reads ENABLED from config.sh and loads or unloads the launchd agents.
# Does NOT touch pmset wake schedule (set once by install.sh; leave alone).
#
# Usage:
#   1. Edit config.sh (ENABLED, PING_TIMES, etc.)
#   2. Run: ./apply.sh
#
# First-time setup: run ./install.sh first (requires sudo for pmset).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

PLIST_LABEL="com.autowake.ping"
CAFFEINATE_LABEL="com.autowake.caffeinate"

echo "=== Claude Autowake Apply ==="
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
    echo "To re-enable: set ENABLED=true in config.sh and run ./apply.sh"
    exit 0
fi

# ENABLED=true — delegate to install.sh for plist regen + load.
# Pass AUTOWAKE_SKIP_PMSET=1 so daily toggles don't re-prompt for sudo.
echo "Enabling autowake (regenerating plists and loading agents)..."
echo ""
AUTOWAKE_SKIP_PMSET=1 exec "$SCRIPT_DIR/install.sh"
