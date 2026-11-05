class_name SortijaMatch
extends GameMatch
## Correr la sortija (docs/gdd/04f_vida_y_fiestas.md §4.26.3; figures: data/games.json "sortija"): at a gallop, thread
## a ring hung over the lane with the lance. 2-6 riders, three runs each, in turn. Each run the ring is large, medium or
## small (keyed per run, the same for all). The rider chooses a pace (prudent 1 point, firm 2, full gallop 3) and then
## the moment to lower the lance among three signals (the first, the second or the third post). One moment is right
## (keyed per rider and run); the ring's sway shows it, true with read = pace's read + (dexterity − 3) × step (the faster
## the harder to see). Lowering at the right moment threads the ring if the hit passes: pace's window + ring's mod +
## (dexterity − 3) × step. Threaded: the pace's points; else 0. After three runs the most points win; equal, more rings
## threaded; still equal, a keyed roll.
##
## The AI (and «Resolver sin jugar») lowers the lance where the sway says (with reliability above 1/3 that is always
## the best) and chooses the pace of the most expected points (points × chance of the right moment × chance of the
## hit); on the last run, when it is behind, the pace with the best chance of passing the leader. The screen shows the
## played side those numbers.

const PACES: Array[String] = ["prudent", "firm", "gallop"]
const MOMENTS: Array[String] = ["first", "second", "third"]


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 0,
		opts: Dictionary = {}) -> SortijaMatch:
	var m := SortijaMatch.new()
	m.cfg = games
	m._init_d("sortija", id, seed, players, player, stake, opts)
	var rings: Array = []
	var sizes: Array = (m.sec().get("rings", {}) as Dictionary).keys()
	sizes.sort()
	for r: int in int(m.sec().get("runs", 3)):
		rings.append(GameRules.pick(sizes, seed, id, r, "ring"))
	m.d.merge({"run": 0, "rider": 0, "rings": rings, "points": GameMatch._zeros(players.size()),
		"hits": GameMatch._zeros(players.size()), "pace": "", "cue": "", "phase": "pace", "turn": -1}, true)
	if _log():
		print("[Games] sortija %s: %d jinetes, anillas %s, jugador %d" % [id, players.size(), rings, player])
	m._advance()
	return m


func pace_cfg(p: String) -> Dictionary:
	return (sec().get("paces", {}) as Dictionary).get(p, {})


func ring() -> String:
	return str((d["rings"] as Array)[mini(int(d["run"]), (d["rings"] as Array).size() - 1)])


func dex(k: int) -> int:
	return GameRules.stat(player_of(k), "dexterity") - 3


func read_chance(k: int, pace: String) -> float:
	var r: Dictionary = sec().get("read", {})
	return clampf(float(pace_cfg(pace).get("read", 0.7)) + dex(k) * float(r.get("step", 0.03)),
		float(r.get("min", 0.34)), float(r.get("max", 0.95)))


func hit_threshold(k: int, pace: String) -> int:
	return int(pace_cfg(pace).get("window", 65)) + int((sec().get("rings", {}) as Dictionary).get(ring(), 0)) \
		+ dex(k) * int(sec().get("hit_step", 5))


## The expected points of rider k with `pace` (following the sway): points × read × chance of the hit.
func expected(k: int, pace: String) -> float:
	return float(pace_cfg(pace).get("points", 1)) * read_chance(k, pace) * GameRules.pass_chance(cfg, hit_threshold(k, pace))


## The right moment of rider k this run (keyed).
func right_moment(k: int) -> String:
	return GameRules.pick(MOMENTS, match_seed(), id(), int(d["run"]) * 10 + k, "moment")


func ai_pace(k: int) -> String:
	var best := ""
	var bv := -1.0
	for p: String in PACES:
		var v := expected(k, p)
		if v > bv + 0.0001:
			bv = v
			best = p
	var last := int(d["run"]) >= int(sec().get("runs", 3)) - 1
	if not last:
		return best
	# the last run, behind: the pace with the best chance of passing the leader (the others' last runs at their mean)
	var pts: Array = d["points"]
	var lead := -1.0
	for j: int in n_players():
		if j == k:
			continue
		var final := float(pts[j]) + (expected(j, ai_pace_ev(j)) if _still_to_run(j) else 0.0)
		lead = maxf(lead, final)
	var need := lead - float(pts[k])
	if need < 0.0:
		return best
	var bp := best
	var bchance := -1.0
	for p: String in PACES:
		var gain := float(pace_cfg(p).get("points", 1))
		var ch := (read_chance(k, p) * GameRules.pass_chance(cfg, hit_threshold(k, p))) if gain > need else 0.0
		if ch > bchance + 0.0001:
			bchance = ch
			bp = p
	return bp if bchance > 0.0 else best


