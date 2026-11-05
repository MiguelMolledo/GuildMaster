class_name AzarMatch
extends GameMatch
## «Azar», the dice game of the Libro de los juegos (1283), simplified (docs/gdd/04f_vida_y_fiestas.md §4.26.7; figures:
## data/games.json "azar"). Two sides; the thrower (opts.thrower, else a keyed roll) throws three dice:
##   1. a first throw in azar (3-6, 15-18) wins for the thrower;
##   2. a middle number is the other's chance; the thrower throws for his own: an azar number now is «reazar» and he
##      loses, the other's number again is thrown again, any other middle number is his chance;
##   3. both chances known, each side may double once (the thrower first; one double per game, up to the cap); the
##      other accepts (the game goes on at the double) or refuses (loses the stake as it was);
##   4. the thrower throws until one of the two chances comes: his wins, the other's loses.
## The decision is how much to risk, never the dice: the dice of a game are the same whatever is chosen (keyed by
## throw). The AI doubles above double_at and accepts from accept_at (the thresholds of the best expected gold with
## the house's rake); its temper moves them (prudent asks more, boastful always doubles and accepts).
## Loaded dice (opts.loaded = the side that uses them, block 3 of 04f): see Betting / Games.

var _ways: Dictionary = GameRules.WAYS_3D6


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 10,
		opts: Dictionary = {}) -> AzarMatch:
	var m := AzarMatch.new()
	m.cfg = games
	m._init_d("azar", id, seed, players, player, stake, opts)
	var thrower := int(opts.get("thrower", -1))
	if thrower < 0 and int(opts.get("loaded", -1)) >= 0:
		thrower = int(opts["loaded"])  # who brings loaded dice insists on throwing
	if thrower < 0:
		thrower = 0 if GameRules.roll(seed, id, 0, "thrower") < 0.5 else 1
	m.d.merge({"thrower": thrower, "chances": [0, 0], "throws": [], "stake_now": stake, "doubled_by": -1,
		"phase": "start", "turn": -1, "offered": [false, false]}, true)
	if _log():
		print("[Games] azar %s: tira el lado %d, apuesta %d, jugador %d" % [id, thrower, stake, player])
	m._advance()
	return m


func thrower() -> int:
	return int(d["thrower"])


func is_azar(t: int) -> bool:
	return t in (sec().get("azar", []) as Array)


## The chance that side `side` wins once both chances are known (0.5 before).
func win_chance(side: int) -> float:
	var ch: Array = d["chances"]
	if int(ch[0]) == 0 or int(ch[1]) == 0:
		return 0.5
	var a := float(_ways.get(int(ch[side]), 0))
	var b := float(_ways.get(int(ch[1 - side]), 0))
	return a / (a + b) if a + b > 0.0 else 0.5


## The thresholds of the best expected gold with the rake r: double above 1/(2-r), accept from 1/(2(2-r)).
func double_at() -> float:
	return 1.0 / (2.0 - rake())


func accept_at() -> float:
	return 1.0 / (2.0 * (2.0 - rake()))


func can_double() -> bool:
	return int(d["doubled_by"]) < 0 and int(d["stake_now"]) * 2 <= int(cfg.get("cap", 50))


func _view(side: int) -> Dictionary:
	var acts: Array = []
	var ph := str(d["phase"])
	if not over() and int(d["turn"]) == side:
		if ph == "offer":
			acts = [{"id": "double", "enabled": can_double(), "why": "" if can_double() else "games.why.cap"},
				{"id": "pass", "enabled": true}]
		elif ph == "answer":
			acts = [{"id": "accept", "enabled": true}, {"id": "refuse", "enabled": true}]
	var p := win_chance(side)
	return {"actions": acts, "thrower": thrower(), "chances": (d["chances"] as Array).duplicate(),
		"throws": (d["throws"] as Array).duplicate(true), "stake_now": int(d["stake_now"]), "win": p,
		"doubled_by": int(d["doubled_by"]), "double_at": double_at(), "accept_at": accept_at(),
		"ev_double": _ev(p, 2 * int(d["stake_now"])), "ev_keep": _ev(p, int(d["stake_now"])),
		"prompt": "games.azar.prompt.%s" % ph if acts.size() > 0 else ""}


## The expected gold of playing on at stake s with chance p (the rake taken off a win).
func _ev(p: float, s: int) -> float:
	return p * s * (1.0 - rake()) - (1.0 - p) * s


func _choose(side: int, action: String) -> Dictionary:
	_apply(side, action)
	return {"ok": true, "reason": ""}


