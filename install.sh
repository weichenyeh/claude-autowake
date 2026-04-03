#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

PLIST_LABEL="com.autowake.ping"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
AUTOWAKE_SCRIPT="$SCRIPT_DIR/autowake.sh"
CAFFEINATE_LABEL="com.autowake.caffeinate"
CAFFEINATE_PLIST="$HOME/Library/LaunchAgents/${CAFFEINATE_LABEL}.plist"

echo "=== Claude Autowake Installer ==="
echo ""

# ── Validate ping times are >= 5h apart ───────────────────────────────
prev_total=-1
for time in "${PING_TIMES[@]}"; do
    h=$((10#${time%%:*}))
    m=$((10#${time##*:}))
    if (( h > 23 || m > 59 )); then
        echo "ERROR: Invalid time '$time'. Hours must be 0-23, minutes 0-59."
        exit 1
    fi
    total=$(( h * 60 + m ))
    if (( prev_total >= 0 )); then
        gap=$(( total - prev_total ))
        if (( gap < 300 )); then
            echo "ERROR: Ping times must be >= 5 hours (300 min) apart."
            echo "  Gap between $(printf "%02d:%02d" $((prev_total/60)) $((prev_total%60))) and $time is only ${gap} min."
            exit 1
        fi
    fi
    prev_total=$total
done

FIRST_TIME="${PING_TIMES[0]}"
FIRST_HOUR=$((10#${FIRST_TIME%%:*}))
FIRST_MINUTE=$((10#${FIRST_TIME##*:}))

echo "Ping schedule:"
for t in "${PING_TIMES[@]}"; do
    echo "  $t"
done
echo ""

# ── Preflight checks ─────────────────────────────────────────────────
if ! command -v "$CLAUDE_BIN" &>/dev/null; then
    echo "WARNING: '$CLAUDE_BIN' not found in PATH."
    echo "  Make sure claude is installed and accessible before the first ping."
    echo ""
fi

# Ensure scripts are executable
chmod +x "$AUTOWAKE_SCRIPT"
chmod +x "$SCRIPT_DIR/uninstall.sh" 2>/dev/null || true

# Create log directory
mkdir -p "$LOG_DIR"

# Ensure LaunchAgents directory exists
mkdir -p "$HOME/Library/LaunchAgents"

# Capture the user's PATH so launchd can find claude
USER_PATH="$PATH"

# ── Generate ping launchd plist ───────────────────────────────────────
echo "Generating launchd plist at: $PLIST_PATH"

CALENDAR_ENTRIES=""
for time in "${PING_TIMES[@]}"; do
    hour=$((10#${time%%:*}))
    minute=$((10#${time##*:}))
    CALENDAR_ENTRIES+="
            <dict>
                <key>Hour</key>
                <integer>$hour</integer>
                <key>Minute</key>
                <integer>$minute</integer>
            </dict>"
done

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${AUTOWAKE_SCRIPT}</string>
    </array>

    <key>StartCalendarInterval</key>
    <array>${CALENDAR_ENTRIES}
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${USER_PATH}</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/launchd_stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/launchd_stderr.log</string>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

# ── Generate caffeinate launchd plist ─────────────────────────────────
echo "Generating caffeinate plist at: $CAFFEINATE_PLIST"

cat > "$CAFFEINATE_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${CAFFEINATE_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-dimsu</string>
        <string>-t</string>
        <string>${CAFFEINATE_SECONDS}</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${FIRST_HOUR}</integer>
        <key>Minute</key>
        <integer>${FIRST_MINUTE}</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/caffeinate_stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/caffeinate_stderr.log</string>
</dict>
</plist>
EOF

# ── Load launchd agents ───────────────────────────────────────────────
echo ""
echo "Loading launchd agents..."

launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/${CAFFEINATE_LABEL}" 2>/dev/null || true

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl bootstrap "gui/$(id -u)" "$CAFFEINATE_PLIST"

echo "  Loaded: $PLIST_LABEL"
echo "  Loaded: $CAFFEINATE_LABEL"

# ── Schedule pmset wake ───────────────────────────────────────────────
echo ""
WAKE_HOUR=$FIRST_HOUR
WAKE_MINUTE=$(( FIRST_MINUTE - WAKE_LEAD_MINUTES ))

if (( WAKE_MINUTE < 0 )); then
    WAKE_MINUTE=$(( WAKE_MINUTE + 60 ))
    WAKE_HOUR=$(( WAKE_HOUR - 1 ))
fi

WAKE_TIME=$(printf "%02d:%02d:00" "$WAKE_HOUR" "$WAKE_MINUTE")

echo "Setting pmset wake schedule: daily at $WAKE_TIME"
echo "  (This requires sudo — you may be prompted for your password)"
echo ""

if sudo pmset repeat wakeorpoweron MTWRFSU "$WAKE_TIME"; then
    echo "  pmset wake scheduled successfully."
else
    echo "  WARNING: Failed to set pmset wake schedule."
    echo "  You can set it manually: sudo pmset repeat wakeorpoweron MTWRFSU $WAKE_TIME"
fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Schedule (one message to $CLAUDE_MODEL per slot):"
for t in "${PING_TIMES[@]}"; do
    echo "  $t"
done
echo ""
echo "  Mac wakes at $WAKE_TIME (${WAKE_LEAD_MINUTES} min before first ping)"
echo "  caffeinate keeps Mac awake for $(( CAFFEINATE_SECONDS / 3600 ))h"
echo ""
echo "Logs:     $LOG_DIR"
echo "Config:   $SCRIPT_DIR/config.sh"
echo ""
echo "To test now:  ./autowake.sh"
echo "To remove:    ./uninstall.sh"
