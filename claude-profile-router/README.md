# claude-profile-router

Route each task to whichever of your Claude accounts has the most rate-limit
headroom left.

If you have two logins — a personal one and a work one, say — you already have
two Claude config dirs. This plugin checks how much of each account's 5-hour and
weekly limits are spent and points every task ty spawns at the one with room. If
both are spent, it holds the task in the queue instead of burning a session on a
429.

```
Routing threshold: skip a profile at or above 90% used

/Users/me/.claude-personal
  me@personal.example
  99% used (weekly, resets Sun 05:00) — 1% headroom

/Users/me/.claude-work
  me@work.example
  11% used (weekly, resets Thu 16:00) — 89% headroom
```

→ the next task runs under `.claude-work`.

## Requirements

A `ty` that supports the **`task.route`** hook and the **`ty usage`** command
(TaskYou [#690](https://github.com/bborn/taskyou/pull/690)). Check with:

```bash
ty usage --help    # if this errors, upgrade: ty upgrade
```

Unlike the other plugins in this collection, this one is a *hook* plugin rather
than a workflow — it needs that hook in ty itself, not just a workflow file.

## Setup

1. **Have two profiles.** A profile is a `CLAUDE_CONFIG_DIR` with its own login:

   ```bash
   CLAUDE_CONFIG_DIR=~/.claude-work claude   # then /login as the second account
   ```

2. **Install and configure:**

   ```bash
   ty plugins add https://github.com/taskyou/plugins
   cd "$(ty plugins dir)/plugins/claude-profile-router"
   cp config.example.env config.env
   $EDITOR config.env        # list your profile dirs in TY_CLAUDE_PROFILES
   ```

   (`ty plugins add` clones the collection into `<plugins dir>/plugins/`, so each
   plugin lives one level down. `ty plugins list` shows what was discovered.)

3. **Check it sees both accounts:**

   ```bash
   ty plugins run claude-profile-router status
   ```

That's it — the next task ty spawns is routed. `ty logs` and the task's own log
record which profile it landed on and why.

## How it decides

- Each profile's **binding limit** is the worst of its reported windows (5-hour
  session, weekly, per-model weekly). A session window at 98% blocks the next
  task even when the weekly one is untouched, so the worst window is the one
  that matters.
- The profile with the **lowest** binding percent wins.
- Profiles at or above `TY_CLAUDE_MAX_PERCENT` (default 90) are skipped. The
  margin exists because usage is sampled at spawn, not metered continuously —
  a long task started at 89% can still cross the line mid-run.
- If every profile is over the threshold, the task is **held**: it stays queued
  and is reconsidered on the next daemon tick, with one log line saying why.
- A task that already names a config dir (set by hand, or by a workflow step) is
  left alone. Routing fills a vacuum; it doesn't overrule you.
- **A task is routed once and stays there.** Its Claude session lives inside that
  config dir, so a resume has to happen under the same profile or it would start
  a fresh conversation. A task already running on a profile therefore waits for
  *that* profile to reset rather than hopping to the other one.
- Anything that goes wrong — no credentials, an expired login, `ty` not on the
  daemon's `PATH` — means the plugin says nothing and the task spawns exactly as
  it would have without it.

## Configuration

See [`config.example.env`](config.example.env). The knobs:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TY_CLAUDE_PROFILES` | *(required)* | Space-separated config dirs to route between |
| `TY_CLAUDE_MAX_PERCENT` | `90` | Skip a profile at or above this percent used |
| `TY_CLAUDE_PROJECTS` | *(all)* | Only route tasks in these projects |
| `TY_BIN` | `ty` | Path to the ty binary, if the daemon's `PATH` lacks it |

Anything already set in the environment overrides `config.env`, so you can try a
threshold without editing the file:

```bash
TY_CLAUDE_MAX_PERCENT=50 ./route.sh
```

## Caveats

- **A config dir is more than an account.** It also carries that profile's
  plugins, MCP servers, and trusted-worktree state. Set both profiles up the
  same way, or a task routed to the quieter one may find tools missing. If you
  want to swap only credentials, use a per-task `env:` override instead (see
  `docs/plugins.md` in the main repo).
- **Usage is read, never written.** `ty usage` reads each profile's stored OAuth
  token to call the same endpoint Claude Code's `/usage` uses. It never
  refreshes or rewrites a credential. A profile whose token has gone stale
  reports as unavailable until you run a `claude` session under it.
- **Two probes per spawn**, each a single HTTPS GET, and ty caches the result for
  a minute. The hook is capped at 15s; if it overruns, the task spawns normally.

## Trust

This plugin reads your Claude credentials (to call the usage endpoint) and
decides which account your tasks spend. Read `route.sh` before installing — it's
about 90 lines of shell and does exactly two things: shell out to `ty usage`, and
print the winning directory.
