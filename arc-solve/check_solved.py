"""VERIFY GATE: replay solution.json against the LIVE game; pass only if enough levels
are completed (default 1; override with $ARC_SOLVE_LEVELS)."""
import json, sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import arc_client
target = int(os.environ.get("ARC_SOLVE_LEVELS", "1"))
try:
    sol = json.load(open(os.path.join(HERE, "solution.json")))
    actions = sol.get("actions") if isinstance(sol, dict) else sol
    assert actions, "solution.json has no actions"
except Exception as e:
    print("Invalid solution.json:", e); sys.exit(1)
game = sol.get("game") if isinstance(sol, dict) else None
res = arc_client.play(actions, game=game)
print(f"[{res['game']}] replayed {res['n_actions']} actions LIVE -> state={res['final_state']}, "
      f"levels_completed={res['levels_completed']}/{res['win_levels']} (need {target})")
sys.exit(0 if res["levels_completed"] >= target else 1)
