# TaskYou plugins

A community collection of [TaskYou](https://github.com/taskyou) plugins — droppable
directories that add **workflows**, **hooks**, and **actions** to your `ty` install.

Install the whole collection with one command:

```sh
ty plugins add https://github.com/taskyou/plugins
ty plugins list
```

`ty plugins add` clones this repo and discovers every plugin inside it. Re-run the
same command to update them all (`git pull` under the hood).

## What's inside

| Plugin | What it gives you |
|--------|-------------------|
| **rpi** | `ty pipeline -d rpi "<goal>"` — Research → Plan → Implement, **human-gated *and* reality-gated**. Neutral research questions, goal-blind research, a design gate and a plan gate you approve, then implement + simplify — each gated on your build + tests — then a PR. A human okays the approach; the machine proves the code. |
| **plan-code-review** | `ty pipeline -d plan-code-review "<goal>"` — Plan → Code → two parallel reviewers → collect, on one shared branch. Each step's model/executor is configurable per project. |
| **claude-profile-router** | Two Claude logins? Each task goes to whichever account has the most rate-limit headroom left, and waits in the queue when both are spent. The one **hook** plugin here rather than a workflow — it answers ty's `task.route` hook just before a task spawns. Needs `jq` or `python3`. |
| **arc-solve** | `ty pipeline -d arc-solve "solve <game-id>"` — play a live [ARC-AGI-3](https://arcprize.org/arc-agi/3) game and complete a level. The gate **replays your solution against the real game**, so a win can't be faked. Needs only an ARC API key at `~/.config/arc/key`. |

## The idea: gate progress on reality

Several of these use TaskYou's **verify gate** — a `verify:` command on a workflow
step. When a step tries to complete, `ty` runs that command in the worktree and only
lets the workflow advance if it passes (exit 0), on the agent's `taskyou_complete`
signal *and* on the daemon's git-completion sweep. It's inspired by the "executable
world model" idea from ARC-AGI-3 research: a step's claim of "done" has to survive
contact with reality (your build, your tests, the actual game) — not just the agent's
word.

- `rpi-verified` gates `implement` and `simplify` on `make verify` (edit those lines
  to your own build+test command if you don't use make).
- `arc-solve` gates on a script that resets the live game and replays the solution.

## Anatomy of a plugin

A plugin is a directory with a `plugin.yaml` manifest. It may carry any of:

```
my-plugin/
  plugin.yaml            # name, version, description
  workflows/*.yaml       # ty pipeline definitions
  hooks/…  + plugin.yaml hooks:   # scripts that fire on task events
  actions/… + plugin.yaml actions: # user-invoked commands (ty plugins run)
```

Workflows are picked up by convention — any `workflows/*.yaml` in a plugin becomes a
`ty pipeline -d <name>` definition. To author your own, add a directory here (or in
your own repo) and open a PR.

Most plugins here are workflows, which work on any `ty`. A plugin that declares a
**hook** needs a `ty` new enough to emit that event — `claude-profile-router` uses
`task.route`, which fires before a task spawns. Each plugin's README states what it
needs; `ty plugins list` shows what your install actually discovered.

## Trust

Installing a plugin runs its scripts and workflow prompts with your agent's access,
and a workflow step can set `env:` / `config_dir:` that route your agent's
credentials — as can a `task.route` hook, for every task. `claude-profile-router`
additionally reads your stored Claude credentials to check each account's usage.
**Only `ty plugins add` sources you trust.** Read a plugin before you install it.
