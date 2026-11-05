class_name BullsMatch
extends GameMatch
## Correr el toro (docs/gdd/04f_vida_y_fiestas.md §4.26.5; figures: data/games.json "bulls"): in the plaza closed with
## carts the lads call the bull and dodge it; no matador, no wounds (O-V5 a: until 4.22's health a failure is a fright
## and the crowd's jeers). 1-4 mozos, three charges each, in turn. Each charge the bull does one of three things
## (keyed, weighted by its kind: data/games.json bulls.bulls): charges straight (charge), feints and stops (feint) or
## hooks to the side (hook); before it goes it gives a sign (it paws the ground, lowers its head, sets off crooked)
## that tells the truth with read = base + (dexterity of the mozo − bravery of the bull) × step. The mozo calls it
## (cite), breaks away at the last moment (break: the quiebro) or gets to safety behind the carts (safe). What each
## gives against each (bulls.payoff): a quiebro to a straight charge is the great applause (2), a call to a feint a
## pass (1), safety is always 0, and the rest is a failure (−1 and a fright). The most applause wins.
##
## The AI (and «Resolver sin jugar») plays the action of the most expected applause against the posterior of the
## bull's action given the sign (its kind's weights as the prior). The screen shows the played side the sign, its
## reliability and the chance of each action of the bull.

const ACTIONS: Array[String] = ["cite", "break", "safe"]
const BULL: Array[String] = ["charge", "feint", "hook"]


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 0,
		opts: Dictionary = {}) -> BullsMatch:
	var m := BullsMatch.new()
	m.cfg = games
	m._init_d("bulls", id, seed, players, player, stake, opts)
	var bull := str(opts.get("bull", m.sec().get("bull", "")))
	if not (m.sec().get("bulls", {}) as Dictionary).has(bull):
		bull = str((m.sec().get("bulls", {}) as Dictionary).keys()[0])
	m.d.merge({"bull": bull, "charge": 0, "mozo": 0, "points": GameMatch._zeros(players.size()),
		"breaks": GameMatch._zeros(players.size()), "fails": GameMatch._zeros(players.size()), "sign": "", "act": "",
		"phase": "charge", "turn": -1}, true)
	if _log():
		print("[Games] toros %s: %d mozos, toro %s, jugador %d" % [id, players.size(), bull, player])
	m._advance()
	return m


func bull() -> Dictionary:
	return (sec().get("bulls", {}) as Dictionary).get(str(d["bull"]), {})


func read_chance(k: int) -> float:
	return GameRules.read_chance(sec().get("read", {}), GameRules.stat(player_of(k), "dexterity"), int(bull().get("bravery", 5)))


func payoff(action: String, bull_act: String) -> float:
	return float(((sec().get("payoff", {}) as Dictionary).get(action, {}) as Dictionary).get(bull_act, 0.0))


## The bull's action for mozo k's charge (keyed, by the bull's weights).
func bull_action(k: int) -> String:
	var w: Dictionary = bull().get("weights", {})
	var total := 0.0
	for a: String in BULL:
		total += float(w.get(a, 1.0))
	var x := GameRules.roll(match_seed(), id(), int(d["charge"]) * 10 + k, "bull") * total
	for a: String in BULL:
		x -= float(w.get(a, 1.0))
		if x < 0.0:
			return a
	return BULL[BULL.size() - 1]


## The chance of each action of the bull given the sign mozo k sees (the bull's weights as the prior).
func odds(k: int) -> Dictionary:
	return GameRules.posterior(bull().get("weights", {}), str(d["sign"]), read_chance(k))


func expected(k: int, action: String) -> float:
	var o := odds(k)
	var v := 0.0
	for b: String in BULL:
		v += float(o.get(b, 0.0)) * payoff(action, b)
	return v


func ai_action(k: int) -> String:
	var best := "safe"
	var bv := -INF
	for a: String in ACTIONS:
		var v := expected(k, a)
		if v > bv + 0.0001:
			bv = v
			best = a
	return best


func _prepare() -> void:
	var k := int(d["mozo"])
	d["act"] = bull_action(k)
	d["sign"] = GameRules.cue(read_chance(k), str(d["act"]), BULL, match_seed(), id(), int(d["charge"]) * 10 + k, "sign")


func _view(side: int) -> Dictionary:
	var acts: Array = []
	if not over() and int(d["turn"]) == side:
		for a: String in ACTIONS:
			acts.append({"id": a, "enabled": true})
	var v := {"actions": acts, "charge": int(d["charge"]), "mozo": int(d["mozo"]), "bull": str(d["bull"]),
		"points": (d["points"] as Array).duplicate(), "breaks": (d["breaks"] as Array).duplicate(),
		"fails": (d["fails"] as Array).duplicate(), "cue": {}, "prompt": "games.bulls.prompt" if acts.size() > 0 else ""}
	if int(d["turn"]) == side and side >= 0:
		v["cue"] = {"text": "games.bulls.cue.%s" % str(d["sign"]), "id": str(d["sign"]), "read": read_chance(side)}
		v["odds"] = odds(side)
		var ex := {}
		for a: String in ACTIONS:
			ex[a] = expected(side, a)
		v["expected"] = ex
	return v


func _choose(side: int, action: String) -> Dictionary:
	_face(side, action)
	return {"ok": true, "reason": ""}


func _face(k: int, action: String) -> void:
	var b := str(d["act"])
	var got := payoff(action, b)
	var pts: Array = d["points"]
	pts[k] = float(pts[k]) + got
	if action == "break" and got > 0.0:
		(d["breaks"] as Array)[k] = int((d["breaks"] as Array)[k]) + 1
	if got < 0.0:
		(d["fails"] as Array)[k] = int((d["fails"] as Array)[k]) + 1
	var rec := {"kind": "charge", "charge": int(d["charge"]), "mozo": k, "bull": b, "sign": str(d["sign"]), "action": action,
		"got": got, "points": pts.duplicate()}
	(d["log"] as Array).append(rec)
	if _log():
		print("[Games] toros %s: embestida %d, mozo %d (señal %s, toro %s) %s -> %s" % [id(), int(d["charge"]) + 1, k,
			d["sign"], b, action, got])
	d["mozo"] = k + 1
	if int(d["mozo"]) >= n_players():
		d["mozo"] = 0
		d["charge"] = int(d["charge"]) + 1


func _advance() -> void:
	var guard := 0
	while not over() and guard < 64:
		guard += 1
		if int(d["charge"]) >= int(sec().get("charges", 3)):
			_end()
			return
		var k := int(d["mozo"])
		_prepare()
		if plays(k):
			d["turn"] = k
			return
		d["turn"] = -1
		_face(k, ai_action(k))


func _end() -> void:
	var pts: Array = d["points"]
	var fails: Array = d["fails"]
	var order: Array = []
	for i: int in n_players():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if not is_equal_approx(float(pts[a]), float(pts[b])):
			return float(pts[a]) > float(pts[b])
		if int(fails[a]) != int(fails[b]):
			return int(fails[a]) < int(fails[b])
		return GameRules.roll(match_seed(), id(), 99, "tie|%d" % a) > GameRules.roll(match_seed(), id(), 99, "tie|%d" % b))
	d["ranking"] = order
	d["scores"] = pts.duplicate()
	(d["facts"] as Array).append({"kind": "bulls", "breaks": int((d["breaks"] as Array)[0]), "fails": int(fails[0])})
	_finish(int(order[0]) if n_players() > 1 else (0 if float(pts[0]) > 0.0 else -1), "applause")


func _ai_move(side: int) -> String:
	return ai_action(side)
