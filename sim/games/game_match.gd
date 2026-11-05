class_name GameMatch
extends RefCounted
## One game or competition, step by step (docs/gdd/04f_vida_y_fiestas.md §4.26; contract: docs/contratos/juegos.md).
## The base of every game of sim/games/ (AzarMatch, MayorMatch, PulsoMatch, ...), shaped like Duel: pure, it holds its
## own `d` (JSON-friendly data; nothing is saved: a game lives only while it is played) and never reads the world.
## Deterministic: same seed, same match id, same players, same choices = same game.
##
## The played side (d.player, -1 = nobody: the AI plays every side) gives its choices with choose(); every choice it
## gives is kept in d.moves, so the sim can replay the game from the order game_play (Games.replay). auto_finish()
## lets the AI play that side from now to the end («Resolver sin jugar»): the AI of a side is the policy that plays
## well, so the automatic way and a player who follows what the screen shows get the same expected result (the
## benches in tools/games_bench.gd measure it).
##
## view(side) -> {phase, turn (whose decision: a side or -1), actions [{id, enabled, cost, why}], prompt (i18n key),
##   cue {text (i18n key), read (chance it is true)} or {}, read_by (how well the other reads this side, or 0), ...the
##   game's own data for its board}. result() -> {ok, over, game, winner (side or -1), ranking [sides, best first],
##   scores [per side], net [gold per side; a table game: what each wins or loses of the stakes, before the house],
##   how (how it ended), facts (the game's own: unhorsed, scared, caught...)}.

## Debug logs of every match (the benches and the many-match tests turn them off).
static var verbose: bool = true

var cfg: Dictionary = {}   # the whole games table (Catalog.games)
var d: Dictionary = {}


func _init_d(game_id: String, id: String, seed: int, players: Array, player: int, stake: int, opts: Dictionary) -> void:
	var ps: Array = []
	for p: Variant in players:
		ps.append((p as Dictionary).duplicate(true))
	d = {"game": game_id, "id": id, "seed": seed, "players": ps, "player": player, "stake": stake,
		"opts": opts.duplicate(true), "step": 0, "moves": [], "log": [], "over": false, "winner": -1, "how": "",
		"net": _zeros(ps.size()), "scores": _zeros(ps.size()), "ranking": [], "facts": [], "phase": "",
		"turn": -1}


static func _zeros(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(0)
	return out


func game() -> String:
	return str(d["game"])


## The figures of this game (data/games.json "<game>").
func sec() -> Dictionary:
	return cfg.get(game(), {})


func over() -> bool:
	return bool(d["over"])


func n_players() -> int:
	return (d["players"] as Array).size()


func player_of(side: int) -> Dictionary:
	return (d["players"] as Array)[side]


func plays(side: int) -> bool:
	return side == int(d["player"]) and side >= 0


func match_seed() -> int:
	return int(d["seed"])


func id() -> String:
	return str(d["id"])


func step() -> int:
	return int(d["step"])


func opt(key: String, default: Variant = null) -> Variant:
	return (d["opts"] as Dictionary).get(key, default)


## The house's share of winnings (0 in the street): opts.rake if given, else the house's when opts.house is set.
func rake() -> float:
	if (d["opts"] as Dictionary).has("rake"):
		return float(opt("rake"))
	if str(opt("house", "")) != "":
		return float((cfg.get("house", {}) as Dictionary).get("rake", 0.0))
	return 0.0


## What the side `side` sees now (the game fills it in _view).
func view(side: int) -> Dictionary:
	var v := _view(side)
	v["over"] = over()
	v["step"] = step()
	if not v.has("phase"):
		v["phase"] = str(d["phase"])
	if not v.has("turn"):
		v["turn"] = int(d["turn"])
	if not v.has("actions"):
		v["actions"] = []
	return v


## The ids of the actions the side may take now.
func allowed(side: int) -> Array:
	var out: Array = []
	for a: Dictionary in view(side)["actions"]:
		if bool(a.get("enabled", true)):
			out.append(str(a["id"]))
	return out


## The played side chooses `action` for the open decision. {ok, reason}.
func choose(side: int, action: String) -> Dictionary:
	if over():
		return {"ok": false, "reason": "game_over"}
	if not plays(side):
		return {"ok": false, "reason": "not_your_side"}
	if int(d["turn"]) != side and int(d["turn"]) != -2:
		return {"ok": false, "reason": "not_your_turn"}
	if not action in allowed(side):
		return {"ok": false, "reason": "bad_action"}
	var r := _choose(side, action)
	if bool(r.get("ok", false)):
		(d["moves"] as Array).append(action)
		if _log():
			print("[Games] %s %s: el lado %d elige %s" % [game(), id(), side, action])
		_advance()
	return r


## The AI plays the played side from now to the end («Resolver sin jugar»).
func auto_finish() -> void:
	if _log() and not over():
		print("[Games] %s %s: resolver sin jugar desde el paso %d" % [game(), id(), step()])
	d["player"] = -1
	_advance()


func moves() -> Array:
	return d["moves"]


func log_entries() -> Array:
	return d["log"]


func result() -> Dictionary:
	return {"ok": true, "over": over(), "game": game(), "winner": int(d["winner"]), "ranking": (d["ranking"] as Array).duplicate(),
		"scores": (d["scores"] as Array).duplicate(), "net": (d["net"] as Array).duplicate(), "how": str(d["how"]),
		"facts": (d["facts"] as Array).duplicate(true), "stake": int(d["stake"])}


static func _log() -> bool:
	return verbose and OS.is_debug_build()


func _finish(winner: int, how: String) -> void:
	d["over"] = true
	d["winner"] = winner
	d["how"] = how
	d["phase"] = "over"
	d["turn"] = -1
	if (d["ranking"] as Array).is_empty():
		d["ranking"] = _rank_by_scores(winner)
	if _log():
		print("[Games] %s %s: fin (%s) gana %d, puntos %s, oro %s" % [game(), id(), how, winner, d["scores"], d["net"]])


## Sides ordered by score (best first); the winner first when there is one.
func _rank_by_scores(winner: int) -> Array:
	var sides: Array = []
	for i: int in n_players():
		sides.append(i)
	var sc: Array = d["scores"]
	sides.sort_custom(func(a: int, b: int) -> bool:
		if a == winner:
			return true
		if b == winner:
			return false
		if float(sc[a]) != float(sc[b]):
			return float(sc[a]) > float(sc[b])
		return a < b)
	return sides


## What the AI would choose for `side` in the open decision (the policy of «Resolver sin jugar»): the bots, the smoke
## and the benches play «well» with it. "" when that side has nothing to decide.
func ai_move(side: int) -> String:
	if over() or int(d["turn"]) != side:
		return ""
	return _ai_move(side)


# --- What every game fills in ----------------------------------------------------------------------------------------

func _ai_move(_side: int) -> String:
	return ""


func _view(_side: int) -> Dictionary:
	return {}


## Applies a valid choice of the played side (the base already checked it is allowed). {ok, reason}.
func _choose(_side: int, _action: String) -> Dictionary:
	return {"ok": true, "reason": ""}


## Plays what the AI decides and what the dice say until a decision of the played side is open or the game is over.
func _advance() -> void:
	pass
