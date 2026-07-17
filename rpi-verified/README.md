# rpi-verified — Research → Implement → Simplify, gated on reality

A dev workflow where "done" has to survive contact with your build and tests — not
just the agent's word for it. Inspired by the "executable world model" idea from
ARC-AGI-3 research: a step's claim is a hypothesis that must reproduce reality before
the workflow advances.

```sh
ty pipeline -d rpi-verified "add a --json flag to the export command"
```

## The steps

| # | Step | Gate | What it does |
|---|------|------|--------------|
| 1 | `research` | — | Reads the code, traces how the affected area works, saves a factual summary. No code yet. |
| 2 | `implement` | `make verify` | Implements the goal from the research, then must pass the gate. |
| 3 | `simplify` | `make verify` | Shrinks the change (dedupe, drop special cases, tighten names) **while the gate stays green**. |
| 4 | `pr` | — | Opens a pull request describing the change and how it was verified. |

## How the reality gate works

Steps 2 and 3 declare `verify: make verify`. When the step tries to complete, TaskYou
runs that command in the worktree and **only advances the workflow if it passes**
(exit 0). This fires both on the agent's `taskyou_complete` signal *and* on the
daemon's git-completion sweep — so there's no path around it. Committed-but-broken
work does not advance the DAG; the step keeps working until the build and tests are
green.

The `simplify` step is the interesting one: with tests locked in as a safety net, the
agent can aggressively cut the change down and immediately know if it broke something
— the "make it smaller while it stays correct" move.

## Setup — point the gate at your build + tests

Out of the box the gate runs **`make verify`**. Give your project that target:

```makefile
verify:
	go build ./... && go test ./...
```

…or edit the two `verify:` lines in `workflows/rpi-verified.yaml` to your own command
(`bin/rails test`, `npm test`, `pytest`, etc.). Whatever you set, the implementation
and its simplification both have to pass it before the workflow finishes.

## When to use it vs `rpi`

- **rpi** — big change, you want to review the *approach* and *plan* (human gates), no
  automated build/test gate.
- **rpi-verified** — you want the *implementation* bound to your build + tests, with a
  simplify pass. Lighter on ceremony, stronger on correctness.
