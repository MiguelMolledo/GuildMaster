class_name TourneyMatch
extends GameMatch
## The fighting tournament (docs/gdd/04f_vida_y_fiestas.md §4.26.2; figures: data/games.json "tourney" and the
## duel's data/combat.json): a knockout of 8 with the duel of 04e in the kind «a tres asaltos, por puntos»
## (combat kind `tourney`: nine lances in three rounds of three, every touch a point, no wound). Equal points go to a
## sudden death (`tourney_sudden`: the first touch in three lances), then the judges: more breath left, then a keyed
## roll. Every fighter fights with the tournament's weapon (opts.weapon: sword, staff or fists; the tournament's
## default). The rounds come one after the other: a fighter starts each bout with the breath he ended the last with
## plus `recover` (it does not all come back).
##
## Side 0 is the played side's fighter; the others (sides 1-7) are characters with martial >= min_martial or the
## outsiders of data/games.json presets (Games / TourneyMatch.entrants). The draw (who meets whom) is a keyed
## shuffle. The bouts without the played side are fought at once by the AI (Duel.auto); the played side's are fought
## lance by lance with the duel's rules: its actions are the duel's (strike, parry, feint), the gesture and its
## reliability are the duel's (Duel.view). Rolls: the duel's keys with the bout's id "<match>|r<round>|b<bout>[|s]".

var combat: Dictionary = {}


static func create(games: Dictionary, combat_cfg: Dictionary, id: String, seed: int, players: Array, player: int = -1,
		stake: int = 0, opts: Dictionary = {}) -> TourneyMatch:
	var m := TourneyMatch.new()
	m.cfg = games
	m.combat = combat_cfg
	m._init_d("tourney", id, seed, players, player, stake, opts)
	var order: Array = []
	for i: int in players.size():
		order.append(i)
	for i: int in range(order.size() - 1, 0, -1):  # the draw
		var j := floori(GameRules.roll(seed, id, 0, "draw|%d" % i) * (i + 1))
		var t: Variant = order[i]
		order[i] = order[j]
		order[j] = t
	var breath: Array = []
	for i: int in players.size():
		breath.append(CombatRules.breath_max(combat_cfg, m.fighter(i)))
	m.d.merge({"draw": order.duplicate(), "round": 0, "field": order, "next": [], "bout": 0, "breath": breath,
		"current": {}, "current_sides": [], "sudden": false, "rounds_won": GameMatch._zeros(players.size()),
		"bouts": [], "phase": "bout", "turn": -1}, true)
	if _log():
		print("[Games] torneo %s: %d luchadores, sorteo %s, arma %s, jugador %d" % [id, players.size(), order,
			m.weapon(), player])
	m._advance()
	return m


func weapon() -> String:
	return str(opt("weapon", sec().get("weapon", "sword")))


## The duel's fighter of side `i` (the tournament's weapon, no armour).
func fighter(i: int) -> Dictionary:
	var p := player_of(i)
	return CombatRules.fighter(str(p.get("id", "s%d" % i)), p.get("stats", {}), weapon(), false, false)


func round_name(r: int) -> String:
	var left := (d["field"] as Array).size() if r == int(d["round"]) else 0
	return "final" if left == 2 else ("semi" if left == 4 else "quarter")


## The duel of the played side's open bout (null if none).
func current_duel() -> Duel:
	var c: Dictionary = d["current"]
	return Duel.wrap(combat, c) if not c.is_empty() else null


## The side (0/1) the played fighter has in the open duel.
func duel_side() -> int:
	var cs: Array = d["current_sides"]
	return 0 if not cs.is_empty() and int(cs[0]) == 0 else 1


func _view(side: int) -> Dictionary:
	var acts: Array = []
	var du := current_duel()
	var dv := {}
	if du != null and not du.over():
		dv = du.view(duel_side())
		if int(d["turn"]) == side:
			var allowed: Array = dv["allowed"]
			for a: String in CombatRules.ACTIONS:
				acts.append({"id": a, "enabled": a in allowed, "cost": CombatRules.cost(combat, a),
					"why": "" if a in allowed else "reason.no_breath"})
	var cs: Array = d["current_sides"]
	return {"actions": acts, "duel": dv, "bout_sides": cs.duplicate(), "round": int(d["round"]),
		"field": (d["field"] as Array).duplicate(), "bouts": (d["bouts"] as Array).duplicate(true),
		"draw": (d["draw"] as Array).duplicate(), "sudden": bool(d["sudden"]),
		"touches": (du.d["touches"] as Array).duplicate() if du != null else [0, 0],
		"breath": (du.d["breath"] as Array).duplicate() if du != null else [0, 0],
		"breath_max": [CombatRules.breath_max(combat, du.fighter(0)), CombatRules.breath_max(combat, du.fighter(1))] if du != null else [0, 0],
		"lance": int(du.d["lance"]) if du != null else 0, "lances": int(du.kind().get("lances", 9)) if du != null else 9,
		"alive": _alive(0), "prompt": "games.tourney.prompt" if acts.size() > 0 else ""}


## Whether side `s` is still in the tournament.
func _alive(s: int) -> bool:
	return s in (d["field"] as Array) or s in (d["next"] as Array)


func _choose(_side: int, action: String) -> Dictionary:
	var du := current_duel()
	var before := du.lances_log().size()
	var r := du.choose(duel_side(), action)
	_copy_lances(du, before)
	return r


func _copy_lances(du: Duel, from: int) -> void:
	var lg := du.lances_log()
	for i: int in range(from, lg.size()):
		var rec: Dictionary = (lg[i] as Dictionary).duplicate(true)
		rec["kind"] = "lance"
		rec["sides"] = (d["current_sides"] as Array).duplicate()
		rec["round"] = int(d["round"])
		rec["sudden"] = bool(d["sudden"])
		(d["log"] as Array).append(rec)


