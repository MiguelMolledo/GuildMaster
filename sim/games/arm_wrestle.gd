class_name PulsoMatch
extends GameMatch
## Pulso, arm wrestling (docs/gdd/04f_vida_y_fiestas.md §4.26.9; figures: data/games.json "pulso"). Two sides, three
## pushes, the one who takes two wins. Each push both choose push / give / hold (push beats give, give beats hold,
## hold beats push). The winner of the exchange tries to take the push with his strength (constitution against
## constitution plus the advantage); if he fails, or if both chose the same, the push goes by sheer strength. Every push
## has a winner. Strength (the bar): push costs 2, give 1, hold recovers 1; without strength one can only hold.
## The first push is blind; then the initiative alternates (side 0 first): the leader chooses first and his face gives
## him away: the reader sees a gesture that tells the truth with read_chance (empathy of the reader against the
## constitution of the leader). The AI is the duel's: it answers the gesture with what beats it; leading or blind, it
## counters the other's most repeated action with chance ai.habit once there is ai.min_history of it, else it picks at
## random among what it can pay. When the played side leads, the AI reads the gesture of its action, never the action.


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 0,
		opts: Dictionary = {}) -> PulsoMatch:
	var m := PulsoMatch.new()
	m.cfg = games
	m._init_d("pulso", id, seed, players, player, stake, opts)
	m.d.merge({"strength": [m.strength_max(0), m.strength_max(1)], "points": [0, 0], "push": 0, "history": [[], []],
		"pending": {}}, true)
	if _log():
		print("[Games] pulso %s: %s contra %s, fuerza %s, jugador %d" % [id, m.player_of(0).get("id", "?"),
			m.player_of(1).get("id", "?"), m.d["strength"], player])
	m._open()
	return m


func actions() -> Array:
	return ["push", "give", "hold"]


func strength_max(side: int) -> int:
	var s: Dictionary = sec().get("strength", {})
	return int(s.get("base", 2)) + floori(GameRules.stat(player_of(side), "constitution") * float(s.get("per_constitution", 0.5)))


func strength(side: int) -> int:
	return int((d["strength"] as Array)[side])


func cost(action: String) -> int:
	return int(((sec().get("actions", {}) as Dictionary).get(action, {}) as Dictionary).get("cost", 0))


func beats(a: String, b: String) -> bool:
	return str(((sec().get("actions", {}) as Dictionary).get(a, {}) as Dictionary).get("beats", "")) == b


func counter_of(a: String) -> String:
	for x: String in actions():
		if beats(x, a):
			return x
	return "hold"


func affordable(side: int) -> Array:
	var out: Array = []
	for a: String in actions():
		if strength(side) >= maxi(0, cost(a)):
			out.append(a)
	return out


func leader_of(push: int) -> int:
	var blind := int(sec().get("blind", 1))
	if push < blind:
		return GameRules.BLIND
	return (push - blind) % 2


func read_chance(reader: int, leader: int) -> float:
	var bonus := float(GameRules.temper(cfg, player_of(reader)).get("read_bonus", 0.0))
	return GameRules.read_chance(sec().get("read", {}), GameRules.stat(player_of(reader), "empathy"),
		GameRules.stat(player_of(leader), "constitution"), bonus)


## The chance side `side` takes the push when it wins the exchange (then, if it fails, the strength roll).
func win_threshold(side: int) -> int:
	var w: Dictionary = sec().get("win", {})
	return int(w.get("base", 50)) + (GameRules.stat(player_of(side), "constitution")
		- GameRules.stat(player_of(1 - side), "constitution")) * int(w.get("step", 5)) + int(w.get("advantage", 25))


## The threshold of side 0 in the strength roll (side 0 takes the push if it passes).
func tie_threshold() -> int:
	var t: Dictionary = sec().get("tie", {})
	return int(t.get("base", 50)) + (GameRules.stat(player_of(0), "constitution")
		- GameRules.stat(player_of(1), "constitution")) * int(t.get("step", 5))


func _open() -> void:
	var push := int(d["push"])
	var leader := leader_of(push)
	d["pending"] = {"leader": leader, "choice": ["", ""], "cue": "", "cue_true": false, "read": 0.0}
	d["phase"] = "push"
	d["step"] = push
	_advance()


func _view(side: int) -> Dictionary:
	var p: Dictionary = d.get("pending", {})
	var leader := int(p.get("leader", GameRules.BLIND))
	var role := "blind" if leader == GameRules.BLIND else ("lead" if leader == side else "read")
	var acts: Array = []
	if not over() and int(d["turn"]) == side:
		var ok := affordable(side)
		for a: String in actions():
			acts.append({"id": a, "enabled": a in ok, "cost": cost(a), "why": "" if a in ok else "games.why.strength"})
	var v := {"actions": acts, "role": role, "push": int(d["push"]), "points": (d["points"] as Array).duplicate(),
		"strength": (d["strength"] as Array).duplicate(), "strength_max": [strength_max(0), strength_max(1)],
		"cue": {}, "read_by": 0.0, "prompt": "games.pulso.prompt.%s" % role if acts.size() > 0 else ""}
	if role == "read" and str(p.get("cue", "")) != "":
		v["cue"] = {"text": "games.pulso.cue.%s" % str(p["cue"]), "id": str(p["cue"]), "read": float(p.get("read", 0.0))}
	elif role == "lead":
		v["read_by"] = read_chance(1 - side, side)
	return v


