# rpi — Research → Plan → Implement (human-gated *and* reality-gated)

Takes one free-text goal and drives it to a pull request. A **human** okays the
approach and the plan; the **machine** proves the implementation against your build
and tests. Use it when a change is big enough that you want to review the *approach*
before code — and be sure the code actually works before it advances.

```sh
ty pipeline -d rpi "add rate limiting to the public API"
```

## The phases

Each phase runs as its own step (its own agent, its own worktree) on one shared
branch. Document phases hand their output to the next through the artifact store;
nothing is committed until code is written.

| # | Phase | Gate | Reads → Produces |
|---|-------|------|------------------|
| 1 | `research-questions` | — | the raw goal → neutral questions research must answer |
| 2 | `research` | — | **only** the questions → a factual report of how the code works today |
| 3 | `design` | 🚦 human | the research → an approach with tradeoffs + a recommendation |
| 4 | `structure-outline` | — | the design → a phased, vertical-slice outline |
| 5 | `plan` | 🚦 human | the outline → a precise, diff-level plan |
| 6 | `implement` | ✅ `make verify` | the plan → code that passes your build + tests |
| 7 | `simplify` | ✅ `make verify` | shrinks the change while the tests stay green |
| 8 | `describe-pr` | — | the branch → a pull request |

## Two kinds of gate

**Human gates (🚦) at the expensive turns.** `design` and `plan` park in `blocked`
when they finish, so you review the approach and the plan before the workflow spends
effort downstream. Approve with:

```sh
ty close <task-id>      # releases the next phase
```

**Reality gates (✅) on the code.** `implement` and `simplify` declare
`verify: make verify`. When the step tries to complete, TaskYou runs that command in
the worktree and **only advances if it passes** — on the agent's `taskyou_complete`
*and* on the daemon's git-completion sweep. Committed-but-broken work does not move
the workflow forward. The `simplify` step leans on this: with tests locked in, the
agent can cut the change down and know instantly if it broke something.

## Setup — point the reality gate at your build + tests

Out of the box the gate runs **`make verify`**. Give your project that target:

```makefile
verify:
	go build ./... && go test ./...
```

…or edit the two `verify:` lines in `workflows/rpi.yaml` to your own command
(`bin/rails test`, `npm test`, `pytest`, …).

## Two ideas that make it work

**Research is blind to the goal.** Phase 2 never sees the raw goal — only the neutral
questions phase 1 produced — so the investigation reports what the code *actually
does*, not what the goal wants to be true.

**A human okays the approach; the machine proves the code.** The gates split the
judgment: taste and direction are yours (design/plan), correctness is enforced
(implement/simplify).
