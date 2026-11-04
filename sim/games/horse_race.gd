class_name RaceMatch
extends GameMatch
## The horse race (docs/gdd/04f_vida_y_fiestas.md §4.26.4; figures: data/games.json "race"): four stretches (the
## start, the straight, the mill's bend, the finish) against 3-5 riders. Each stretch every rider chooses a pace:
## reserve (+1 wind), keep (−1) or press (−3); a pace one has no wind for cannot be chosen (without wind, only
## reserve). A stretch covers the horse's speed × the pace's factor + a keyed noise; in the bend, pressing risks a
## stumble (dexterity: base + (dexterity − 3) × step): the stretch counts only `stumble` of itself. The horse matters:
## speed and wind by horse (data/games.json race.horses; the rented one, or the rider's). After the four stretches the
## longest run wins (equal: the faster horse, then a keyed roll).
##
## All choose at once each stretch, seeing where everyone is and his wind. The AI (and «Resolver sin jugar») spends its
## wind by an exact plan (dynamic programming over the stretches left and the wind: the most expected distance, the
## bend's risk counted). The screen shows the played side the distance each pace would give and what is left.

const PACES: Array[String] = ["reserve", "keep", "press"]

var _plans: Dictionary = {}   # "k|from|wind" -> plan(): the plan depends only on the rider, the stretch and the wind


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 0,
		opts: Dictionary = {}) -> RaceMatch:
	var m := RaceMatch.new()
	m.cfg = games
	m._init_d("race", id, seed, players, player, stake, opts)
	var wind: Array = []
	var horses: Array = []
	for i: int in players.size():
		var h := str((players[i] as Dictionary).get("horse", opts.get("horse", "") if i == 0 else ""))
		if not (m.sec().get("horses", {}) as Dictionary).has(h):
			h = str(m.sec().get("rented", "rented"))
		horses.append(h)
		wind.append(int((m.sec()["horses"][h] as Dictionary).get("wind", 6)))
	m.d.merge({"stretch": 0, "horses": horses, "wind": wind, "dist": GameMatch._zeros(players.size()),
		"choice": [], "phase": "stretch", "turn": -1}, true)
	(m.d["choice"] as Array).resize(players.size())
	(m.d["choice"] as Array).fill("")
	if _log():
		print("[Games] carrera %s: %d jinetes, caballos %s, jugador %d" % [id, players.size(), horses, player])
	m._advance()
	return m


func stretches() -> Array:
	return sec().get("stretches", ["start", "straight", "bend", "finish"])


func stretch_id() -> String:
	return str(stretches()[mini(int(d["stretch"]), stretches().size() - 1)])


func horse(k: int) -> Dictionary:
	return (sec().get("horses", {}) as Dictionary).get(str((d["horses"] as Array)[k]), {})


func pace(p: String) -> Dictionary:
	return (sec().get("paces", {}) as Dictionary).get(p, {})


func can_pace(wind: int, p: String) -> bool:
	return wind >= maxi(0, int(pace(p).get("wind", 0)))


func stumble_chance(k: int) -> float:
	var s: Dictionary = sec().get("stumble", {})
	return 1.0 - GameRules.pass_chance(cfg, int(s.get("base", 70)) + (GameRules.stat(player_of(k), "dexterity") - 3)
		* int(s.get("step", 5)))


## The speed factor of pace `p` on stretch `st` (pressing on the finish pays the finish bonus).
func factor(p: String, st: String) -> float:
	var f := float(pace(p).get("factor", 1.0))
	var fin: Dictionary = sec().get("finish", {})
	if st == str(fin.get("stretch", "finish")) and fin.has(p):
		f *= float(fin[p])
	return f


## The expected distance of a stretch at `p` for rider k (the bend's stumble counted).
func stretch_gain(k: int, p: String, st: String) -> float:
	var g := float(horse(k).get("speed", 10.0)) * factor(p, st)
	if st == str(sec().get("risky", "bend")) and bool(pace(p).get("risky", false)):
		var sc := stumble_chance(k)
		g = g * (1.0 - sc) + g * float((sec().get("stumble", {}) as Dictionary).get("keep", 0.5)) * sc
	return g


## The best expected distance of rider k from stretch `from` with `wind` (and the best pace now): {value, pace}.
func plan(k: int, from: int, wind: int) -> Dictionary:
	var key := "%d|%d|%d" % [k, from, wind]
	if _plans.has(key):
		return _plans[key]
	var sts := stretches()
	if from >= sts.size():
		_plans[key] = {"value": 0.0, "pace": ""}
		return _plans[key]
	var best := {"value": -1.0, "pace": "reserve"}
	var wmax := int(horse(k).get("wind", 6))
	for p: String in PACES:
		if not can_pace(wind, p):
			continue
		var w2 := clampi(wind - int(pace(p).get("wind", 0)), 0, wmax)
		var v := stretch_gain(k, p, str(sts[from])) + float(plan(k, from + 1, w2)["value"])
		if v > float(best["value"]) + 0.0001:
			best = {"value": v, "pace": p}
	_plans[key] = best
	return best


