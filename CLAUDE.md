# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Claude Autowake is a macOS tool that pre-starts Claude Code's 5-hour rolling usage window by sending a minimal ping (`"hi"` to Haiku) on a schedule via launchd. This ensures the usage window resets before the user's workday begins.

## Architecture

Four shell scripts, no build system:

- **config.sh** — All user-configurable settings (ping times, model, weekday-only flag, caffeinate duration). Sourced by other scripts. Reads secrets and machine-specific paths from `~/.claude-autowake/local.env` one key at a time rather than sourcing it, so nothing in that file can execute or redefine settings.
- **autowake.sh** — The ping runner. Sends one message to Claude CLI (`claude --print --model haiku -p "hi"`). Has lockfile protection, retry logic (2 attempts, 60s gap), log pruning, and an Uptime Kuma heartbeat.
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

## Machine-Local Overrides

This repo is public. Secrets and machine-specific paths go in `~/.claude-autowake/local.env`
(`KEY=value`, one per line; see `local.env.example`), never in `config.sh`. The file lives
outside the repo on purpose, so the checkout and the installed copy in `~/.claude-autowake/bin/`
read the same one — editing it needs no `./sync.sh`. Recognised keys: `KUMA_PUSH_URL`, `CLAUDE_BIN`.

## Monitoring

`autowake.sh` reports every run to an Uptime Kuma Push monitor as a dead man's switch. Kuma
alerts when no heartbeat arrives inside the heartbeat window, which covers the ping failing,
the Mac sleeping through it, and the Mac being off.

The exit code alone is not the signal. An expired login or a rate limit still exits 0, so
`run_ping` returns 2 in that case and the heartbeat goes out as `status=down`. Reporting it as
`up` would produce a green light that lies, which is worse than having no monitor. Failure
modes that report down: ping failed both attempts, `claude` binary missing, and exit 0 whose
output matches the auth/rate-limit pattern.

With `KUMA_PUSH_URL` unset the push is skipped entirely and behaviour is unchanged.

## Runtime Artifacts

- Logs: `~/.claude-autowake/logs/ping_*.log` (auto-pruned to 30 files)
- Lockfile: `/tmp/claude-autowake.lock`
- LaunchAgents: `~/Library/LaunchAgents/com.autowake.{ping,caffeinate}.plist`

## Platform

macOS only — depends on launchd, pmset, and caffeinate.
