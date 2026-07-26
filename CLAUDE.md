# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Claude Autowake is a macOS tool that pre-starts Claude Code's 5-hour rolling usage window by sending a minimal ping (`"hi"` to Haiku) on a schedule via launchd. This ensures the usage window resets before the user's workday begins.

## Architecture

Four shell scripts, no build system:

- **config.sh** — All user-configurable settings (ping times, model, weekday-only flag, caffeinate duration). Sourced by other scripts. Reads secrets and machine-specific paths from `~/.claude-autowake/local.env` one key at a time rather than sourcing it, so nothing in that file can execute or redefine settings.
- **autowake.sh** — The ping runner. Sends one message to Claude CLI (`claude --print --model haiku -p "hi"`). Has lockfile protection, retry logic (2 attempts, 60s gap), log pruning, and an Uptime Kuma heartbeat.
- **sync.sh** — Generates two launchd plists (`com.autowake.ping` for scheduled pings, `com.autowake.caffeinate` to keep the Mac awake), loads them via `launchctl bootstrap`, and sets a `pmset repeat wakeorpoweron` schedule. Validates that ping times are >= 5h apart. Set `AUTOWAKE_SKIP_PMSET=1` to skip the only step that needs sudo.
- **toggle.sh** — Enables or disables autowake without touching the schedule. Writes `ENABLED` into `local.env`, then brings the agents into line. Rejects an unrecognised argument instead of falling through to "enable".
- **schedule.sh** — Changes the ping times. Validates `HH:MM`, writes `PING_TIMES` into `local.env`, then re-runs sync.sh.
- **status.sh** — Read-only report: enabled state, which agents are loaded, the ping times, the pmset wake time, Kuma push config, and the last ping result. Deliberately has no `set -e`, so one unreadable section cannot truncate the rest.
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

### Disabled is a reported state, not silence

`./toggle.sh off` does **not** unload the ping agent. The agent is what reports
autowake's state each day, so unloading it would make Kuma alarm 24 hours later
about something the user chose on purpose — and a monitor that cries wolf gets
ignored, which costs more than the false alarm itself.

When disabled, the daily run sends `status=up` with `msg=disabled by user` and
exits **without calling Claude**, so a disabled autowake uses no tokens. Only
the caffeinate agent is unloaded, since keeping the Mac awake for a ping that
will not happen has no purpose.

The consequence to keep in mind: **"agent loaded" no longer implies "it will
ping"**. Those are two separate facts, which is why `status.sh` reports the
enabled state first and unmissably. The accepted trade-off is that autowake can
sit disabled indefinitely without Kuma complaining — deliberate, because the
monitor's job is defined as "is autowake alive", not "did it ping today".

## Runtime Artifacts

- Logs: `~/.claude-autowake/logs/ping_*.log` (auto-pruned to 30 files)
- Lockfile: `/tmp/claude-autowake.lock`
- LaunchAgents: `~/Library/LaunchAgents/com.autowake.{ping,caffeinate}.plist`

## Platform

macOS only — depends on launchd, pmset, and caffeinate.

## Testing a ping by hand

Use launchd, not the script directly:

```bash
launchctl kickstart -p gui/$(id -u)/com.autowake.ping
```

Running `./autowake.sh` over SSH **always fails**, and not for any reason
related to autowake. Claude's credentials live in the login Keychain, which an
SSH session cannot reach; the launchd agent runs in the GUI domain and can. The
failure looks exactly like an expired login, and — now that the heartbeat is
wired up — it also pushes a false `status=down` and sets off a real alert.

This produced one false alarm on 2026-07-26, diagnosed as "the login expired"
until a run through launchd succeeded three seconds later. The general rule it
belongs to: verify by replaying the path the thing actually takes, not by
calling a piece of it in isolation.
