#!/usr/bin/env bash
# claude-autowake configuration
# Edit these values to customize your schedule.

# ── Schedule ──────────────────────────────────────────────────────────
# Ping times in HH:MM (24-hour) format.
# Must be >= 5 hours apart. install.sh will validate this.
PING_TIMES=("06:00")
 
# Minutes before the first ping to wake the Mac from sleep.
WAKE_LEAD_MINUTES=3

# ── Claude CLI ────────────────────────────────────────────────────────
CLAUDE_BIN="claude"

# Model to use — haiku is cheapest, just enough to start the window.
CLAUDE_MODEL="haiku"

# Minimal prompt — we just need to start the usage window.
PING_PROMPT="hi how are you?"

# Optional: cd into this directory before running claude.
# Leave empty to use a temp directory.
PING_WORKING_DIR=""

# ── Caffeinate ────────────────────────────────────────────────────────
# Keep Mac awake for this many seconds after the first ping.
# Default: 43200 = 12 hours (covers a full workday).
CAFFEINATE_SECONDS=43200

# ── Logging ───────────────────────────────────────────────────────────
LOG_DIR="$HOME/.claude-autowake/logs"

# Max log files to keep (oldest are pruned on each run).
MAX_LOG_FILES=30
