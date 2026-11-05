class_name RescueMatch
extends GameMatch
## The rescue of a kidnapping, played (docs/gdd/04f_vida_y_fiestas.md §4.24.5, §4.26; vida: Incidents, choice
## «rescue»): a chain of duels, the rescuers (the actor first, then the guards he hired) against the band, one fighter of
## each side at a time; whoever loses a bout is out and the next of his side fights on; a draw takes both out. The
## rescuers win when no bandit is left (at most `max_bouts` bouts). Exactly the chain of Incidents._fights (same duel ids
## "<key>|<n>", same fighters, the duel's first blood): played by nobody it gives the same result, so «Resolver sin
## jugar» and the vida's numbers do not move. The played side fights the actor's bouts lance by lance with the duel's
## rules (strike, parry, feint, the gesture); the helpers' bouts are fought by the AI.
##
## Players: the fighters of side A then side B, each {id, name, name_key, fighter (CombatRules.fighter)}; opts.team_a =
## how many are rescuers. Rescue.preview builds them for the screen; Rescue.fight is what Incidents calls.

const MAX_BOUTS: int = 12

var combat: Dictionary = {}


static func create(games: Dictionary, combat_cfg: Dictionary, id: String, seed: int, players: Array, player: int = -1,
		opts: Dictionary = {}) -> RescueMatch:
	var m := RescueMatch.new()
	m.cfg = games
	m.combat = combat_cfg
	m._init_d("rescue", id, seed, players, player, 0, opts)
	var na := int(opts.get("team_a", 1))
	var a: Array = []
	var b: Array = []
	for k: int in players.size():
		(a if k < na else b).append(k)
	m.d.merge({"a": a, "b": b, "i": 0, "j": 0, "n": 0, "current": {}, "lost_a": [], "phase": "bout", "turn": -1}, true)
	if _log():
		print("[Games] rescate %s: %d rescatadores contra %d, jugador %d" % [id, a.size(), b.size(), player])
	m._advance()
	return m


func fighter(k: int) -> Dictionary:
	var p := player_of(k)
	if p.get("fighter") is Dictionary:
		return p["fighter"]
	return CombatRules.fighter(str(p.get("id", "s%d" % k)), p.get("stats", {}), "fists")


func current_duel() -> Duel:
	var c: Dictionary = d["current"]
	return Duel.wrap(combat, c) if not c.is_empty() else null


## The sides of the bout being fought: [rescuer, bandit] (player indices), or [].
func bout_sides() -> Array:
	var a: Array = d["a"]
	var b: Array = d["b"]
	if int(d["i"]) >= a.size() or int(d["j"]) >= b.size():
		return []
	return [int(a[int(d["i"])]), int(b[int(d["j"])])]


func _view(side: int) -> Dictionary:
	var acts: Array = []
	var du := current_duel()
	var dv := {}
	if du != null and not du.over():
		dv = du.view(0)
		if int(d["turn"]) == side:
			for act: String in CombatRules.ACTIONS:
				acts.append({"id": act, "enabled": act in (dv["allowed"] as Array), "cost": CombatRules.cost(combat, act),
					"why": "" if act in (dv["allowed"] as Array) else "reason.no_breath"})
	return {"actions": acts, "duel": dv, "bout_sides": bout_sides(), "bouts": int(d["n"]), "i": int(d["i"]), "j": int(d["j"]),
		"touches": (du.d["touches"] as Array).duplicate() if du != null else [0, 0],
		"breath": (du.d["breath"] as Array).duplicate() if du != null else [0, 0],
		"breath_max": [CombatRules.breath_max(combat, du.fighter(0)), CombatRules.breath_max(combat, du.fighter(1))] if du != null else [0, 0],
		"lance": int(du.d["lance"]) if du != null else 0, "prompt": "games.rescue.prompt" if acts.size() > 0 else ""}


func _choose(_side: int, action: String) -> Dictionary:
	var du := current_duel()
	var before := du.lances_log().size()
	var r := du.choose(0, action)
	_copy(du, before)
	return r


func _copy(du: Duel, from: int) -> void:
	var lg := du.lances_log()
	for k: int in range(from, lg.size()):
		var rec: Dictionary = (lg[k] as Dictionary).duplicate(true)
		rec["kind"] = "lance"
		rec["sides"] = bout_sides()
		(d["log"] as Array).append(rec)


func auto_finish() -> void:
	var du := current_duel()
	if du != null and not du.over():
		var before := du.lances_log().size()
		du.auto_finish()
		_copy(du, before)
	super.auto_finish()


func _advance() -> void:
	var guard := 0
	while not over() and guard < 64:
		guard += 1
		var du := current_duel()
		if du != null:
			if not du.over():
				if plays(0):
					d["turn"] = 0
					return
				var before := du.lances_log().size()
				du.auto_finish()
				_copy(du, before)
			_bout_over(du)
			continue
		var sides := bout_sides()
		if sides.is_empty() or int(d["n"]) >= MAX_BOUTS:
			_end()
			return
		# the actor's bouts (he is the first rescuer) are played; the others the AI fights
		var mine := plays(0) and int(sides[0]) == 0
		var was := Duel.verbose
		Duel.verbose = was and _log()
		var nd := Duel.create(combat, "%s|%d" % [id(), int(d["n"])], match_seed(), fighter(int(sides[0])), fighter(int(sides[1])),
			"first_blood", 0 if mine else -1)
		Duel.verbose = was
		d["current"] = nd.d
		_copy(nd, 0)


func _bout_over(du: Duel) -> void:
	var w := int(du.result()["winner"])
	var sides := bout_sides()
	d["n"] = int(d["n"]) + 1
	var rec := {"kind": "bout", "n": int(d["n"]) - 1, "sides": sides, "winner": w, "touches": (du.d["touches"] as Array).duplicate()}
	(d["log"] as Array).append(rec)
	if w == 0:
		d["j"] = int(d["j"]) + 1
	elif w == 1:
		(d["lost_a"] as Array).append(str(player_of(int(sides[0])).get("id", "")))
		d["i"] = int(d["i"]) + 1
	else:
		d["i"] = int(d["i"]) + 1
		d["j"] = int(d["j"]) + 1
	d["current"] = {}
	d["turn"] = -1


func _end() -> void:
	var won := int(d["j"]) >= (d["b"] as Array).size()
	d["ranking"] = [0, 1] if won else [1, 0]
	_finish(0 if won else 1, "rescued" if won else "beaten")


func won() -> bool:
	return over() and int(d["winner"]) == 0


func _ai_move(side: int) -> String:
	var du := current_duel()
	if du == null or du.over() or side != 0:
		return ""
	var v := du.view(0)
	return CombatRules.ai_choice(combat, du.fighter(0), du.breath(0), str(v["role"]), str(v["cue"]), (du.d["history"] as Array)[1],
		int(du.d["seed"]), str(du.d["id"]), int(v["lance"]), 0)