func ai_pace_ev(k: int) -> String:
	var best := "firm"
	var bv := -1.0
	for p: String in PACES:
		var v := expected(k, p)
		if v > bv:
			bv = v
			best = p
	return best


func _still_to_run(j: int) -> bool:
	return j >= int(d["rider"])


func _view(side: int) -> Dictionary:
	var acts: Array = []
	var ph := str(d["phase"])
	if not over() and int(d["turn"]) == side:
		if ph == "pace":
			for p: String in PACES:
				acts.append({"id": p, "enabled": true})
		else:
			for mo: String in MOMENTS:
				acts.append({"id": mo, "enabled": true})
	var ex := {}
	if side >= 0:
		for p: String in PACES:
			ex[p] = expected(side, p)
			ex[p + "_hit"] = GameRules.pass_chance(cfg, hit_threshold(side, p))
			ex[p + "_read"] = read_chance(side, p)
	var v := {"actions": acts, "run": int(d["run"]), "rider": int(d["rider"]), "ring": ring(),
		"points": (d["points"] as Array).duplicate(), "hits": (d["hits"] as Array).duplicate(), "expected": ex,
		"pace": str(d["pace"]), "cue": {}, "prompt": "games.sortija.prompt.%s" % ph if acts.size() > 0 else ""}
	if ph == "moment" and int(d["turn"]) == side:
		v["cue"] = {"text": "games.sortija.cue.%s" % str(d["cue"]), "id": str(d["cue"]), "read": read_chance(side, str(d["pace"]))}
	return v


func _choose(side: int, action: String) -> Dictionary:
	if str(d["phase"]) == "pace":
		d["pace"] = action
		d["cue"] = GameRules.cue(read_chance(side, action), right_moment(side), MOMENTS, match_seed(), id(),
			int(d["run"]) * 10 + side, "sway")
		d["phase"] = "moment"
	else:
		_ride(side, str(d["pace"]), action)
	return {"ok": true, "reason": ""}


func _ride(k: int, pace: String, moment: String) -> void:
	var run := int(d["run"])
	var right := right_moment(k)
	var hit := false
	var roll := 0
	if moment == right:
		var r := GameRules.check(cfg, hit_threshold(k, pace), match_seed(), id(), run * 10 + k, "hit")
		hit = bool(r["success"])
		roll = int(r["roll"])
	var got := int(pace_cfg(pace).get("points", 1)) if hit else 0
	var pts: Array = d["points"]
	pts[k] = int(pts[k]) + got
	if hit:
		(d["hits"] as Array)[k] = int((d["hits"] as Array)[k]) + 1
	var rec := {"kind": "run", "run": run, "rider": k, "ring": ring(), "pace": pace, "moment": moment, "right": right,
		"cue": str(d["cue"]), "hit": hit, "got": got, "points": pts.duplicate(), "roll": roll}
	(d["log"] as Array).append(rec)
	if _log():
		print("[Games] sortija %s: carrera %d, %d a %s baja en %s (era %s) -> %s, puntos %s" % [id(), run + 1, k, pace, moment,
			right, "ENSARTA" if hit else "falla", pts])
	d["pace"] = ""
	d["cue"] = ""
	d["phase"] = "pace"
	d["rider"] = int(d["rider"]) + 1
	if int(d["rider"]) >= n_players():
		d["rider"] = 0
		d["run"] = run + 1


func _advance() -> void:
	var guard := 0
	while not over() and guard < 64:
		guard += 1
		if int(d["run"]) >= int(sec().get("runs", 3)):
			_end()
			return
		var k := int(d["rider"])
		if plays(k):
			d["turn"] = k
			return
		d["turn"] = -1
		var pace := ai_pace(k)
		d["cue"] = GameRules.cue(read_chance(k, pace), right_moment(k), MOMENTS, match_seed(), id(), int(d["run"]) * 10 + k, "sway")
		_ride(k, pace, str(d["cue"]))


func _end() -> void:
	var pts: Array = d["points"]
	var hits: Array = d["hits"]
	var order: Array = []
	for i: int in n_players():
		order.append(i)
	var tie_roll := {}
	for i: int in n_players():
		tie_roll[i] = GameRules.roll(match_seed(), id(), 99, "tie|%d" % i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(pts[a]) != int(pts[b]):
			return int(pts[a]) > int(pts[b])
		if int(hits[a]) != int(hits[b]):
			return int(hits[a]) > int(hits[b])
		return float(tie_roll[a]) > float(tie_roll[b]))
	d["ranking"] = order
	d["scores"] = pts.duplicate()
	var w := int(order[0])
	var s := int(d["stake"])
	if s > 0:
		var net: Array = d["net"]
		for i: int in n_players():
			net[i] = -s
		net[w] = s * (n_players() - 1)
	_finish(w, "points")


func _ai_move(side: int) -> String:
	if str(d["phase"]) == "pace":
		return ai_pace(side)
	return str(d["cue"])