func auto_finish() -> void:
	var du := current_duel()
	if du != null and not du.over():
		var before := du.lances_log().size()
		du.auto_finish()
		_copy_lances(du, before)
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
				_copy_lances(du, before)
			_bout_over(du)
			continue
		var field: Array = d["field"]
		var b := int(d["bout"])
		if b * 2 >= field.size():
			_next_round()
			continue
		var a := int(field[b * 2])
		var c := int(field[b * 2 + 1])
		d["current_sides"] = [a, c]
		d["sudden"] = false
		_open_duel("tourney")


func _open_duel(kind: String) -> void:
	var cs: Array = d["current_sides"]
	var a := int(cs[0])
	var c := int(cs[1])
	var mine := plays(0) and (a == 0 or c == 0)
	var did := "%s|r%d|b%d%s" % [id(), int(d["round"]), int(d["bout"]), "|s" if kind != "tourney" else ""]
	var br: Array = d["breath"]
	var was := Duel.verbose
	Duel.verbose = was and _log()
	var du := Duel.create(combat, did, match_seed(), fighter(a), fighter(c), kind, (0 if a == 0 else 1) if mine else -1,
		[int(br[a]), int(br[c])])
	Duel.verbose = was
	d["current"] = du.d
	_copy_lances(du, 0)


func _bout_over(du: Duel) -> void:
	var r := du.result()
	var cs: Array = d["current_sides"]
	var w := int(r["winner"])
	if w < 0 and not bool(d["sudden"]):
		# equal points: sudden death with the breath they have
		var br: Array = d["breath"]
		br[int(cs[0])] = du.breath(0)
		br[int(cs[1])] = du.breath(1)
		d["sudden"] = true
		_open_duel("tourney_sudden")
		return
	var how := "points" if not bool(d["sudden"]) else "sudden"
	if w < 0:  # the judges: more breath left, then a keyed roll
		how = "judges"
		if du.breath(0) != du.breath(1):
			w = 0 if du.breath(0) > du.breath(1) else 1
		else:
			w = 0 if GameRules.roll(match_seed(), id(), int(d["round"]) * 10 + int(d["bout"]), "judges") < 0.5 else 1
	var winner := int(cs[w])
	var loser := int(cs[1 - w])
	var br2: Array = d["breath"]
	br2[winner] = mini(CombatRules.breath_max(combat, fighter(winner)), du.breath(w) + int(sec().get("recover", 2)))
	(d["rounds_won"] as Array)[winner] = int((d["rounds_won"] as Array)[winner]) + 1
	(d["next"] as Array).append(winner)
	var rec := {"kind": "bout", "round": int(d["round"]), "bout": int(d["bout"]), "sides": cs.duplicate(), "winner": winner,
		"loser": loser, "touches": (du.d["touches"] as Array).duplicate(), "how": how}
	(d["bouts"] as Array).append(rec)
	(d["log"] as Array).append(rec)
	if _log():
		print("[Games] torneo %s: ronda %d combate %d: %d contra %d -> gana %d (%s, toques %s)" % [id(), int(d["round"]),
			int(d["bout"]), int(cs[0]), int(cs[1]), winner, how, du.d["touches"]])
	d["current"] = {}
	d["current_sides"] = []
	d["sudden"] = false
	d["bout"] = int(d["bout"]) + 1
	d["turn"] = -1


func _next_round() -> void:
	var nxt: Array = d["next"]
	if nxt.size() <= 1:
		var w := int(nxt[0]) if nxt.size() == 1 else -1
		d["scores"] = (d["rounds_won"] as Array).duplicate()
		var rank: Array = []
		for i: int in n_players():
			rank.append(i)
		var rw: Array = d["rounds_won"]
		rank.sort_custom(func(a: int, b: int) -> bool:
			if a == w:
				return true
			if b == w:
				return false
			if int(rw[a]) != int(rw[b]):
				return int(rw[a]) > int(rw[b])
			return a < b)
		d["ranking"] = rank
		_finish(w, "final")
		return
	d["field"] = nxt.duplicate()
	d["next"] = []
	d["round"] = int(d["round"]) + 1
	d["bout"] = 0


func _ai_move(side: int) -> String:
	var du := current_duel()
	if du == null or du.over():
		return ""
	var v := du.view(duel_side())
	return CombatRules.ai_choice(combat, du.fighter(duel_side()), du.breath(duel_side()), str(v["role"]), str(v["cue"]),
		(du.d["history"] as Array)[1 - duel_side()], int(du.d["seed"]), str(du.d["id"]), int(v["lance"]), duel_side()) \
		if side == 0 else ""


## The entrants of a tournament for `actor`: him, then the characters of other families with martial >= min_martial
## (by id), then the outsiders of `outsiders` (data/games.json "tourney") up to `size`: refs for Games.player_ref.
static func entrants(state: WorldState, games: Dictionary, actor: String) -> Array:
	var t: Dictionary = games.get("tourney", {})
	var size := int(t.get("size", 8))
	var out: Array = [actor]
	var fam := str(state.characters.get(actor, {}).get("family", ""))
	var ids: Array = state.characters.keys()
	ids.sort()
	for c: String in ids:
		if out.size() >= size:
			break
		var ch: Dictionary = state.characters[c]
		if c == actor or str(ch.get("family", "")) == fam or not bool(ch.get("alive", true)):
			continue
		if int((ch.get("stats", {}) as Dictionary).get("martial", 0)) >= int(t.get("min_martial", 4)):
			out.append(c)
	for o: Variant in t.get("outsiders", []):
		if out.size() >= size:
			break
		out.append("preset:" + str(o))
	return out
