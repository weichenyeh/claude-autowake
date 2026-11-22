#!/usr/bin/env bash
# status.sh — report what autowake is currently doing. Read-only.
#
# No `set -e` here, on purpose: a status script must keep printing even when one
# section cannot be read. Aborting halfway is worse than one missing line,
# because a truncated report still looks like a complete one. Each section below
# guards itself instead.
set -uo pipefail

PLIST_LABEL="com.autowake.ping"
CAFFEINATE_LABEL="com.autowake.caffeinate"
LOG_DIR="$HOME/.claude-autowake/logs"

# ── Machine-readable form ─────────────────────────────────────────────
# `./status.sh --json` prints the same state as one JSON object, for tools
# that copy it elsewhere (the owner's notes regenerate their status table from
# it). Fields may be added but are never renamed, so a reader written against
# today's output keeps working. The Kuma URL is a secret and stays out, as in
# the human report.
#
# "outcome" is read from the result line autowake.sh writes, so it is one of
# ok / failed / disabled / unknown — a run cut off before its result line
# shows as unknown rather than being guessed at.
if [ "${1:-}" = "--json" ]; then
    PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist" \
    LOCAL_FILE="$HOME/.claude-autowake/local.env" LOG_DIR="$LOG_DIR" \
    LOADED="$(launchctl list "$PLIST_LABEL" &>/dev/null && echo 1 || echo 0)" \
    exec /usr/bin/python3 - <<'PY'
import json, os, plistlib, re
from pathlib import Path

env = {}
local = Path(os.environ["LOCAL_FILE"])
if local.exists():
    for line in local.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip("'\"")

times = []
plist = Path(os.environ["PLIST_PATH"])
if plist.exists():
    sched = plistlib.loads(plist.read_bytes()).get("StartCalendarInterval", [])
    for item in sched if isinstance(sched, list) else [sched]:
        times.append("%02d:%02d" % (item["Hour"], item["Minute"]))

last = None
logs = sorted(Path(os.environ["LOG_DIR"]).glob("ping_*.log"))
if logs:
    lines = logs[-1].read_text(errors="replace").splitlines()
    stamp = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] ")
    first = next((m.group(1) for l in lines if (m := stamp.match(l))), None)
    text = "\n".join(lines)
    reason = next((l for l in lines if l and not stamp.match(l)), "")
    if "Autowake is disabled" in text:
        outcome, detail = "disabled", "disabled by user"
    elif "Ping completed" in text:
        outcome, detail = "ok", ""
    elif "All ping attempts failed" in text:
        outcome, detail = "failed", reason
    else:
        outcome, detail = "unknown", ""
    kuma = re.findall(r"Kuma heartbeat sent \(status=(\w+)\)", text)
    last = {"time": first.replace(" ", "T") if first else None, "outcome": outcome,
            "detail": detail, "kuma_delivery": kuma[-1] if kuma else None,
            "log": str(logs[-1])}

print(json.dumps({
    "service": "claude",
    "enabled": env.get("ENABLED", "true") == "true",
    "loaded": os.environ["LOADED"] == "1",
    "daily_times": times,
    "kuma_configured": bool(env.get("KUMA_PUSH_URL")),
    "last_run": last,
}, ensure_ascii=False))
PY
fi

echo "=== Claude Autowake Status ==="
echo ""

# ── Enabled state ─────────────────────────────────────────────────────
# This has to come first and be unmissable. Since `off` deliberately leaves
# the ping agent loaded so it can keep reporting to Kuma, "agent: loaded" no
# longer means "it will ping Claude" — those are now two separate facts, and
# reading the agent line alone would be misleading.
LOCAL_FILE="$HOME/.claude-autowake/local.env"
ENABLED_VALUE="$(grep -E '^ENABLED=' "$LOCAL_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]')"
ENABLED_VALUE="${ENABLED_VALUE:-true}"

if [ "$ENABLED_VALUE" = "true" ]; then
    echo "Enabled:  YES — pings Claude on schedule"
else
    echo "Enabled:  NO — disabled, no tokens used"
    echo "          (agent stays loaded to report 'disabled' to Kuma daily)"
    echo "          Re-enable with: ./toggle.sh on"
fi

# ── launchd agents ────────────────────────────────────────────────────
echo ""
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
    # PlistBuddy prints "Hour = H" then "Minute = M" for each scheduled time.
    # awk pairs them by remembering the last Hour and printing when Minute
    # arrives; $NF is the value whatever the indentation. The previous version
    # used `read -r h_line m_line`, which split "Hour = 7" on whitespace and
    # left h_line as the bare word "Hour" — the digit grep then found nothing,
    # returned 1, and killed the whole script under `set -e`.
    TIMES=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval" "$PLIST_PATH" 2>/dev/null \
        | awk '/Hour/ { h = $NF } /Minute/ { printf "  %02d:%02d\n", h, $NF }')
    if [ -n "$TIMES" ]; then
        echo "$TIMES"
    else
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

# ── Kuma heartbeat ────────────────────────────────────────────────────
# Reports only whether a push URL is configured. The URL itself is a secret
# and is deliberately never printed — status.sh output gets pasted around.
echo ""
echo "Kuma push:"
if [ -f "$LOCAL_FILE" ] && grep -qE '^KUMA_PUSH_URL=.+' "$LOCAL_FILE" 2>/dev/null; then
    echo "  configured ($LOCAL_FILE)"
    LAST_BEAT=$(ls -1t "$LOG_DIR"/ping_*.log 2>/dev/null | head -1)
    if [ -n "$LAST_BEAT" ]; then
        grep -E 'Kuma heartbeat' "$LAST_BEAT" 2>/dev/null | sed 's/^/  /' \
            || echo "  (last run logged no heartbeat)"
    fi
else
    echo "  not configured — no dead man's switch on this machine"
fi

# ── Last run result ──────────────────────────────────────────────────
# "run", not "ping": a disabled run reports to Kuma without pinging Claude,
# so labelling every run a ping would describe some of them wrongly.
echo ""
echo "Last run:"
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

# ── What you can do next ──────────────────────────────────────────────
# Printed here rather than only behind --help, because this report is the
# thing actually run often enough to be remembered, and a flag you have to
# remember to ask for is no help months later.
#
# Both forms are listed on purpose. The wrapper runs from the MacBook while
# the scripts run here, so neither form is correct in both places — and
# showing the pair also documents which wrapper command maps to which script.
echo ""
echo "Commands:"
echo "  From MacBook     autowake                   overview of all services"
echo "                   autowake claude            this report"
echo "                   autowake claude time       show ping times"
echo "                   autowake claude time HH:MM change ping time"
echo "                   autowake claude on | off   off uses no tokens, still reports"
echo "  On this machine  ./schedule.sh HH:MM     change ping time"
echo "                   ./toggle.sh on | off    enable / disable"
echo "                   launchctl kickstart -p gui/\$(id -u)/com.autowake.ping"
echo "                                           run one ping the way launchd does"
echo "                                           (./autowake.sh over SSH gives a FALSE failure —"
echo "                                            no Keychain access, sends a false down to Kuma)"
echo "                   ./sync.sh               reinstall after editing config.sh"
echo "                   ./set-push-url.sh       store the Kuma push URL (hidden input)"
echo "  Secrets/paths    \$EDITOR $LOCAL_FILE"
