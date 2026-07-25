# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Claude Autowake is a macOS tool that pre-starts Claude Code's 5-hour rolling usage window by sending a minimal ping (`"hi"` to Haiku) on a schedule via launchd. This ensures the usage window resets before the user's workday begins.

## Architecture

Four shell scripts, no build system:

- **config.sh** — All user-configurable settings (ping times, model, weekday-only flag, caffeinate duration). Sourced by other scripts.
- **autowake.sh** — The ping runner. Sends one message to Claude CLI (`claude --print --model haiku -p "hi"`). Has lockfile protection, retry logic (2 attempts, 60s gap), and log pruning.
- **sync.sh** — Generates two launchd plists (`com.autowake.ping` for scheduled pings, `com.autowake.caffeinate` to keep the Mac awake), loads them via `launchctl bootstrap`, and sets a `pmset repeat wakeorpoweron` schedule. Validates that ping times are >= 5h apart. Set `AUTOWAKE_SKIP_PMSET=1` to skip the only step that needs sudo.
- **toggle.sh** — Enables or disables autowake without touching the schedule. Writes `ENABLED` into config.sh, then loads or unloads the agents. Rejects an unrecognised argument instead of falling through to "enable".
- **status.sh** — Read-only report: which agents are loaded, the ping times, the pmset wake time, and the last ping result. Deliberately has no `set -e`, so one unreadable section cannot truncate the rest.
- **uninstall.sh** — Reverses install: unloads agents, removes plists, cancels pmset, optionally deletes logs.

## Key Commands

```bash
./sync.sh          # Install/re-sync launchd agents + pmset wake (sudo for pmset only)
./toggle.sh on     # Enable  (no sudo)
./toggle.sh off    # Disable (no sudo)
./status.sh        # Report loaded agents, schedule, pmset wake, last ping result
./autowake.sh      # Manual test ping
./uninstall.sh     # Remove everything
```

Only `autowake.sh` and `config.sh` get copied into `~/.claude-autowake/bin/`, which is
what launchd actually runs. `toggle.sh` / `status.sh` / `sync.sh` run from the repo. So a
`git pull` is enough for those three, but changes to `autowake.sh` need `./sync.sh` to
take effect.

## Runtime Artifacts

- Logs: `~/.claude-autowake/logs/ping_*.log` (auto-pruned to 30 files)
- Lockfile: `/tmp/claude-autowake.lock`
- LaunchAgents: `~/Library/LaunchAgents/com.autowake.{ping,caffeinate}.plist`

## Platform

macOS only — depends on launchd, pmset, and caffeinate.
