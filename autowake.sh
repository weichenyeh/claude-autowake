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
        local to_delete=$(( count - MAX_LOG_FILES ))
        find "$LOG_DIR" -name 'ping_*.log' -type f -print0 \
            | sort -z \
            | head -z -n "$to_delete" \
            | xargs -0 rm -f
        log "Pruned $to_delete old log file(s)"
    fi
}

# ── Lockfile (prevent overlapping runs) ───────────────────────────────
LOCK_FILE="/tmp/claude-autowake.lock"

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log "ERROR: Another ping is already running (PID $lock_pid). Exiting."
            exit 1
        else
            log "WARN: Stale lockfile found (PID $lock_pid not running). Removing."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
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
        trap 'rm -rf "$WORK_DIR"; rm -f "$LOCK_FILE"' EXIT
    fi

    log "Working directory: $WORK_DIR"
    log "Sending ping to Claude ($CLAUDE_MODEL)..."

    local start_time end_time duration
    start_time=$(date +%s)

    # Single message to haiku — just enough to start the usage window
    if (cd "$WORK_DIR" && "$CLAUDE_BIN" --print --model "$CLAUDE_MODEL" -p "$PING_PROMPT") \
        >> "$LOG_FILE" 2>&1; then
        end_time=$(date +%s)
        duration=$(( end_time - start_time ))
        log "=== Ping completed in ${duration}s ==="
    else
        end_time=$(date +%s)
        duration=$(( end_time - start_time ))
        log "=== Ping failed after ${duration}s (exit code: $?) ==="
    fi
}

# ── Entry point ───────────────────────────────────────────────────────
prune_logs
acquire_lock
run_ping
