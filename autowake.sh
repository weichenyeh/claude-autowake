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

# ── Main ping ─────────────────────────────────────────────────────────
run_ping() {
    log "=== Claude Autowake Ping ==="
    log "Model: $CLAUDE_MODEL"

    # Verify claude is accessible
    if ! command -v "$CLAUDE_BIN" &>/dev/null; then
        log "ERROR: '$CLAUDE_BIN' not found in PATH."
        log "PATH=$PATH"
        exit 1
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

    local start_time end_time duration
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
            duration=$(( end_time - start_time ))
            # Check for auth/API errors in successful exit codes
            if echo "$output" | grep -qiE "unauthorized|auth.*error|invalid.*key|rate.?limit|forbidden|expired"; then
                log "WARNING: Ping exited 0 but output suggests an error. Check log."
            fi
            log "=== Ping completed in ${duration}s ==="
            return 0
        else
            end_time=$(date +%s)
            duration=$(( end_time - start_time ))
            log "=== Ping failed after ${duration}s (attempt $attempt/2) ==="
        fi
    done
    log "ERROR: All ping attempts failed."
    return 1
}

# ── Entry point ───────────────────────────────────────────────────────
prune_logs
acquire_lock
run_ping
