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

# ── Master switch ─────────────────────────────────────────────────────
# Whether autowake is enabled.
#   true  = launchd agents loaded, ping fires at PING_TIMES daily
#   false = launchd agents unloaded (plists retained, pmset kept — harmless)
ENABLED=true

# ── Schedule ──────────────────────────────────────────────────────────
# Ping times in HH:MM (24-hour) format.
# Must be >= 5 hours apart. sync.sh will validate this.
PING_TIMES=("07:00")

# Minutes before the first ping to wake the Mac from sleep.
WAKE_LEAD_MINUTES=3

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

# ── Logging ───────────────────────────────────────────────────────────
LOG_DIR="$HOME/.claude-autowake/logs"

# Max log files to keep (oldest are pruned on each run).
MAX_LOG_FILES=30