func ai_pace(k: int) -> String:
	return str(plan(k, int(d["stretch"]), int((d["wind"] as Array)[k]))["pace"])


func _view(side: int) -> Dictionary:
	var acts: Array = []
	var wind := int((d["wind"] as Array)[side]) if side >= 0 else 0
	if not over() and int(d["turn"]) == side:
		for p: String in PACES:
			var ok := can_pace(wind, p)
			acts.append({"id": p, "enabled": ok, "cost": int(pace(p).get("wind", 0)), "why": "" if ok else "games.why.wind"})
	var gains := {}
	var plans := {}
	if side >= 0:
		var wmax := int(horse(side).get("wind", 6))
		for p: String in PACES:
			gains[p] = stretch_gain(side, p, stretch_id())
			if can_pace(wind, p):
				plans[p] = gains[p] + float(plan(side, int(d["stretch"]) + 1, clampi(wind - int(pace(p).get("wind", 0)), 0, wmax))["value"])
	var winds: Array = (d["wind"] as Array).duplicate()
	var wmaxs: Array = []
	for k: int in n_players():
		wmaxs.append(int(horse(k).get("wind", 6)))
	return {"actions": acts, "stretch": int(d["stretch"]), "stretch_id": stretch_id(), "dist": (d["dist"] as Array).duplicate(),
		"wind": winds, "wind_max": wmaxs, "gains": gains, "plans": plans,
		"stumble": stumble_chance(side) if side >= 0 else 0.0, "horses": (d["horses"] as Array).duplicate(),
		"prompt": "games.race.prompt" if acts.size() > 0 else ""}


func _choose(side: int, action: String) -> Dictionary:
	(d["choice"] as Array)[side] = action
	return {"ok": true, "reason": ""}


func _advance() -> void:
	var guard := 0
	while not over() and guard < 20:
		guard += 1
		var ch: Array = d["choice"]
		d["turn"] = -1
		for k: int in n_players():
			if str(ch[k]) == "" and not plays(k):
				ch[k] = ai_pace(k)
		for k: int in n_players():
			if str(ch[k]) == "":
				d["turn"] = k
				return
		_run()


func _run() -> void:
	var st := int(d["stretch"])
	var sid := stretch_id()
	var ch: Array = d["choice"]
	var dist: Array = d["dist"]
	var wind: Array = d["wind"]
	var gains: Array = []
	var stumbles: Array = []
	for k: int in n_players():
		var p := str(ch[k])
		var g := float(horse(k).get("speed", 10.0)) * factor(p, sid)
		g += (GameRules.roll(match_seed(), id(), st, "noise|%d" % k) * 2.0 - 1.0) * float(sec().get("noise", 1.0))
		var fell := false
		if sid == str(sec().get("risky", "bend")) and bool(pace(p).get("risky", false)):
			var s: Dictionary = sec().get("stumble", {})
			var r := GameRules.check(cfg, int(s.get("base", 70)) + (GameRules.stat(player_of(k), "dexterity") - 3)
				* int(s.get("step", 5)), match_seed(), id(), st, "stumble|%d" % k)
			if not bool(r["success"]):
				fell = true
				g *= float(s.get("keep", 0.5))
		dist[k] = float(dist[k]) + g
		wind[k] = clampi(int(wind[k]) - int(pace(p).get("wind", 0)), 0, int(horse(k).get("wind", 6)))
		gains.append(snappedf(g, 0.01))
		stumbles.append(fell)
	var rec := {"kind": "stretch", "stretch": st, "id": sid, "paces": ch.duplicate(), "gains": gains, "stumbles": stumbles,
		"dist": dist.duplicate(), "wind": wind.duplicate()}
	(d["log"] as Array).append(rec)
	if _log():
		print("[Games] carrera %s: tramo %d (%s) %s -> %s, fuelle %s" % [id(), st + 1, sid, ch, dist, wind])
	for k: int in n_players():
		ch[k] = ""
	d["stretch"] = st + 1
	d["step"] = st + 1
	if int(d["stretch"]) >= stretches().size():
		_end()


func _end() -> void:
	var dist: Array = d["dist"]
	var order: Array = []
	for i: int in n_players():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if not is_equal_approx(float(dist[a]), float(dist[b])):
			return float(dist[a]) > float(dist[b])
		if float(horse(a).get("speed", 0)) != float(horse(b).get("speed", 0)):
			return float(horse(a).get("speed", 0)) > float(horse(b).get("speed", 0))
		return GameRules.roll(match_seed(), id(), 99, "tie|%d" % a) > GameRules.roll(match_seed(), id(), 99, "tie|%d" % b))
	d["ranking"] = order
	var sc: Array = []
	for x: Variant in dist:
		sc.append(snappedf(float(x), 0.01))
	d["scores"] = sc
	var w := int(order[0])
	var s := int(d["stake"])
	if s > 0:
		var net: Array = d["net"]
		for i: int in n_players():
			net[i] = -s
		net[w] = s * (n_players() - 1)
	_finish(w, "finish")


func _ai_move(side: int) -> String:
	return ai_pace(side)
