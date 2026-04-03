# Claude Autowake

Start your Claude Code 5-hour usage window early so it resets before you need it.

## How It Works

Claude Code's usage limit operates on a rolling 5-hour window. This tool sends a single small message to Haiku at scheduled intervals (>= 5h apart) to start each window. By 9am, you're already 3 hours into the first window — meaning it resets at 11am instead of 2pm.

Each ping is one message (`"hi"`) to the cheapest model (Haiku) — minimal token cost.

## Quick Start

```bash
# 1. Edit config.sh to set your preferred start time
vim config.sh

# 2. Install (sets up launchd + pmset wake schedule)
./install.sh

# 3. Test it manually
./autowake.sh
```

## Configuration

Edit `config.sh` to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| `FIRST_PING` | `"06:00"` | First ping of the day (24h format) |
| `PINGS_PER_DAY` | `3` | Number of pings (spaced by interval) |
| `PING_INTERVAL_MINUTES` | `300` | Minutes between pings (min 300 = 5h) |
| `CLAUDE_MODEL` | `"haiku"` | Model to ping (haiku = cheapest) |
| `PING_PROMPT` | `"hi"` | What to send (keep it tiny) |
| `WAKE_LEAD_MINUTES` | `3` | Minutes before first ping to wake Mac |
| `CAFFEINATE_SECONDS` | `43200` (12h) | How long to keep Mac awake |

### Example Schedules

With `PING_INTERVAL_MINUTES=300` (5 hours):

| `FIRST_PING` | Pings at | Window resets by |
|---|---|---|
| `"05:00"` | 5:00, 10:00, 15:00 | ~10am, ~3pm, ~8pm |
| `"06:00"` | 6:00, 11:00, 16:00 | ~11am, ~4pm, ~9pm |
| `"07:00"` | 7:00, 12:00, 17:00 | ~12pm, ~5pm, ~10pm |

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
