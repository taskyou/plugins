# claude-profile-router

Route each task to whichever of your Claude accounts has the most rate-limit
headroom left.

If you have two logins — a personal one and a work one, say — you already have
two Claude config dirs. This plugin checks how much of each account's 5-hour and
weekly limits are spent and points every task ty spawns at the one with room. If
both are spent, it holds the task in the queue instead of burning a session on a
429.

```
$ ty plugins run claude-profile-router status
Routing threshold: skip a profile at or above 90% used

/Users/me/.claude-personal
  me@personal.example
  99% used (weekly_all, resets 2026-08-16 10:00:00)
  -> skipped by the router (at or above 90%)

/Users/me/.claude-work
  me@work.example
  12% used (weekly_all, resets 2026-08-20 21:00:00)
```

→ the next task runs under `.claude-work`.

## Requirements

- **A `ty` that emits the `task.route` hook** (TaskYou
  [#690](https://github.com/bborn/taskyou/pull/690)). Unlike the other plugins in
  this collection, this one is a *hook* plugin rather than a workflow, so it needs
  support in ty itself, not just a workflow file. On an older ty the plugin loads
  and does nothing — the event never fires. To confirm it's working, start a task
  and look for a `Routed to Claude profile …` line in its log.
- **`jq` or `python3`** on the daemon's `PATH`, to read the usage API's JSON.
  macOS has shipped `/usr/bin/jq` for a while; otherwise `brew install jq`.

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
   ty plugins run claude-profile-router status   # or just: ./status.sh
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
- Anything that goes wrong — no credentials, an expired login, no `jq`/`python3`,
  the usage API unreachable with no cached reading — means the plugin says nothing
  and the task spawns exactly as it would have without it. The one exception is
  deliberate: if *every* profile merely failed to probe, it does **not** hold your
  tasks, because that's the plugin being broken rather than the accounts being
  spent.

## Configuration

See [`config.example.env`](config.example.env). The knobs:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TY_CLAUDE_PROFILES` | *(required)* | Space-separated config dirs to route between |
| `TY_CLAUDE_MAX_PERCENT` | `90` | Skip a profile at or above this percent used |
| `TY_CLAUDE_PROJECTS` | *(all)* | Only route tasks in these projects |
| `TY_CLAUDE_JSON` | `auto` | Force a JSON backend (`jq` or `python3`) |
| `TY_CLAUDE_CACHE_TTL` | `60` | Seconds a usage reading is served before refetching |
| `TY_CLAUDE_CACHE_STALE` | `1800` | Seconds a cached reading stays usable when a live read fails |

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
- **Usage is read, never written.** `usage.sh` reads each profile's stored OAuth
  token — from the macOS Keychain, or `<config-dir>/.credentials.json` elsewhere —
  to call the same endpoint Claude Code's `/usage` uses. It never refreshes,
  rewrites, or prints a credential. A profile whose token has gone stale reports
  as unavailable until you run a `claude` session under it.
- **The keychain lookup depends on undocumented Anthropic behavior.** Claude Code
  namespaces each config dir's credentials by the SHA-256 of the *exact string*
  it was given for `CLAUDE_CONFIG_DIR` — NFC-normalized, and **not** resolved or
  tidied. `usage.sh` reproduces that, which means `~/.claude-work` and
  `~/.claude-work/` are different profiles: list yours in `TY_CLAUDE_PROFILES`
  the same way you set `CLAUDE_CONFIG_DIR` when you logged in. (A trailing slash
  that misses gets an explicit hint rather than a silent skip.) If Anthropic
  changes the scheme, profiles report "no credentials" loudly on stderr and
  routing stops — it never silently reads as "0% used".
- **[claude-swap](https://github.com/realiti4/claude-swap) is worth a look** if
  you want more than routing: it manages the accounts themselves (adding,
  refreshing dead tokens, a TUI) and is where the credential handling here was
  checked against. Once it can report a session profile's path, this plugin can
  drop `usage.sh` and just ask it.
- **Two probes per spawn**, each a single HTTPS GET, cached for a minute under
  `~/.cache/ty/claude-usage`. The endpoint rate-limits, so the cache is not
  optional; a cached reading up to 30 minutes old is used if a live read fails.
  The hook is capped at 15s by ty; if it overruns, the task spawns normally.

## Trust

This plugin reads your Claude credentials (to call the usage endpoint) and
decides which account your tasks spend. Read it before installing — it's two
short shell scripts:

- `usage.sh` — reads one profile's token and reports its used percent.
- `route.sh` — asks `usage.sh` about each profile and prints the winner.

## Files

| File | What it is |
| --- | --- |
| `route.sh` | The `task.route` hook: picks a profile, or holds the task |
| `usage.sh` | Reads one profile's rate-limit usage (`usage.sh percent\|show <dir>`) |
| `status.sh` | The `status` action: what the router currently sees |
| `config.env` | Your profiles and threshold (copy from `config.example.env`) |

`usage.sh` is usable on its own:

```bash
./usage.sh percent ~/.claude-work   # -> 12
./usage.sh show    ~/.claude-work
```
