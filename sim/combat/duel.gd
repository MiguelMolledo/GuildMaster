class_name Duel
extends RefCounted
## One duel «a tres tiempos», lance by lance (docs/gdd/04e_combate.md §2-§4; rules: CombatRules; figures:
## data/combat.json). Pure: it holds its own `d` (JSON-friendly data, ready to live in WorldState when the owner
## approves the design; nothing is saved today) and never reads the world. Deterministic: same seed, same fighters, same
## choices = same duel. The choices of a played side come in through choose() (in the sim they will be the order
## `duel_move`, Orders.apply); the AI's come from CombatRules.ai_choice with the duel's keyed rolls.
##
## A lance: the leader (CombatRules.leader_of) chooses first; if the AI leads, its action is drawn at once and the player
## (reader) sees `cue` with `read` (the chance it is true); if the player leads, the AI reads the player's action when
## it comes in. Blind lances: both choose without a cue. When both have chosen, the lance resolves and the next opens.
## auto_finish() lets the AI play the player's side to the end («Resolver sin jugar»): a side the AI plays gets
## exactly the choices of the AI policy, so the automatic way and a player following that policy are the same duel.

## Debug logs of every duel (the benches and the many-duel tests turn them off).
static var verbose: bool = true

var cfg: Dictionary = {}
var d: Dictionary = {}


## A new duel. a: the challenger, b: the challenged (CombatRules.fighter). player: the side the player plays (-1: none,
## the AI plays both: a duel between NPCs). kind: a data/combat.json "kinds" id (a locked kind is refused: ok false).
static func create(combat: Dictionary, id: String, seed: int, a: Dictionary, b: Dictionary, kind: String,
		player: int = -1) -> Duel:
	var du := Duel.new()
	du.cfg = combat
	var k: Dictionary = (combat.get("kinds", {}) as Dictionary).get(kind, {})
	du.d = {"id": id, "seed": seed, "kind": kind, "fighters": [a.duplicate(), b.duplicate()], "player": player,
		"breath": [CombatRules.breath_max(combat, a), CombatRules.breath_max(combat, b)], "touches": [0, 0],
		"lance": 0, "history": [[], []], "log": [], "over": false, "winner": -1, "end": "", "yielded": -1,
		"ok": not k.is_empty() and not bool(k.get("locked", false)), "pending": {}}
	if not bool(du.d["ok"]):
		du.d["over"] = true
		du.d["end"] = "locked" if not k.is_empty() else "unknown_kind"
	if _log():
		print("[Duel] %s: %s (%s) contra %s (%s), tipo %s, jugador %d, aliento %s%s" % [id, a.get("id", "?"),
			a.get("weapon"), b.get("id", "?"), b.get("weapon"), kind, player, du.d["breath"],
			"" if bool(du.d["ok"]) else " RECHAZADO: " + str(du.d["end"])])
	if bool(du.d["ok"]):
		du._open()
	return du


static func _log() -> bool:
	return verbose and OS.is_debug_build()


## A Duel over data that already exists (a duel kept in the state: state.duels.open[id].duel). The Duel works on that
## same dictionary, so the state changes with it.
static func wrap(combat: Dictionary, data: Dictionary) -> Duel:
	var du := Duel.new()
	du.cfg = combat
	du.d = data
	return du


## The figures of the kind of this duel.
func kind() -> Dictionary:
	return (cfg.get("kinds", {}) as Dictionary).get(str(d["kind"]), {})


func over() -> bool:
	return bool(d["over"])


func fighter(side: int) -> Dictionary:
	return (d["fighters"] as Array)[side]


func breath(side: int) -> int:
	return int((d["breath"] as Array)[side])


func touches(side: int) -> int:
	return int((d["touches"] as Array)[side])


## What the side `side` sees of the open lance: {lance (0-based), leader (-1 blind, 0, 1), role (blind | lead | read),
## cue (the gesture it sees when reading, else ""), read (the chance that cue is true), read_by (when leading: the
## chance the other reads it), allowed (actions it may take), chosen (its action if already given), can_yield}.
func view(side: int) -> Dictionary:
	var p: Dictionary = d["pending"]
	var leader := int(p.get("leader", CombatRules.BLIND))
	var role := "blind" if leader == CombatRules.BLIND else ("lead" if leader == side else "read")
	var other := 1 - side
	var out := {"lance": int(d["lance"]), "leader": leader, "role": role, "cue": "", "read": 0.0, "read_by": 0.0,
		"allowed": CombatRules.allowed(cfg, breath(side)), "chosen": str((p.get("choice", ["", ""]) as Array)[side]),
		"can_yield": bool(kind().get("can_yield", false)) and not over()}
	if role == "read":
		out["read"] = CombatRules.read_chance(cfg, fighter(side), fighter(other))
		out["cue"] = str(p.get("cue", ""))
	elif role == "lead":
		out["read_by"] = CombatRules.read_chance(cfg, fighter(other), fighter(side))
	return out