func _choose(side: int, action: String) -> Dictionary:
	((d["pending"] as Dictionary)["choice"] as Array)[side] = action
	return {"ok": true, "reason": ""}


func _set_cue(leader: int, act: String) -> void:
	var p: Dictionary = d["pending"]
	var r := read_chance(1 - leader, leader)
	p["cue"] = GameRules.cue(r, act, actions(), match_seed(), id(), int(d["push"]))
	p["cue_true"] = str(p["cue"]) == act
	p["read"] = r


## The AI's action for `side`: role "read" answers `seen` (what beats it if it can pay it, else the gesture itself,
## else hold); "lead"/"blind" counters the other's habit or picks at random among what it can pay.
func ai_choice(side: int, role: String, seen: String) -> String:
	var ok := affordable(side)
	if role == "read" and seen != "":
		var best := counter_of(seen)
		if best in ok:
			return best
		return seen if seen in ok else "hold"
	var ai: Dictionary = sec().get("ai", {})
	var hist: Array = (d["history"] as Array)[1 - side]
	if hist.size() >= int(ai.get("min_history", 2)):
		var mf := GameRules.most_frequent(hist)
		if mf != "" and GameRules.roll(match_seed(), id(), int(d["push"]), "habit|%d" % side) < float(ai.get("habit", 0.5)):
			var c := counter_of(mf)
			if c in ok:
				return c
	return GameRules.pick(ok, match_seed(), id(), int(d["push"]), "style|%d" % side)


func _advance() -> void:
	if over():
		return
	var p: Dictionary = d["pending"]
	var choice: Array = p["choice"]
	var leader := int(p["leader"])
	d["turn"] = -1
	if leader == GameRules.BLIND:
		for s: int in [0, 1]:
			if str(choice[s]) == "" and not plays(s):
				choice[s] = ai_choice(s, "blind", "")
	else:
		var reader := 1 - leader
		if str(choice[leader]) == "" and not plays(leader):
			choice[leader] = ai_choice(leader, "lead", "")
		if str(choice[leader]) != "" and str(p["cue"]) == "":
			_set_cue(leader, str(choice[leader]))
		if str(choice[leader]) != "" and str(choice[reader]) == "" and not plays(reader):
			choice[reader] = ai_choice(reader, "read", str(p["cue"]))
	for s: int in [0, 1]:
		if str(choice[s]) == "":
			# the leader decides first: the reader waits for the gesture
			if leader != GameRules.BLIND and s != leader and str(choice[leader]) == "":
				continue
			d["turn"] = s
			return
	_resolve()


func _resolve() -> void:
	var p: Dictionary = d["pending"]
	var choice: Array = p["choice"]
	var a := str(choice[0])
	var b := str(choice[1])
	var push := int(d["push"])
	var winner := -1
	var how := "strength"
	var r := {}
	if a != b:
		var w := 0 if beats(a, b) else 1
		r = GameRules.check(cfg, win_threshold(w), match_seed(), id(), push, "win")
		if bool(r["success"]):
			winner = w
			how = "beats"
	if winner < 0:
		var t := GameRules.check(cfg, tie_threshold(), match_seed(), id(), push, "strength")
		winner = 0 if bool(t["success"]) else 1
		if r.is_empty():
			r = t
		elif how != "beats":
			how = "held"
	var pts: Array = d["points"]
	pts[winner] = int(pts[winner]) + 1
	var st: Array = d["strength"]
	st[0] = clampi(int(st[0]) - cost(a), 0, strength_max(0))
	st[1] = clampi(int(st[1]) - cost(b), 0, strength_max(1))
	((d["history"] as Array)[0] as Array).append(a)
	((d["history"] as Array)[1] as Array).append(b)
	var rec := {"push": push, "leader": int(p["leader"]), "actions": [a, b], "cue": str(p.get("cue", "")),
		"cue_true": bool(p.get("cue_true", false)), "read": float(p.get("read", 0.0)), "winner": winner, "how": how,
		"roll": int(r.get("roll", 0)), "threshold": int(r.get("threshold", 0)), "points": pts.duplicate(),
		"strength": st.duplicate()}
	(d["log"] as Array).append(rec)
	if _log():
		print("[Games] pulso %s: empuje %d %s vs %s (pista %s) -> %s gana %d, puntos %s, fuerza %s" % [id(), push + 1, a, b,
			rec["cue"], how, winner, pts, st])
	d["scores"] = pts.duplicate()
	if int(pts[winner]) >= int(sec().get("to_win", 2)) or push + 1 >= int(sec().get("pushes", 3)):
		var w2 := 0 if int(pts[0]) > int(pts[1]) else 1
		var s := int(d["stake"])
		(d["net"] as Array)[w2] = s
		(d["net"] as Array)[1 - w2] = -s
		d["ranking"] = [w2, 1 - w2]
		_finish(w2, "pushes")
		return
	d["push"] = push + 1
	_open()


func _ai_move(side: int) -> String:
	var v := view(side)
	return ai_choice(side, str(v["role"]), str((v["cue"] as Dictionary).get("id", "")))
