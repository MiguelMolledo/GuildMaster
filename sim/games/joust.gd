class_name JoustMatch
extends GameMatch
## The joust, a tournament on horseback (docs/gdd/04f_vida_y_fiestas.md §4.26.1; figures: data/games.json "joust").
## Two riders, three passes. Each pass each rider takes a stance that says both where his lance goes and where his
## shield is (data/games.json joust.stances): «al yelmo» (lance high, shield mid: covers the chest), «al pecho» (lance
## at the chest, shield low: covers the shield's face) or «al escudo» (lance at the shield, shield high: covers the
## helm). The three make a triangle like the duel's: al escudo beats al yelmo (his lance meets the shield held high and
## yours finds his shield open), al yelmo beats al pecho (his shield is low: the helm is open), al pecho beats al
## escudo (his chest is open). A lance aimed at what the other does not cover tries its hit (dexterity against
## dexterity plus the aim's difficulty): the helm unhorses (the joust is won), the chest is worth 2, the shield 1; a
## covered helm or chest is 0; the shield always gives half a point («medio punto seguro»).
##
## Initiative and reading as in the duel (and the pulso): the first pass is blind; then the riders lead in turn (side
## 0 first): who leads chooses first and his horse and seat give him away; the other sees a gesture true with
## read_chance (empathy of the reader against the martial of the rider). The AI answers the gesture with the stance
## that beats it; leading or blind it counters the other's most repeated stance with chance ai.habit (once there is
## ai.min_history of them), else it picks at random. After `passes` the most points win; equal, up to `extra` more
## passes, then a draw.

const STANCES: Array[String] = ["helm", "chest", "shield"]


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 0,
		opts: Dictionary = {}) -> JoustMatch:
	var m := JoustMatch.new()
	m.cfg = games
	m._init_d("joust", id, seed, players, player, stake, opts)
	m.d.merge({"pass": 0, "points": [0.0, 0.0], "history": [[], []], "pending": {}, "phase": "pass", "turn": -1}, true)
	if _log():
		print("[Games] justa %s: %s contra %s, jugador %d" % [id, m.player_of(0).get("id", "?"), m.player_of(1).get("id", "?"),
			player])
	m._open()
	return m


func stance(st: String) -> Dictionary:
	return (sec().get("stances", {}) as Dictionary).get(st, {})


func aim_of(st: String) -> String:
	return str(stance(st).get("aim", ""))


func cover_of(st: String) -> String:
	return str(stance(st).get("covers", ""))


func aim_cfg(aim: String) -> Dictionary:
	return (sec().get("aims", {}) as Dictionary).get(aim, {})


## Whether stance a beats stance b (a's lance finds b open and b's lance meets a's cover).
func beats(a: String, b: String) -> bool:
	return cover_of(b) != aim_of(a) and cover_of(a) == aim_of(b)


func counter_of(st: String) -> String:
	for x: String in STANCES:
		if beats(x, st):
			return x
	return "shield"


func read_chance(reader: int, rider: int) -> float:
	return GameRules.read_chance(sec().get("read", {}), GameRules.stat(player_of(reader), "empathy"),
		GameRules.stat(player_of(rider), "martial"))


func leader_of(ps: int) -> int:
	var blind := int(sec().get("blind", 1))
	return GameRules.BLIND if ps < blind else (ps - blind) % 2


## The threshold of side `s`'s hit at `aim` (dexterity against the other's, plus the aim's difficulty).
func hit_threshold(s: int, aim: String) -> int:
	var h: Dictionary = sec().get("hit", {})
	return int(h.get("base", 55)) + (GameRules.stat(player_of(s), "dexterity") - GameRules.stat(player_of(1 - s), "dexterity")) \
		* int(h.get("step", 5)) + int(aim_cfg(aim).get("mod", 0))


func _open() -> void:
	d["pending"] = {"leader": leader_of(int(d["pass"])), "choice": ["", ""], "cue": "", "cue_true": false, "read": 0.0}
	d["phase"] = "pass"
	d["step"] = int(d["pass"])
	_advance()


func _view(side: int) -> Dictionary:
	var p: Dictionary = d.get("pending", {})
	var leader := int(p.get("leader", GameRules.BLIND))
	var role := "blind" if leader == GameRules.BLIND else ("lead" if leader == side else "read")
	var acts: Array = []
	if not over() and int(d["turn"]) == side:
		for st: String in STANCES:
			acts.append({"id": st, "enabled": true})
	var hits := {}
	for a: String in ["helm", "chest", "shield"]:
		hits[a] = GameRules.pass_chance(cfg, hit_threshold(side, a)) if side >= 0 else 0.0
	var v := {"actions": acts, "role": role, "pass": int(d["pass"]), "points": (d["points"] as Array).duplicate(),
		"hits": hits, "cue": {}, "read_by": 0.0, "prompt": "games.joust.prompt.%s" % role if acts.size() > 0 else ""}
	if role == "read" and str(p.get("cue", "")) != "":
		v["cue"] = {"text": "games.joust.cue.%s" % str(p["cue"]), "id": str(p["cue"]), "read": float(p.get("read", 0.0))}
	elif role == "lead":
		v["read_by"] = read_chance(1 - side, side)
	return v