## A played side chooses its action for the open lance, or "yield" (if the kind allows it). {ok, reason}.
func choose(side: int, action: String) -> Dictionary:
	if over():
		return {"ok": false, "reason": "duel_over"}
	if side != int(d["player"]):
		return {"ok": false, "reason": "not_your_side"}
	var p: Dictionary = d["pending"]
	var choice: Array = p["choice"]
	if str(choice[side]) != "":
		return {"ok": false, "reason": "already_chosen"}
	if action == "yield":
		if not bool(kind().get("can_yield", false)):
			return {"ok": false, "reason": "cannot_yield"}
		_finish(1 - side, "yield", side)
		return {"ok": true, "reason": ""}
	if not action in CombatRules.ACTIONS:
		return {"ok": false, "reason": "bad_action"}
	if not CombatRules.can_afford(cfg, breath(side), action):
		return {"ok": false, "reason": "no_breath"}
	choice[side] = action
	_advance()
	return {"ok": true, "reason": ""}


## The AI plays the player's side from now to the end («Resolver sin jugar»).
func auto_finish() -> void:
	if _log() and not over():
		print("[Duel] %s: resolver sin jugar desde el lance %d" % [d["id"], int(d["lance"]) + 1])
	d["player"] = -1
	_advance()


## The whole duel between two AI fighters (NPCs, or «Resolver sin jugar» from the start): its result().
static func auto(combat: Dictionary, id: String, seed: int, a: Dictionary, b: Dictionary, kind: String) -> Dictionary:
	var du := create(combat, id, seed, a, b, kind, -1)
	return du.result()


## {ok, over, winner (-1 = draw), loser, end (touches | lances | yield | locked), touches [a, b], lances (played),
## yielded (side or -1), wound (the loser is wounded: the kind says so and it did not yield)}.
func result() -> Dictionary:
	var w := int(d["winner"])
	return {"ok": bool(d["ok"]), "over": over(), "winner": w, "loser": (1 - w) if w >= 0 else -1, "end": d["end"],
		"touches": (d["touches"] as Array).duplicate(), "lances": (d["log"] as Array).size(), "yielded": d["yielded"],
		"wound": w >= 0 and bool(kind().get("wound", false)) and int(d["yielded"]) < 0}


## The record of the lances played: [{lance, leader, actions [a, b], cue, read, winner, how, roll, threshold,
## touches [a, b], breath [a, b]}].
func lances_log() -> Array:
	return d["log"]


func _plays(side: int) -> bool:
	return side == int(d["player"])


## Opens the lance `d.lance` (who leads); _advance() then draws what the AI chooses now and the cue the reader sees.
func _open() -> void:
	var lance := int(d["lance"])
	var leader := CombatRules.leader_of(cfg, lance)
	d["pending"] = {"leader": leader, "choice": ["", ""], "cue": "", "cue_true": false, "read": 0.0}
	if _log():
		print("[Duel] %s: lance %d abre (lidera %s, aliento %s, toques %s)" % [d["id"], lance + 1,
			"nadie" if leader < 0 else str(leader), d["breath"], d["touches"]])
	_advance()


func _set_cue(leader: int, act: String) -> void:
	var p: Dictionary = d["pending"]
	var reader := 1 - leader
	var read := CombatRules.read_chance(cfg, fighter(reader), fighter(leader))
	p["cue"] = CombatRules.cue(read, act, int(d["seed"]), str(d["id"]), int(d["lance"]))
	p["cue_true"] = str(p["cue"]) == act
	p["read"] = read


func _ai(side: int, role: String, seen: String) -> String:
	return CombatRules.ai_choice(cfg, fighter(side), breath(side), role, seen, (d["history"] as Array)[1 - side],
		int(d["seed"]), str(d["id"]), int(d["lance"]), side)


