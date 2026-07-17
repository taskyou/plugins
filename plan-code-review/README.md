# plan-code-review — Plan → Code → two parallel reviewers → Collect

A workflow built around **independent review**: after the change is coded, two
reviewers run *in parallel with separate context*, then a final step collects their
findings. Two agents that can't see each other's reasoning catch different classes of
issue and avoid single-context self-review bias.

```sh
ty pipeline -d plan-code-review "add optimistic locking to the orders table"
```

## The shape

```
        ┌────────────┐
Plan ─▶ │    Code    │ ─▶ Review A ┐
        └────────────┘             ├─▶ Collect
                      └─▶ Review B ┘
```

| Step | What it does |
|------|--------------|
| `Plan` | Explores the codebase and writes `PLAN.md` on the shared branch. |
| `Code` | Implements the plan. |
| `Review A` / `Review B` | Run **in parallel**, each on its own review branch, each blind to the other. |
| `Collect` | The terminal step: reads both reviews, reconciles them, and opens the PR. |

The parallel reviewers push to their *own* branches (not the shared one) so a weak
review can't clobber the other, and `Collect` is told exactly which branches to read.

## Configurable per project

Every step's model and executor is adjustable, so you can (for example) point one
reviewer at a different model or executor for a genuinely different perspective:

```sh
ty pipeline config plan-code-review --set "Review B=codex"
```

Defaults are all Claude (Plan/Review A on a stronger model, Code/Collect on a faster
one) so it runs anywhere without surprises.

## Notes

- This is the original built-in TaskYou workflow, now shipped as a plugin.
- No build/test gate — it relies on the two reviewers for quality. Pair it with, or
  swap to, **rpi-verified** if you want completion bound to your build + tests.
