# rpi — Research → Plan → Implement

A phased, **human-gated** workflow that takes one free-text goal and drives it from
understanding to a pull request. Use it when a change is big enough that you want to
review the *approach* and the *plan* before any code is written.

```sh
ty pipeline -d rpi "add rate limiting to the public API"
```

## The phases

Each phase runs as its own step (its own agent, its own worktree) on one shared
branch. Document phases hand their output to the next phase through TaskYou's
artifact store — nothing is committed to git until code is written.

| # | Phase | Reads | Produces |
|---|-------|-------|----------|
| 1 | `research-questions` | the raw goal | a neutral list of questions the research must answer |
| 2 | `research` | **only** the questions (not the goal) | a factual report of how the code works today |
| 3 | `design` 🚦 | the research | an approach with tradeoffs and a recommendation |
| 4 | `structure-outline` | the design | a phased, vertical-slice outline |
| 5 | `plan` 🚦 | the outline | a precise, diff-level plan with success criteria |
| 6 | `implement` | the plan | code, committed on the shared branch |
| 7 | `describe-pr` | the branch | a pull request |

## Two ideas that make it work

**Research is blind to the goal.** Phase 2 never sees the raw goal — it works only
from the neutral questions phase 1 produced, so the investigation reports what the
code *actually does* rather than what the goal wants to be true.

**Human gates (🚦) at the expensive turns.** The `design` and `plan` steps park in
`blocked` when they finish, so you can review the approach and the plan before the
workflow spends effort downstream. Approve a parked gate with the normal close verb:

```sh
ty close <task-id>      # releases the next phase
```

To revise instead of approve, edit that phase's artifact / re-run the step before
closing.

## Notes

- No build/test gate here — `rpi` is about getting the *plan* right with human
  review. If you want the implementation gated on your build + tests too, use
  **rpi-verified**.
- The whole flow advances on its own between gates; it only pauses at a gate or if a
  step calls `taskyou_needs_input`.
