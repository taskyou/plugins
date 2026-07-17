"""Live ARC-AGI-3 client. Needs only an API key at ~/.config/arc/key (or $ARC_API_KEY).
Game id: $ARC_GAME, else a `game.txt` file, else the first public game. Deterministic
at seed=0, so a solution replays identically. Run with a venv that has `arc-agi`."""
import os, json, sys
import arc_agi
from arcengine.enums import GameAction
def _key():
    p = os.path.expanduser("~/.config/arc/key")
    return open(p).read().strip() if os.path.exists(p) else os.environ.get("ARC_API_KEY", "")
def _arc(): return arc_agi.Arcade(arc_api_key=_key())
def _A(n): return getattr(GameAction, f"ACTION{int(n)}")
def list_games(): return [(e.game_id, e.title) for e in _arc().get_environments()]
def _game(explicit=None):
    if explicit: return explicit
    g = os.environ.get("ARC_GAME", "").strip()
    if g: return g
    if os.path.exists("game.txt"):
        t = open("game.txt").read().strip()
        if t: return t
    return _arc().get_environments()[0].game_id
def play(actions, game=None, seed=0):
    game = _game(game)
    arc = _arc(); sc = arc.open_scorecard(tags=["solve"]); env = arc.make(game, seed=seed, scorecard_id=sc)
    f = env.reset(); trace = [(f.levels_completed, str(f.state).split('.')[-1], list(f.available_actions))]
    for a in actions:
        f = env.step(_A(a)); trace.append((f.levels_completed, str(f.state).split('.')[-1], list(f.available_actions)))
        if str(f.state) in ("GameState.WIN", "GameState.GAME_OVER"): break
    arc.close_scorecard(sc)
    return {"game": game, "final_state": str(f.state).split('.')[-1], "levels_completed": f.levels_completed,
            "win_levels": f.win_levels, "n_actions": len(actions), "trace": trace}
def grid_after(actions, game=None, seed=0):
    game = _game(game)
    arc = _arc(); sc = arc.open_scorecard(tags=["explore"]); env = arc.make(game, seed=seed, scorecard_id=sc)
    f = env.reset()
    for a in actions:
        f = env.step(_A(a))
        if str(f.state) in ("GameState.WIN", "GameState.GAME_OVER"): break
    g = [[int(c) for c in row] for row in f.frame[0]]; arc.close_scorecard(sc)
    return g, str(f.state).split('.')[-1], f.levels_completed
if __name__ == "__main__":
    if sys.argv[1:2] == ["games"]:
        for gid, t in list_games(): print(gid, t)
    else:
        print(json.dumps(play([int(x) for x in sys.argv[1:]]), default=list))
