#!/usr/bin/env bash
# schedule.sh — change when autowake pings.
#
# Usage:
#   ./schedule.sh 08:30          one ping at 08:30
#   ./schedule.sh 08:00,13:30    two pings
#   ./schedule.sh                show the current times
#
# Writes PING_TIMES into ~/.claude-autowake/local.env and re-runs sync.sh to
# regenerate the launchd plist. The times are machine state, so they never
# touch a tracked file and the repo stays clean.
#
# No sudo unless the pmset recovery time also has to move; sync.sh compares
# first and says so if it does.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

if [ $# -eq 0 ]; then
    echo "Current ping times: ${PING_TIMES[*]}"
    echo "Usage: ./schedule.sh HH:MM[,HH:MM...]"
    exit 0
fi

NEW="$1"

# Validate before writing. An invalid time would otherwise produce a plist that
# launchd accepts but never fires — a failure with no error message anywhere.
IFS=',' read -ra _parts <<< "$NEW" || true
for _t in "${_parts[@]}"; do
    _t="$(printf '%s' "$_t" | tr -d '[:space:]')"
    if ! printf '%s' "$_t" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$'; then
        echo "schedule.sh: '$_t' is not a valid 24-hour HH:MM time." >&2
        exit 2
    fi
done

autowake_local_set PING_TIMES "$NEW"
echo "local.env: PING_TIMES=$NEW"
echo ""

# sync.sh re-reads config.sh, so it picks up the value just written. It also
# enforces the >= 5h spacing rule for multiple times.
exec "$SCRIPT_DIR/sync.sh"
