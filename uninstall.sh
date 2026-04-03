#!/usr/bin/env bash
set -euo pipefail

PLIST_LABEL="com.autowake.ping"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
CAFFEINATE_LABEL="com.autowake.caffeinate"
CAFFEINATE_PLIST="$HOME/Library/LaunchAgents/${CAFFEINATE_LABEL}.plist"
LOG_DIR="$HOME/.claude-autowake/logs"

echo "=== Claude Autowake Uninstaller ==="
echo ""

# ── Unload launchd agents ─────────────────────────────────────────────
echo "Unloading launchd agents..."

if launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null; then
    echo "  Unloaded: $PLIST_LABEL"
else
    echo "  $PLIST_LABEL was not loaded (skipping)"
fi

if launchctl bootout "gui/$(id -u)/${CAFFEINATE_LABEL}" 2>/dev/null; then
    echo "  Unloaded: $CAFFEINATE_LABEL"
else
    echo "  $CAFFEINATE_LABEL was not loaded (skipping)"
fi

# ── Remove plist files ────────────────────────────────────────────────
echo ""
echo "Removing plist files..."

for plist in "$PLIST_PATH" "$CAFFEINATE_PLIST"; do
    if [ -f "$plist" ]; then
        rm -f "$plist"
        echo "  Removed: $plist"
    else
        echo "  Not found: $plist (skipping)"
    fi
done

# ── Cancel pmset wake schedule ────────────────────────────────────────
echo ""
echo "Cancelling pmset wake schedule..."
echo "  (This requires sudo — you may be prompted for your password)"

if sudo pmset repeat cancel 2>/dev/null; then
    echo "  pmset repeat schedule cancelled."
else
    echo "  No pmset repeat schedule found (skipping)"
fi

# ── Optionally remove logs ────────────────────────────────────────────
echo ""
if [ -d "$LOG_DIR" ]; then
    read -rp "Remove log files in $LOG_DIR? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -rf "$LOG_DIR"
        echo "  Logs removed."
        rmdir "$HOME/.claude-autowake" 2>/dev/null || true
    else
        echo "  Logs kept at: $LOG_DIR"
    fi
else
    echo "No log directory found."
fi

echo ""
echo "=== Uninstall Complete ==="