func _choose(side: int, action: String) -> Dictionary:
	((d["pending"] as Dictionary)["choice"] as Array)[side] = action
	return {"ok": true, "reason": ""}


func ai_choice(side: int, role: String, seen: String) -> String:
	if role == "read" and seen != "":
		return counter_of(seen)
	var ai: Dictionary = sec().get("ai", {})
	var hist: Array = (d["history"] as Array)[1 - side]
	if hist.size() >= int(ai.get("min_history", 1)):
		var mf := GameRules.most_frequent(hist)
		if mf != "" and GameRules.roll(match_seed(), id(), int(d["pass"]), "habit|%d" % side) < float(ai.get("habit", 0.5)):
			return counter_of(mf)
	return GameRules.pick(STANCES, match_seed(), id(), int(d["pass"]), "style|%d" % side)


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
			var r := read_chance(reader, leader)
			p["cue"] = GameRules.cue(r, str(choice[leader]), STANCES, match_seed(), id(), int(d["pass"]))
			p["cue_true"] = str(p["cue"]) == str(choice[leader])
			p["read"] = r
		if str(choice[leader]) != "" and str(choice[reader]) == "" and not plays(reader):
			choice[reader] = ai_choice(reader, "read", str(p["cue"]))
	for s: int in [0, 1]:
		if str(choice[s]) == "":
			if leader != GameRules.BLIND and s != leader and str(choice[leader]) == "":
				continue
			d["turn"] = s
			return
	_resolve()


func _resolve() -> void:
	var p: Dictionary = d["pending"]
	var ch: Array = p["choice"]
	var ps := int(d["pass"])
	var pts: Array = d["points"]
	var got: Array = [0.0, 0.0]
	var hits: Array = [false, false]
	var unhorsed: Array = [false, false]
	for s: int in [0, 1]:
		var aim := aim_of(str(ch[s]))
		var safe := float(aim_cfg(aim).get("safe", 0.0))
		if cover_of(str(ch[1 - s])) == aim:
			got[s] = safe
			continue
		var r := GameRules.check(cfg, hit_threshold(s, aim), match_seed(), id(), ps, "hit|%d" % s)
		hits[s] = bool(r["success"])
		got[s] = float(aim_cfg(aim).get("points", 0)) if bool(r["success"]) else safe
		if bool(r["success"]) and bool(aim_cfg(aim).get("unhorses", false)):
			unhorsed[1 - s] = true
	pts[0] = float(pts[0]) + float(got[0])
	pts[1] = float(pts[1]) + float(got[1])
	((d["history"] as Array)[0] as Array).append(str(ch[0]))
	((d["history"] as Array)[1] as Array).append(str(ch[1]))
	var un := -1
	if bool(unhorsed[0]) != bool(unhorsed[1]):
		un = 0 if bool(unhorsed[0]) else 1
	var rec := {"kind": "pass", "pass": ps, "leader": int(p["leader"]), "stances": ch.duplicate(), "cue": str(p.get("cue", "")),
		"cue_true": bool(p.get("cue_true", false)), "read": float(p.get("read", 0.0)), "got": got.duplicate(),
		"hits": hits.duplicate(), "points": pts.duplicate(), "unhorsed": un}
	(d["log"] as Array).append(rec)
	if _log():
		print("[Games] justa %s: pasada %d %s vs %s (pista %s) -> %s, puntos %s%s" % [id(), ps + 1, ch[0], ch[1],
			rec["cue"], got, pts, (", desmonta a %d" % un) if un >= 0 else ""])
	d["scores"] = pts.duplicate()
	if un >= 0:
		(d["facts"] as Array).append({"kind": "unhorsed", "side": un})
		_end(1 - un, "unhorsed")
		return
	var passes := int(sec().get("passes", 3))
	if ps + 1 >= passes and float(pts[0]) != float(pts[1]):
		_end(0 if float(pts[0]) > float(pts[1]) else 1, "points")
		return
	if ps + 1 >= passes + int(sec().get("extra", 2)):
		_end(-1, "draw")
		return
	d["pass"] = ps + 1
	_open()


func _end(w: int, how: String) -> void:
	var s := int(d["stake"])
	if w >= 0:
		(d["net"] as Array)[w] = s
		(d["net"] as Array)[1 - w] = -s
		d["ranking"] = [w, 1 - w]
	_finish(w, how)


func _ai_move(side: int) -> String:
	var v := view(side)
	return ai_choice(side, str(v["role"]), str((v["cue"] as Dictionary).get("id", "")))
