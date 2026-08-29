#!/usr/bin/env bash
set -euo pipefail

# ── Resolve script directory and load config ──────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ── Logging setup ─────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG_FILE="$LOG_DIR/ping_${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ── Prune old logs ────────────────────────────────────────────────────
prune_logs() {
    local count
    count=$(find "$LOG_DIR" -name 'ping_*.log' -type f | wc -l | tr -d ' ')
    if (( count > MAX_LOG_FILES )); then
        # ls -1t sorts newest-first; tail grabs the oldest excess files
        local pruned=0
        for f in $(ls -1t "$LOG_DIR"/ping_*.log | tail -n +$(( MAX_LOG_FILES + 1 ))); do
            rm -f "$f"
            pruned=$(( pruned + 1 ))
        done
        log "Pruned $pruned old log file(s)"
    fi
}

# ── Cleanup ───────────────────────────────────────────────────────────
LOCK_DIR="/tmp/claude-autowake.lock"
_TEMP_DIR=""

cleanup() {
    [ -n "$_TEMP_DIR" ] && rm -rf "$_TEMP_DIR"
    rm -rf "$LOCK_DIR"
}
trap cleanup EXIT

# ── Lockfile (prevent overlapping runs) ───────────────────────────────
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        return
    fi

    # Lock dir exists — check if the holder is still alive
    local lock_pid
    lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        log "ERROR: Another ping is already running (PID $lock_pid). Exiting."
        exit 1
    fi

    # Stale lock — reclaim it
    log "WARN: Stale lock found (PID $lock_pid not running). Reclaiming."
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo $$ > "$LOCK_DIR/pid"
}

# ── Kuma heartbeat ────────────────────────────────────────────────────
# Report the run to the Uptime Kuma Push monitor. Kuma's half of the deal is
# to shout when no heartbeat lands inside the window; ours is to tell it the
# truth about which kind of heartbeat this was.
#
# The URL is a secret and is never logged — only the status and message are.
# A failed push is left to the monitor itself: if curl cannot reach Kuma, no
# heartbeat arrives, the window expires, and the alert fires anyway.
PING_DURATION=0
PING_FAIL_REASON=""

kuma_push() {
    local status="$1" msg="$2"
    [ -n "${KUMA_PUSH_URL:-}" ] || return 0

    # --get + --data-urlencode builds the query string with proper escaping,
    # so a message containing spaces or & cannot corrupt the request.
    if curl -fsS -m 10 --get \
        --data-urlencode "status=$status" \
        --data-urlencode "msg=$msg" \
        --data-urlencode "ping=$PING_DURATION" \
        "$KUMA_PUSH_URL" >/dev/null 2>&1; then
        log "Kuma heartbeat sent (status=$status)."
    else
        log "WARNING: Kuma heartbeat failed to send (status=$status)."
    fi
}

