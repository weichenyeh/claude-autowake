#!/usr/bin/env bash
# claude-autowake configuration
# Edit these values to customize your schedule.
#
# After editing, run ./apply.sh to apply changes.

# ── Master switch ─────────────────────────────────────────────────────
# Whether autowake is enabled.
#   true  = launchd agents loaded, ping fires at PING_TIMES daily
#   false = launchd agents unloaded (plists retained, pmset kept — harmless)
ENABLED=true

# ── Schedule ──────────────────────────────────────────────────────────
# Ping times in HH:MM (24-hour) format.
# Must be >= 5 hours apart. sync.sh will validate this.
PING_TIMES=("05:00")

# Minutes before the first ping to wake the Mac from sleep.
WAKE_LEAD_MINUTES=3

# ── Claude CLI ────────────────────────────────────────────────────────
# Absolute path — launchd runs in a non-interactive, non-login shell whose
# PATH lacks ~/.local/bin. Using absolute path sidesteps PATH resolution.
# Update this if claude moves (e.g. when switching machines).
CLAUDE_BIN="/Users/yeweichen/.local/bin/claude"

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

# ── Logging ───────────────────────────────────────────────────────────
LOG_DIR="$HOME/.claude-autowake/logs"

# Max log files to keep (oldest are pruned on each run).
MAX_LOG_FILES=30
