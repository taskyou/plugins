# arc-solve — beat a level of a live ARC-AGI-3 game

An agent plays a real [ARC-AGI-3](https://arcprize.org/arc-agi/3) game and completes a
level. The catch that makes it honest: the **verify gate replays the agent's solution
against the live game**, so the workflow only advances on a win it re-checked against
reality — the agent can't self-report success.

```sh
ty pipeline -d arc-solve "solve ls20-9607627b"
```

![arc-solve completing level 1 of LS20](./solve.gif)

## Requirements

- **An ARC API key** at `~/.config/arc/key` (free — register at
  <https://three.arcprize.org>). That's the *only* thing you provide; the workflow
  installs the ARC SDK itself.
- Python 3 + network access in the agent's environment.

## How it works

| Step | Gate | What it does |
|------|------|--------------|
| `solve` | `.venv/bin/python check_solved.py` | Sets up (venv + `arc-agi` SDK), plays the game to find a level-completing move sequence, writes it to `solution.json`. |
| `report` | — | Writes a one-line `RESULT.md` (game, moves, levels completed). |

**The gate** (`check_solved.py`) reads `solution.json`, `reset`s the live game, and
replays the moves. It passes only if `levels_completed ≥ 1` (raise the bar with
`ARC_SOLVE_LEVELS`). Because the game is deterministic at seed 0, a solution replays
identically — so a pass means the moves genuinely beat a level, not that the agent
said so.

## The helper the agent plays with (`arc_client.py`)

```python
import arc_client
arc_client.play([1,2,3,4])     # reset (seed 0) + apply action ints 1-4;
                               # returns levels_completed, state, per-step trace
arc_client.grid_after([1,2])   # the 64x64 frame after those actions, to inspect
arc_client.list_games()        # (game_id, title) for the public set
```

The game id comes from the goal (e.g. `"solve ls20-9607627b"`); if you don't name one
the agent lists the public games and picks one. The key is read from
`~/.config/arc/key` (or `$ARC_API_KEY`) automatically.

## Honest scope

- Completes **one level**, not a full `WIN` (games have several levels). Raise
  `ARC_SOLVE_LEVELS` to demand more.
- The ARC SDK leaves the game's (obfuscated) source on disk, which a determined agent
  can read — so this is a **source-available** solve, weaker than solving fully blind.
- See [`example-run.md`](./example-run.md) for a full recorded run.
