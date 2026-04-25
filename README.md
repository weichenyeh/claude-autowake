# Claude Autowake

Start your Claude Code 5-hour usage window early so it resets before you need it.

## How It Works

Claude Code's usage limit operates on a rolling 5-hour window. This tool sends a single small message to Haiku at scheduled times (>= 5h apart) to start each window. By 9am, you're already 3 hours into the first window — meaning it resets at 11am instead of 2pm.

Each ping is one message (`"hi"`) to the cheapest model (Haiku) — minimal token cost.

## Quick Start

```bash
# 1. Edit config.sh to set your preferred schedule
vim config.sh

# 2. Sync system to config (sets up launchd + pmset wake schedule)
./sync.sh

# 3. Test it manually
./autowake.sh

# 4. Check status
./status.sh
```

**Daily on/off** (no sudo): edit `ENABLED` in `config.sh`, run `./toggle.sh`.
**Schedule change** (re-prompts sudo for pmset): edit `PING_TIMES` etc., re-run `./sync.sh`.

## Configuration

Edit `config.sh` to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| `PING_TIMES` | `("06:00")` | Array of ping times in HH:MM 24h format. Must be >= 5h apart. |
| `WAKE_LEAD_MINUTES` | `3` | Minutes before first ping to wake Mac from sleep |
| `ENABLED` | `true` | Master switch. `false` unloads agents (plists kept on disk). |
| `CLAUDE_MODEL` | `"haiku"` | Model to ping (haiku = cheapest) |
| `PING_PROMPT` | `"hi"` | What to send (keep it tiny) |
| `CAFFEINATE_SECONDS` | `"auto"` | `"auto"` = span of ping times + 10 min buffer. Or set a number of seconds manually. |
| `PING_WORKING_DIR` | `""` | Directory to cd into before running claude (temp dir if empty) |
| `CLAUDE_EXTRA_FLAGS` | `""` | Extra flags for the claude CLI (e.g., `"--dangerouslySkipPermissions"`) |
| `MAX_LOG_FILES` | `30` | Max log files to keep |

### Example Schedules

With pings 5 hours apart:

| `PING_TIMES` | Window resets by |
|---|---|
| `("05:00" "10:00" "15:00")` | ~10am, ~3pm, ~8pm |
| `("06:00" "11:00" "16:00")` | ~11am, ~4pm, ~9pm |
| `("06:00")` | ~11am |

## Requirements

- macOS (uses launchd, pmset, caffeinate)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Mac plugged into power (required for pmset wake from sleep)

## Logs

Stored in `~/.claude-autowake/logs/`. Auto-pruned to last 30 files.

```bash
# View latest log
ls -t ~/.claude-autowake/logs/ping_*.log | head -1 | xargs cat

# Check launchd status
launchctl list | grep autowake

# Check wake schedule
pmset -g sched
```

## Uninstall

```bash
./uninstall.sh
```


## Extra
#Check total usage, and see if the haiku model is sending properly.
```bash
npx ccusage@latest
```