# ── Main ping ─────────────────────────────────────────────────────────
run_ping() {
    # Pick a random message from the configured list
    PING_PROMPT="${PING_MESSAGES[$((RANDOM % ${#PING_MESSAGES[@]}))]}"

    log "=== Claude Autowake Ping ==="
    log "Model: $CLAUDE_MODEL"
    log "Message: $PING_PROMPT"

    # Verify claude is accessible. This returns rather than exits so the
    # caller still gets to report the failure to Kuma — a missing binary is
    # exactly the kind of silent breakage the monitor exists to catch.
    if ! command -v "$CLAUDE_BIN" &>/dev/null; then
        log "ERROR: '$CLAUDE_BIN' not found in PATH."
        log "PATH=$PATH"
        PING_FAIL_REASON="claude binary not found"
        return 1
    fi

    # Set working directory
    if [ -n "${PING_WORKING_DIR:-}" ] && [ -d "$PING_WORKING_DIR" ]; then
        WORK_DIR="$PING_WORKING_DIR"
    else
        WORK_DIR="$(mktemp -d)"
        _TEMP_DIR="$WORK_DIR"
    fi

    log "Working directory: $WORK_DIR"
    log "Sending ping to Claude ($CLAUDE_MODEL)..."

    local start_time end_time
    start_time=$(date +%s)

    # Single message to haiku — just enough to start the usage window
    local attempt
    for attempt in 1 2; do
        if (( attempt == 2 )); then
            log "Retrying in 60 seconds..."
            sleep 60
            start_time=$(date +%s)
        fi

        # shellcheck disable=SC2086
        local output
        if output=$(cd "$WORK_DIR" && "$CLAUDE_BIN" --print --model "$CLAUDE_MODEL" $CLAUDE_EXTRA_FLAGS -p "$PING_PROMPT" 2>&1); then
            echo "$output" | tee -a "$LOG_FILE"
            end_time=$(date +%s)
            PING_DURATION=$(( end_time - start_time ))
            # An auth failure or a rate limit still exits 0, so exit code alone
            # cannot tell success from failure here. Treating that as "up"
            # would leave Kuma showing a green light that lies, which is worse
            # than having no monitor at all — so it returns a distinct failure.
            # No retry: neither expired credentials nor a rate limit resolves
            # in 60 seconds.
            # "not logged in" was added after a real expiry on 2026-07-26. It
            # exited non-zero that time so the failure path caught it anyway,
            # but the same message arriving with exit 0 would otherwise read
            # as success.
            if echo "$output" | grep -qiE "unauthorized|auth.*error|invalid.*key|rate.?limit|forbidden|expired|not logged in"; then
                log "ERROR: Ping exited 0 but output suggests an error. Check log."
                PING_FAIL_REASON="exit 0 but output matched an auth/rate-limit pattern"
                return 2
            fi
            log "=== Ping completed in ${PING_DURATION}s ==="
            return 0
        else
            end_time=$(date +%s)
            PING_DURATION=$(( end_time - start_time ))
            # Log the output on failure too. It used to be discarded, which
            # left the log saying only "it failed" — useless in the one
            # situation the log exists for, namely answering "Kuma says down,
            # why?". An expired login looked identical to a network outage.
            echo "$output" | tee -a "$LOG_FILE"
            log "=== Ping failed after ${PING_DURATION}s (attempt $attempt/2) ==="
        fi
    done
    log "ERROR: All ping attempts failed."
    # Carry the first line of the error into the heartbeat, so the phone
    # notification says "Not logged in" rather than a generic failure and the
    # cause is known before opening a terminal. Trimmed hard: this ends up in
    # a URL and a push message.
    local first_line
    first_line="$(printf '%s' "$output" | head -1 | cut -c1-120)"
    PING_FAIL_REASON="all $attempt attempts failed: $first_line"
    # OAuth expiry is the one failure mode that never resolves on its own —
    # unlike a rate limit or a network blip, it needs a human to click
    # through a browser login. Naming the fix in the notification itself
    # saves the SSH-and-read-logs round trip that diagnosing this by hand
    # otherwise takes (see 2026-08-29 incident).
    if printf '%s' "$first_line" | grep -qiE "oauth|not logged in|unauthorized"; then
        PING_FAIL_REASON="$PING_FAIL_REASON -> fix: claude login"
    fi

    # A manual run over SSH fails for a reason that has nothing to do with
    # autowake: Claude's credentials live in the login Keychain, which an SSH
    # session cannot reach, while the launchd agent runs in the GUI domain and
    # can. Saying so keeps a self-inflicted failure from reading as an outage —
    # this exact confusion produced a false alarm on 2026-07-26.
    if [ -n "${SSH_CONNECTION:-}" ]; then
        log "NOTE: this ran over SSH, which has no Keychain access. That alone can"
        log "      cause the failure above. To test the way launchd actually runs it:"
        log "        launchctl kickstart -p gui/\$(id -u)/com.autowake.ping"
        PING_FAIL_REASON="$PING_FAIL_REASON [ran over SSH, may be a Keychain artifact]"
    fi
    return 1
}

# ── Entry point ───────────────────────────────────────────────────────
prune_logs

# Disabled is a reported state, not silence. The monitor answers "is autowake
# alive", not "did it ping today", so a run the user switched off still checks
# in as up. Staying quiet instead would make Kuma alarm a day later about
# something deliberate, and a monitor that cries wolf gets ignored.
#
# Claude is never called on this path, so being disabled costs no tokens.
if [ "${ENABLED:-true}" != "true" ]; then
    log "Autowake is disabled (ENABLED=false in local.env) — Claude not called."
    kuma_push up "disabled by user"
    exit 0
fi

acquire_lock

# run_ping is called as an `if` condition so `set -e` does not abort before
# the failure has been reported. Its exit code is preserved for launchd.
if run_ping; then
    kuma_push up "ping ok"
else
    rc=$?
    kuma_push down "${PING_FAIL_REASON:-ping failed}"
    exit "$rc"
fi
