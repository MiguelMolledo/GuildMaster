class_name MayorMatch
extends GameMatch
## «Tres dados a la mayor» (docs/gdd/04f_vida_y_fiestas.md §4.26.7; figures: data/games.json "mayor"). 2-4 sides put
## the stake and throw three dice: two in sight of all, the last under the cup (only its owner sees it). Then all
## decide at once: retire (loses half the stake) or go on (puts the stake again: double or nothing). Of those who go
## on the highest total takes the pot (ties share it; the odd gold goes to the first of them); alone, he takes it
## without showing; if nobody goes on, all lose half.
##
## What the screen shows (and the AI uses): the chance of beating every other at once with their hidden dice unknown
## (`share`: ties count their part) and the expected gold of going on if all go on, against the half lost retiring.
## The AI goes on when going on is worth more (temper even, «Resolver sin jugar»); prudent asks stay_margin more of the
## share; boastful always goes on («el atrevido dobla siempre»).


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 10,
		opts: Dictionary = {}) -> MayorMatch:
	var m := MayorMatch.new()
	m.cfg = games
	m._init_d("mayor", id, seed, players, player, stake, opts)
	var dice: Array = []
	for i: int in players.size():
		var th := GameRules.throw_dice(seed, id, 0, "p%d" % i, int(m.sec().get("dice", 3)))
		if int(opts.get("loaded", -1)) == i:
			th = m._load_dice(th, i)
		dice.append(th)
	m.d.merge({"dice": dice, "decisions": _empty(players.size()), "phase": "decide", "turn": -1, "step": 1}, true)
	if _log():
		print("[Games] mayor %s: %d jugadores, apuesta %d, dados %s, jugador %d" % [id, players.size(), stake, dice, player])
	m._advance()
	return m


