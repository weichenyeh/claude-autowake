#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

PLIST_LABEL="com.autowake.ping"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
CAFFEINATE_LABEL="com.autowake.caffeinate"
CAFFEINATE_PLIST="$HOME/Library/LaunchAgents/${CAFFEINATE_LABEL}.plist"

# Scripts are copied to ~/.claude-autowake/bin/ at install time so that
# launchd can access them without macOS TCC blocking reads from ~/Documents.
INSTALL_BIN_DIR="$HOME/.claude-autowake/bin"
AUTOWAKE_SCRIPT="$INSTALL_BIN_DIR/autowake.sh"

echo "=== Claude Autowake Sync ==="
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

LAST_TIME="${PING_TIMES[${#PING_TIMES[@]}-1]}"
LAST_HOUR=$((10#${LAST_TIME%%:*}))
LAST_MINUTE=$((10#${LAST_TIME##*:}))

# ── Auto-calculate caffeinate duration if "auto" ───────────────────────
if [[ "$CAFFEINATE_SECONDS" == "auto" ]]; then
    first_total=$(( FIRST_HOUR * 60 + FIRST_MINUTE ))
    last_total=$(( LAST_HOUR * 60 + LAST_MINUTE ))
    span_minutes=$(( last_total - first_total + 10 ))  # +10 min buffer
    if (( span_minutes < 10 )); then
        span_minutes=10  # minimum 10 min for single-ping configs
    fi
    CAFFEINATE_SECONDS=$(( span_minutes * 60 ))
fi

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

# Ensure source scripts are executable
chmod +x "$SCRIPT_DIR/autowake.sh"
chmod +x "$SCRIPT_DIR/uninstall.sh" 2>/dev/null || true

# Create log directory
mkdir -p "$LOG_DIR"

# Copy scripts to a TCC-safe location (~/Documents is protected by macOS)
echo "Copying scripts to $INSTALL_BIN_DIR ..."
mkdir -p "$INSTALL_BIN_DIR"
cp "$SCRIPT_DIR/autowake.sh" "$INSTALL_BIN_DIR/autowake.sh"
cp "$SCRIPT_DIR/config.sh"   "$INSTALL_BIN_DIR/config.sh"
chmod +x "$INSTALL_BIN_DIR/autowake.sh"

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

CAFF_CALENDAR="    <dict>
        <key>Hour</key>
        <integer>${FIRST_HOUR}</integer>
        <key>Minute</key>
        <integer>${FIRST_MINUTE}</integer>
    </dict>"

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
${CAFF_CALENDAR}

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

# The ping agent loads regardless of ENABLED, because it is also what reports
# autowake's state to the monitor. When disabled it sends a heartbeat and
# exits without calling Claude.
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
echo "  Loaded: $PLIST_LABEL"

# caffeinate only makes sense when a ping is actually going to happen.
if [ "${ENABLED:-true}" = "true" ]; then
    launchctl bootstrap "gui/$(id -u)" "$CAFFEINATE_PLIST"
    echo "  Loaded: $CAFFEINATE_LABEL"
else
    echo "  Skipped: $CAFFEINATE_LABEL (ENABLED=false)"
fi

# ── pmset ────────────────────────────────────────────────────────────
# Deliberately left unmanaged, not removed. This Mac runs with system sleep
# disabled (`pmset -g` shows sleep=0), so there is nothing to wake it from
# day to day — but `wakeorpoweron` can also power the machine on from a full
# shutdown (this hardware supports it: `pmset -g cap` lists womp/powernap),
# which is worth keeping as a future recovery safety net rather than coding
# away. If that day comes, schedule it by hand:
#   sudo pmset repeat wakeorpoweron MTWRFSU HH:MM:00

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=== Sync Complete ==="
echo ""
echo "Schedule (one message to $CLAUDE_MODEL per slot):"
for t in "${PING_TIMES[@]}"; do
    echo "  $t"
done
echo ""
echo "  caffeinate keeps Mac awake for $(( CAFFEINATE_SECONDS / 60 )) min"
echo ""
echo "Logs:     $LOG_DIR"
echo "Scripts:  $INSTALL_BIN_DIR"
echo "Config:   $SCRIPT_DIR/config.sh (source — re-run ./sync.sh after edits)"
echo ""
echo "To test now:  ./autowake.sh"
echo "To remove:    ./uninstall.sh"