func _apply(side: int, action: String) -> void:
	var ph := str(d["phase"])
	(d["log"] as Array).append({"kind": "decision", "side": side, "action": action, "stake": int(d["stake_now"])})
	if ph == "offer":
		(d["offered"] as Array)[side] = true
		if action == "double" and can_double():
			d["doubled_by"] = side
			d["phase"] = "answer"
			d["turn"] = 1 - side
		elif side == thrower():
			d["turn"] = 1 - side
		else:
			d["phase"] = "roll"
			d["turn"] = -1
	elif ph == "answer":
		if action == "accept":
			d["stake_now"] = int(d["stake_now"]) * 2
			d["phase"] = "roll"
			d["turn"] = -1
		else:
			var w := int(d["doubled_by"])
			_settle(w, "refused")


## The AI's decision for side `side` in the open phase.
func ai_decision(side: int) -> String:
	var t := GameRules.temper(cfg, player_of(side))
	var p := win_chance(side)
	var margin := float(t.get("stay_margin", 0.0))
	var bold := bool(t.get("stay_always", false))
	if str(d["phase"]) == "offer":
		if not can_double():
			return "pass"
		return "double" if bold or p > double_at() + margin else "pass"
	return "accept" if bold or p >= accept_at() + margin else "refuse"


func _throw() -> Array:
	var st := step()
	var dice := GameRules.throw_dice(match_seed(), id(), st, "throw", int(sec().get("dice", 3)))
	dice = _loaded(dice, st)
	d["step"] = st + 1
	var t := GameRules.total(dice)
	(d["throws"] as Array).append({"dice": dice, "total": t})
	return [dice, t]


## Loaded dice of the thrower (opts.loaded = his side): on the first throw each die below 4 is thrown again once (an
## azar is likelier); while throwing for the two chances, a throw that shows the other's chance is thrown again
## once with chance loaded.again (keyed). Without them the game is fair; with them the thrower wins about 3 in 5 (tools/games_bench.gd).
func _loaded(dice: Array, st: int) -> Array:
	if int(opt("loaded", -1)) != thrower():
		return dice
	var ph := str(d["phase"])
	var ld: Dictionary = sec().get("loaded", {})
	if ph == "start":
		var out: Array = []
		for i: int in dice.size():
			var x := int(dice[i])
			if x < int(ld.get("below", 4)):
				x = GameRules.d6(match_seed(), id(), st, "loaded|%d" % i)
			out.append(x)
		return out
	if ph == "roll" and GameRules.total(dice) == int((d["chances"] as Array)[1 - thrower()]) \
			and GameRules.roll(match_seed(), id(), st, "loaded_again") < float(ld.get("again", 0.5)):
		return GameRules.throw_dice(match_seed(), id(), st, "loaded", dice.size())
	return dice


func _advance() -> void:
	var guard := 0
	while not over() and guard < 200:
		guard += 1
		var ph := str(d["phase"])
		if ph == "start":
			var r := _throw()
			var t := int(r[1])
			if is_azar(t):
				(d["log"] as Array).append({"kind": "azar", "total": t})
				_settle(thrower(), "azar")
				return
			(d["chances"] as Array)[1 - thrower()] = t
			d["phase"] = "own"
		elif ph == "own":
			var r2 := _throw()
			var t2 := int(r2[1])
			if is_azar(t2):
				(d["log"] as Array).append({"kind": "reazar", "total": t2})
				_settle(1 - thrower(), "reazar")
				return
			if t2 != int((d["chances"] as Array)[1 - thrower()]):
				(d["chances"] as Array)[thrower()] = t2
				d["phase"] = "offer"
				d["turn"] = thrower()
				(d["log"] as Array).append({"kind": "chances", "chances": (d["chances"] as Array).duplicate()})
			elif (d["throws"] as Array).size() > int(sec().get("max_throws", 60)):
				_settle(1 - thrower(), "stuck")
				return
		elif ph == "offer" or ph == "answer":
			var side := int(d["turn"])
			if plays(side):
				return
			_apply(side, ai_decision(side))
		elif ph == "roll":
			var r3 := _throw()
			var t3 := int(r3[1])
			var ch: Array = d["chances"]
			if t3 == int(ch[thrower()]):
				_settle(thrower(), "chance")
				return
			if t3 == int(ch[1 - thrower()]):
				_settle(1 - thrower(), "chance")
				return
			if (d["throws"] as Array).size() > int(sec().get("max_throws", 60)):
				_settle(1 - thrower(), "stuck")
				return
		else:
			return


func _settle(winner: int, how: String) -> void:
	var s := int(d["stake_now"])
	var net: Array = d["net"]
	net[winner] = s
	net[1 - winner] = -s
	(d["scores"] as Array)[winner] = 1
	d["ranking"] = [winner, 1 - winner]
	_finish(winner, how)


func _ai_move(side: int) -> String:
	return ai_decision(side)
