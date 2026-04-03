#!/usr/bin/env bash
set -euo pipefail

PLIST_LABEL="com.autowake.ping"
CAFFEINATE_LABEL="com.autowake.caffeinate"
LOG_DIR="$HOME/.claude-autowake/logs"

echo "=== Claude Autowake Status ==="
echo ""

# ── launchd agents ────────────────────────────────────────────────────
echo "Launchd agents:"
if launchctl list "$PLIST_LABEL" &>/dev/null; then
    echo "  $PLIST_LABEL: loaded"
else
    echo "  $PLIST_LABEL: not loaded"
fi
if launchctl list "$CAFFEINATE_LABEL" &>/dev/null; then
    echo "  $CAFFEINATE_LABEL: loaded"
else
    echo "  $CAFFEINATE_LABEL: not loaded"
fi

# ── Ping schedule (from plist) ────────────────────────────────────────
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
echo ""
echo "Ping schedule:"
if [ -f "$PLIST_PATH" ]; then
    # Extract hour/minute pairs from the plist
    /usr/libexec/PlistBuddy -c "Print :StartCalendarInterval" "$PLIST_PATH" 2>/dev/null \
        | grep -E "Hour|Minute" \
        | paste - - \
        | while read -r h_line m_line; do
            hour=$(echo "$h_line" | grep -oE '[0-9]+')
            minute=$(echo "$m_line" | grep -oE '[0-9]+')
            printf "  %02d:%02d\n" "$hour" "$minute"
          done
    if [ $? -ne 0 ]; then
        echo "  (could not parse plist)"
    fi
else
    echo "  No plist found at $PLIST_PATH"
fi

# ── pmset wake schedule ───────────────────────────────────────────────
echo ""
echo "pmset wake schedule:"
SCHED=$(pmset -g sched 2>/dev/null || true)
if [ -n "$SCHED" ]; then
    echo "$SCHED" | sed 's/^/  /'
else
    echo "  No wake schedule set"
fi

# ── Last ping result ─────────────────────────────────────────────────
echo ""
echo "Last ping:"
if [ -d "$LOG_DIR" ]; then
    LATEST=$(ls -1t "$LOG_DIR"/ping_*.log 2>/dev/null | head -1)
    if [ -n "$LATEST" ]; then
        echo "  Log: $LATEST"
        # Show the result line (completed/failed) and timing
        tail -5 "$LATEST" | sed 's/^/  /'
    else
        echo "  No log files found"
    fi
else
    echo "  Log directory not found ($LOG_DIR)"
fi