## Fills what the AI can choose now and resolves the lance once both have chosen (then opens the next).
func _advance() -> void:
	if over():
		return
	var p: Dictionary = d["pending"]
	var choice: Array = p["choice"]
	var leader := int(p["leader"])
	if _ai_yields():
		return
	if leader == CombatRules.BLIND:
		for s: int in [0, 1]:
			if str(choice[s]) == "" and not _plays(s):
				choice[s] = _ai(s, "blind", "")
	else:
		var reader := 1 - leader
		if str(choice[leader]) == "" and not _plays(leader):
			choice[leader] = _ai(leader, "lead", "")
		if str(choice[leader]) != "" and str(p["cue"]) == "":
			_set_cue(leader, str(choice[leader]))
		if str(choice[leader]) != "" and str(choice[reader]) == "" and not _plays(reader):
			choice[reader] = _ai(reader, "read", str(p["cue"]))
	if str(choice[0]) != "" and str(choice[1]) != "":
		_resolve()


## An AI side of a duel that allows yielding gives up when the other needs one touch and it is behind enough.
func _ai_yields() -> bool:
	if not bool(kind().get("can_yield", false)):
		return false
	var ai: Dictionary = cfg.get("ai", {})
	var need := int(kind().get("touches", 3))
	for s: int in [0, 1]:
		if _plays(s):
			continue
		if touches(1 - s) == need - 1 and touches(1 - s) - touches(s) >= int(ai.get("yield_behind", 2)) \
				and CombatRules.roll(int(d["seed"]), str(d["id"]), int(d["lance"]), "yield|%d" % s) \
				< float(ai.get("yield_chance", 0.5)):
			_finish(1 - s, "yield", s)
			return true
	return false


func _resolve() -> void:
	var p: Dictionary = d["pending"]
	var choice: Array = p["choice"]
	var a := str(choice[0])
	var b := str(choice[1])
	var lance := int(d["lance"])
	var r := CombatRules.resolve_lance(cfg, fighter(0), fighter(1), a, b, int(d["seed"]), str(d["id"]), lance)
	var t: Array = d["touches"]
	if int(r["winner"]) >= 0:
		t[int(r["winner"])] = int(t[int(r["winner"])]) + 1
	var br: Array = d["breath"]
	br[0] = CombatRules.breath_after(cfg, fighter(0), int(br[0]), a)
	br[1] = CombatRules.breath_after(cfg, fighter(1), int(br[1]), b)
	((d["history"] as Array)[0] as Array).append(a)
	((d["history"] as Array)[1] as Array).append(b)
	var rec := {"lance": lance, "leader": p["leader"], "actions": [a, b], "cue": p.get("cue", ""),
		"cue_true": p.get("cue_true", false), "read": p.get("read", 0.0), "winner": r["winner"], "how": r["how"],
		"exchange": r["exchange"], "roll": r["roll"], "threshold": r["threshold"], "touches": t.duplicate(),
		"breath": br.duplicate()}
	(d["log"] as Array).append(rec)
	if _log():
		print("[Duel] %s: lance %d %s vs %s (pista %s, %s) -> %s gana=%d (tirada %d/%d) toques %s aliento %s" % [
			d["id"], lance + 1, a, b, rec["cue"], "cierta" if bool(rec["cue_true"]) else "falsa", r["how"],
			int(r["winner"]), int(r["roll"]), int(r["threshold"]), t, br])
	var need := int(kind().get("touches", 3))
	if int(t[0]) >= need or int(t[1]) >= need:
		_finish(0 if int(t[0]) >= need else 1, "touches", -1)
		return
	d["lance"] = lance + 1
	if int(d["lance"]) >= int(kind().get("lances", 9)):
		var w := -1
		if int(t[0]) != int(t[1]):
			w = 0 if int(t[0]) > int(t[1]) else 1
		_finish(w, "lances", -1)
		return
	_open()


func _finish(winner: int, end: String, yielded: int) -> void:
	d["over"] = true
	d["winner"] = winner
	d["end"] = end
	d["yielded"] = yielded
	d["pending"] = {"leader": CombatRules.BLIND, "choice": ["", ""], "cue": ""}
	if _log():
		print("[Duel] %s: fin (%s) gana %d, toques %s, lances %d%s" % [d["id"], end, winner, d["touches"],
			(d["log"] as Array).size(), (", se rinde %d" % yielded) if yielded >= 0 else ""])