static func _empty(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append("")
	return out


## Loaded dice: a die below 4 is thrown again once (keyed).
func _load_dice(th: Array, side: int) -> Array:
	var out: Array = []
	for i: int in th.size():
		var x := int(th[i])
		if x < 4:
			x = GameRules.d6(match_seed(), id(), 0, "loaded|%d|%d" % [side, i])
		out.append(x)
	return out


func hidden_n() -> int:
	return int(sec().get("hidden", 1))


func dice_of(side: int) -> Array:
	return (d["dice"] as Array)[side]


## The dice of `side` that `viewer` sees: all his own, the visible ones of the others (0 = under the cup), all at the end.
func dice_seen(side: int, viewer: int) -> Array:
	var th := dice_of(side)
	if side == viewer or over():
		return th.duplicate()
	var out: Array = th.duplicate()
	for i: int in range(out.size() - hidden_n(), out.size()):
		out[i] = 0
	return out


## {share, ev} of `side` if every side goes on, over every value of the others' hidden dice: share = the expected part
## of the pot (1/k when it ties with k-1 others at the top, 0 when someone is higher); ev = the expected gold of going
## on (the part of the pot minus the two stakes put, the rake taken off a net win).
func odds(side: int) -> Dictionary:
	var mine := GameRules.total(dice_of(side))
	var others: Array = []
	for j: int in n_players():
		if j != side:
			others.append(GameRules.total(dice_seen(j, side)))
	var s := float(int(d["stake"]))
	var pot := 2.0 * s * n_players()
	var acc := {"share": 0.0, "ev": 0.0, "n": 0}
	_enum(mine, others, 0, 1, false, pot, s, acc)
	var n := maxi(1, int(acc["n"]))
	return {"share": float(acc["share"]) / n, "ev": float(acc["ev"]) / n}


func _enum(mine: int, others: Array, i: int, ties: int, beaten: bool, pot: float, s: float, acc: Dictionary) -> void:
	if i >= others.size():
		var f := 0.0 if beaten else 1.0 / float(ties)
		var net := f * pot - 2.0 * s
		if net > 0.0:
			net *= 1.0 - rake()
		acc["share"] = float(acc["share"]) + f
		acc["ev"] = float(acc["ev"]) + net
		acc["n"] = int(acc["n"]) + 1
		return
	for h: int in range(1, 7):
		var t := int(others[i]) + h
		_enum(mine, others, i + 1, ties + (1 if t == mine else 0), beaten or t > mine, pot, s, acc)


func share(side: int) -> float:
	return float(odds(side)["share"])


func ev_stay(side: int) -> float:
	return float(odds(side)["ev"])


func ev_retire() -> float:
	return -float(int(d["stake"])) * (1.0 - float(sec().get("retire_keep", 0.5)))


## The chance nobody is higher than `side` (ties included).
func _p_not_beaten(side: int) -> float:
	var mine := GameRules.total(dice_of(side))
	var p := 1.0
	for j: int in n_players():
		if j == side:
			continue
		var v := GameRules.total(dice_seen(j, side))
		var ok := 0
		for h: int in range(1, 7):
			if v + h <= mine:
				ok += 1
		p *= ok / 6.0
	return p


func ai_decision(side: int) -> String:
	var t := GameRules.temper(cfg, player_of(side))
	if bool(t.get("stay_always", false)):
		return "stay"
	var margin := float(t.get("stay_margin", 0.0))
	var ev := ev_stay(side) - margin * 2.0 * float(int(d["stake"])) * n_players()
	return "stay" if ev > ev_retire() else "retire"


func _view(side: int) -> Dictionary:
	var acts: Array = []
	if not over() and int(d["turn"]) == side:
		acts = [{"id": "stay", "enabled": true}, {"id": "retire", "enabled": true}]
	var seen: Array = []
	for j: int in n_players():
		seen.append(dice_seen(j, side))
	var dec: Array = (d["decisions"] as Array).duplicate()
	if not over():  # the others' decisions are not known until all have decided
		for j: int in n_players():
			if j != side:
				dec[j] = ""
	return {"actions": acts, "dice": seen, "share": share(side) if side >= 0 else 0.0,
		"beat": _p_not_beaten(side) if side >= 0 else 0.0, "ev_stay": ev_stay(side) if side >= 0 else 0.0,
		"ev_retire": ev_retire(), "decisions": dec, "stake": int(d["stake"]),
		"prompt": "games.mayor.prompt" if acts.size() > 0 else ""}


func _choose(side: int, action: String) -> Dictionary:
	(d["decisions"] as Array)[side] = action
	return {"ok": true, "reason": ""}


func _advance() -> void:
	if over():
		return
	var dec: Array = d["decisions"]
	for j: int in n_players():
		if str(dec[j]) == "" and not plays(j):
			dec[j] = ai_decision(j)
	for j: int in n_players():
		if str(dec[j]) == "":
			d["turn"] = j
			return
	_showdown()


func _showdown() -> void:
	var s := int(d["stake"])
	var n := n_players()
	var dec: Array = d["decisions"]
	var keep := int(floor(s * float(sec().get("retire_keep", 0.5))))
	var lose_half := s - keep
	var stayers: Array = []
	var pot := 0
	for j: int in n:
		if str(dec[j]) == "stay":
			stayers.append(j)
			pot += 2 * s
		else:
			pot += lose_half
	var net: Array = d["net"]
	var sc: Array = d["scores"]
	for j: int in n:
		sc[j] = GameRules.total(dice_of(j))
	(d["log"] as Array).append({"kind": "showdown", "decisions": dec.duplicate(), "dice": (d["dice"] as Array).duplicate(true)})
	if stayers.is_empty():
		for j: int in n:
			net[j] = -lose_half
		d["ranking"] = []
		_finish(-1, "all_retired")
		return
	var best := -1
	for j: Variant in stayers:
		best = maxi(best, int(sc[int(j)]))
	var top: Array = []
	for j: Variant in stayers:
		if int(sc[int(j)]) == best:
			top.append(int(j))
	var part := pot / top.size()
	var odd := pot - part * top.size()
	for j: int in n:
		var put := 2 * s if str(dec[j]) == "stay" else lose_half
		var got := 0
		if j in top:
			got = part + (odd if j == int(top[0]) else 0)
		net[j] = got - put
	var rank: Array = top.duplicate()
	var rest: Array = []
	for j: int in n:
		if not j in top:
			rest.append(j)
	rest.sort_custom(func(a: int, b: int) -> bool:
		var sa := 1 if str(dec[a]) == "stay" else 0
		var sb := 1 if str(dec[b]) == "stay" else 0
		if sa != sb:
			return sa > sb
		return int(sc[a]) > int(sc[b]))
	d["ranking"] = rank + rest
	_finish(int(top[0]) if top.size() == 1 else -1, "alone" if stayers.size() == 1 else ("tie" if top.size() > 1 else "highest"))


func _ai_move(side: int) -> String:
	return ai_decision(side)
