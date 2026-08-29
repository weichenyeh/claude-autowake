#!/usr/bin/env bash
# claude-autowake configuration
# Edit these values to customize your schedule.
#
# After editing, run ./apply.sh to apply changes.

# ── Machine-local overrides ───────────────────────────────────────────
# This repo is public, so two kinds of value must never land in it: secrets
# (the Kuma push URL) and paths that only make sense on one machine. Both
# live in a single file outside the repo, in KEY=value form, one per line:
#
#     ~/.claude-autowake/local.env
#
# It sits next to the installed copy rather than inside the repo so that the
# repo checkout and ~/.claude-autowake/bin/ read the *same* file. Keeping it
# in the repo would force sync.sh to copy the secret into bin/, leaving two
# copies to drift apart.
#
# Keys are read one at a time instead of sourcing the file. Sourcing would
# run whatever is in there as shell code and let a stray line silently
# redefine anything below; an explicit read can only ever set the keys named
# here. (Same reasoning as ~/Developer/infrastructure/ibkr/run.sh, which
# greps one key out of .env rather than sourcing a file full of broker
# credentials.)
AUTOWAKE_LOCAL_FILE="${AUTOWAKE_LOCAL_FILE:-$HOME/.claude-autowake/local.env}"

# Print the value of one key, or nothing if the file or key is absent.
# Trailing CR, surrounding whitespace and optional quotes are stripped, so a
# value pasted straight out of a web UI works whether or not it got quoted.
autowake_local() {
    [ -f "$AUTOWAKE_LOCAL_FILE" ] || return 0
    grep -E "^$1=" "$AUTOWAKE_LOCAL_FILE" 2>/dev/null \
        | tail -n 1 \
        | cut -d= -f2- \
        | tr -d '\r' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/" \
        || true
}

# Write one key, replacing any existing line for it. Used by toggle.sh and
# schedule.sh so that changing this machine's state never edits a tracked
# file — that is what used to leave the repo dirty and make the next
# `git pull` conflict.
#
# The rewrite goes through a temp file and is copied back with `cat` rather
# than `mv`, so the original file keeps its inode and its 600 permissions
# instead of inheriting mktemp's.
autowake_local_set() {
    local key="$1" value="$2" tmp
    mkdir -p "$(dirname "$AUTOWAKE_LOCAL_FILE")"
    [ -f "$AUTOWAKE_LOCAL_FILE" ] || : > "$AUTOWAKE_LOCAL_FILE"
    tmp="$(mktemp)"
    grep -vE "^${key}=" "$AUTOWAKE_LOCAL_FILE" > "$tmp" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    cat "$tmp" > "$AUTOWAKE_LOCAL_FILE"
    rm -f "$tmp"
    # Enforced on every write, not just on creation: the file holds the push
    # URL, and a copy made by hand (or by a shell redirect) lands at 644 under
    # the default umask and would otherwise stay readable by everyone.
    chmod 600 "$AUTOWAKE_LOCAL_FILE"
}

# ── Master switch ─────────────────────────────────────────────────────
# Whether autowake pings Claude.
#   true  = the daily run pings Claude
#   false = the daily run still reports in to Kuma, but never calls Claude
#
# Note that `false` does NOT unload the ping agent. The agent has to keep
# firing, because something must run in order to report; unloading it would
# make Kuma alarm 24 hours later for a state the user chose on purpose. A
# disabled autowake costs no tokens — it just curls a heartbeat and exits.
#
# This is machine state, so it lives in local.env. Change it with
# ./toggle.sh on|off, never by editing this file.
ENABLED="$(autowake_local ENABLED)"
ENABLED="${ENABLED:-true}"

# ── Schedule ──────────────────────────────────────────────────────────
# Ping times in HH:MM (24-hour). Comma-separate several: 08:00,13:00
# Must be >= 5 hours apart. sync.sh will validate this.
#
# Also machine state — set it with ./schedule.sh HH:MM. The value below is
# only the fallback for a machine that has no local.env yet.
_raw_ping_times="$(autowake_local PING_TIMES)"
if [ -n "$_raw_ping_times" ]; then
    PING_TIMES=()
    # Trim spaces around each entry so "08:00, 13:00" works as typed.
    while IFS= read -r _t; do
        _t="${_t#"${_t%%[![:space:]]*}"}"
        _t="${_t%"${_t##*[![:space:]]}"}"
        [ -n "$_t" ] && PING_TIMES+=("$_t")
    done <<< "$(printf '%s' "$_raw_ping_times" | tr ',' '\n')"
else
    PING_TIMES=("08:00")
fi
unset _raw_ping_times _t

# ── Claude CLI ────────────────────────────────────────────────────────
# Absolute path — launchd runs in a non-interactive, non-login shell whose
# PATH lacks ~/.local/bin. Using absolute path sidesteps PATH resolution.
# Override with CLAUDE_BIN= in local.env if claude lives somewhere else.
CLAUDE_BIN="$(autowake_local CLAUDE_BIN)"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

# Model to use — haiku is cheapest, just enough to start the window.
CLAUDE_MODEL="haiku"

# Messages to send — one is picked at random each ping.
# Simplified to a single "Hi" for this fork (weekday ad-hoc use handled manually).
PING_MESSAGES=(
    "Hi"
)

# Extra flags to pass to the claude CLI (e.g., "--dangerouslySkipPermissions").
CLAUDE_EXTRA_FLAGS=""

# Optional: cd into this directory before running claude.
# Leave empty to use a temp directory.
PING_WORKING_DIR=""

# ── Caffeinate ────────────────────────────────────────────────────────
# Keep Mac awake after the first ping.
# "auto" = calculated from ping times (first-to-last span + 10 min buffer).
# Or set a number of seconds manually (e.g., 43200 = 12 hours).
CAFFEINATE_SECONDS="auto"

# ── Monitoring ────────────────────────────────────────────────────────
# Uptime Kuma Push monitor URL, used as a dead man's switch: autowake reports
# every run, and Kuma shouts when no heartbeat arrives inside the window —
# which covers the ping failing, the machine sleeping through it, and the
# machine being off entirely.
#
# Secret, so it comes from local.env and never from this file. Empty means
# the push is skipped and autowake behaves exactly as before.
KUMA_PUSH_URL="$(autowake_local KUMA_PUSH_URL)"
# Kuma's UI displays the push URL with a sample query string already on it
# (?status=up&msg=OK&ping=). Pasted as-is, those would sit in front of the
# parameters added at push time, and a stale status=up could outrank the real
# one — a failure reported as success. Trim at the first '?' so either form
# of the URL works.
KUMA_PUSH_URL="${KUMA_PUSH_URL%%\?*}"

# ── Logging ───────────────────────────────────────────────────────────
LOG_DIR="$HOME/.claude-autowake/logs"

# Max log files to keep (oldest are pruned on each run).
MAX_LOG_FILES=30
