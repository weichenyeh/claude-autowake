#!/usr/bin/env bash
# toggle.sh — enable/disable autowake (no schedule change)
#
# Writes ENABLED into ~/.claude-autowake/local.env, then brings the launchd
# agents into line.
#
# Usage:
#   ./toggle.sh on     — start pinging Claude again
#   ./toggle.sh off    — stop pinging Claude, keep reporting to Kuma
#   ./toggle.sh        — act on whatever ENABLED already says
#
# `off` deliberately leaves the ping agent loaded. The agent is what reports
# autowake's state to the monitor each day, so unloading it would make Kuma
# alarm 24 hours later about a state the user chose. When disabled the agent
# only sends a heartbeat and exits without calling Claude, so it costs
# nothing. Only the caffeinate agent is unloaded, since keeping the Mac awake
# for a ping that will not happen has no purpose.
#
# Schedule changes: ./schedule.sh HH:MM. First-time setup: ./sync.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

# ── Argument ──────────────────────────────────────────────────────────
# The on/off argument is persisted rather than applied only to this run,
# because the stored value has to stay the single source of truth: if `off`
# merely unloaded an agent, the next ./sync.sh would read ENABLED=true and
# undo it — the argument and the file would disagree, and the file would win
# without saying so.
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
        echo "  on   resume pinging Claude"
        echo "  off  stop pinging Claude; keep reporting to Kuma (no tokens used)"
        echo "  (no argument)  act on whatever ENABLED already says"
        exit 0
        ;;
    *)
        echo "toggle.sh: unknown argument '$1'" >&2
        echo "Usage: ./toggle.sh [on|off]" >&2
        exit 2
        ;;
esac

source "$CONFIG_FILE"

if [[ -n "$DESIRED" ]]; then
    autowake_local_set ENABLED "$DESIRED"
    echo "local.env: ENABLED=$DESIRED"
    echo ""
    ENABLED="$DESIRED"
fi

PLIST_LABEL="com.autowake.ping"
CAFFEINATE_LABEL="com.autowake.caffeinate"

echo "=== Claude Autowake Toggle ==="
echo "  ENABLED:    ${ENABLED:-false}"
echo "  PING_TIMES: ${PING_TIMES[*]}"
echo ""

if [[ "${ENABLED:-false}" != "true" ]]; then
    echo "Disabling autowake (Claude will not be called)..."

    # caffeinate goes away — no ping to stay awake for.
    if launchctl bootout "gui/$(id -u)/${CAFFEINATE_LABEL}" 2>/dev/null; then
        echo "  Unloaded: $CAFFEINATE_LABEL"
    else
        echo "  (not currently loaded: $CAFFEINATE_LABEL)"
    fi

    # The ping agent stays. It is what keeps the monitor informed.
    if launchctl list "$PLIST_LABEL" &>/dev/null; then
        echo "  Kept loaded: $PLIST_LABEL (reports 'disabled' to Kuma daily)"
    else
        echo "  WARNING: $PLIST_LABEL is not loaded, so nothing will report to"
        echo "           Kuma and it will alarm in 24h. Run ./sync.sh to load it."
    fi

    echo ""
    echo "Disabled. No tokens will be used; the daily heartbeat continues."
    echo "To re-enable: ./toggle.sh on"
    exit 0
fi

# ENABLED=true — delegate to sync.sh for plist regen + load.
# Pass AUTOWAKE_SKIP_PMSET=1 so daily toggles don't re-prompt for sudo.
echo "Enabling autowake (regenerating plists and loading agents)..."
echo ""
AUTOWAKE_SKIP_PMSET=1 exec "$SCRIPT_DIR/sync.sh"
