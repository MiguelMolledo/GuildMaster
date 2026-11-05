class_name BoardRace
extends GameBoard
## The horse race (docs/ui/mecanicas/juegos.md §Carrera; rules: RaceMatch): one lane per rider across the board, the
## four stretches marked (the start, the straight, the mill's bend, the finish), each horse where its distance puts it,
## and under its name the wind it has left. A stretch is animated: the horses move on together; who stumbled in the
## bend says so.

var _shown: int = 0
var _rec: Dictionary = {}
var _prev: Array = []
var _k: float = 0.0


func reset() -> void:
	super.reset()
	_shown = 0
	_rec = {}
	_prev = []


func new_entries(match_: GameMatch) -> Array:
	var lg := match_.log_entries()
	var out: Array = lg.slice(_shown)
	_shown = lg.size()
	_step_time = 0.8
	return out


func _start_entry(e: Dictionary) -> void:
	_rec = e
	_k = 0.0
	var lg := m.log_entries()
	var i := lg.find(e)
	_prev = (lg[i - 1]["dist"] as Array) if i > 0 else GameMatch._zeros(m.n_players())


func _animate(k: float) -> void:
	_k = k


func _end_entry(_e: Dictionary) -> void:
	_rec = {}


func _draw() -> void:
	missing.clear()
	art_or_box("race", "track", Rect2(Vector2.ZERO, size), Color(0.42, 0.36, 0.24), tr("games.ui.art_missing") % "race/track")
	if m == null:
		return
	var rm := m as RaceMatch
	var n := m.n_players()
	var x0 := 118.0
	var x1 := size.x - 14.0
	var full := 0.0
	for k: int in n:
		full = maxf(full, float(rm.horse(k).get("speed", 10.0)))
	full *= float(rm.stretches().size()) * 1.25
	var sts := rm.stretches()
	for i: int in sts.size() + 1:
		var x := lerpf(x0, x1, float(i) / sts.size())
		draw_line(Vector2(x, 10), Vector2(x, size.y - 22), Color(0.3, 0.24, 0.16), 1.0)
		if i < sts.size():
			var seg := (x1 - x0) / sts.size()
			var lab := tr("games.race.stretch.%s" % str(sts[i]))
			if lab.length() > 10:
				lab = lab.substr(0, 9) + "…"
			text(Vector2(x + seg / 2.0, size.y - 10), lab, DIM, 8, -1.0, HORIZONTAL_ALIGNMENT_CENTER)
	var done := _shown - (_queue.size() + (1 if playing else 0))
	var lg := m.log_entries()
	var dist: Array = (lg[done - 1]["dist"] as Array) if done > 0 else GameMatch._zeros(n)
	var wind: Array = (lg[done - 1]["wind"] as Array) if done > 0 else []
	if wind.is_empty():
		for k: int in n:
			wind.append(int(rm.horse(k).get("wind", 6)))
	var lane := minf(34.0, (size.y - 34.0) / maxf(1.0, n))
	for k: int in n:
		var y := 12.0 + k * lane
		var dd := float(dist[k])
		if playing and not _rec.is_empty():
			dd = lerpf(float(_prev[k]), float((_rec["dist"] as Array)[k]), _k)
		var x := lerpf(x0, x1, clampf(dd / full * (float(sts.size()) / sts.size()), 0.0, 1.0) if full > 0.0 else 0.0)
		x = lerpf(x0, x1, clampf(dd / (full / 1.25), 0.0, 1.0))
		text(Vector2(6, y + 10), _short(who(k)), GOLD if k == me else INK, 8)
		pips(Vector2(6, y + 14), int(wind[k]), int(rm.horse(k).get("wind", 6)), Color(0.36, 0.55, 0.78), 5.0)
		var horse := VisualPaths.game_art("race", "horse")
		var r := Rect2(Vector2(x - 20, y), Vector2(28, 18))
		if horse != null:
			draw_texture_rect(horse, r, false)
		else:
			if not "race/horse" in missing:
				missing.append("race/horse")
			draw_rect(Rect2(Vector2(x - 20, y + 6), Vector2(24, 9)), Color(0.42, 0.3, 0.2))
			draw_rect(Rect2(Vector2(x + 2, y + 1), Vector2(7, 7)), Color(0.42, 0.3, 0.2))
			draw_rect(Rect2(Vector2(x - 12, y - 2), Vector2(6, 9)), GOLD if k == me else Color(0.55, 0.6, 0.75))
		if playing and not _rec.is_empty() and bool((_rec["stumbles"] as Array)[k]) and _k > 0.5:
			text(Vector2(x + 10, y + 8), tr("games.race.ui.stumble"), RED.lightened(0.3), 8)


func _short(n: String) -> String:
	return n if n.length() <= 17 else n.substr(0, 16) + "…"


func info_busy() -> Dictionary:
	return {"title": tr("games.race.ui.running"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": "", "read": ""}
	var sid := str(view.get("stretch_id", ""))
	var g: Dictionary = view.get("gains", {})
	var p: Dictionary = view.get("plans", {})
	var parts: Array[String] = []
	for pc: String in RaceMatch.PACES:
		var tail := tr("games.race.ui.to_finish") % float(p[pc]) if p.has(pc) else tr("games.why.wind")
		parts.append("%s %.1f (%s)" % [tr("games.race.action.%s" % pc), float(g.get(pc, 0.0)), tail])
	var title := tr("games.race.prompt") + " · " + tr("games.race.stretch.%s" % sid)
	var rd := tr("games.race.ui.wind") % [int((view.get("wind", []) as Array)[me]), int((view.get("wind_max", []) as Array)[me])]
	if sid == "bend":
		rd += "  ·  " + tr("games.race.ui.stumble_risk") % roundi(float(view.get("stumble", 0.0)) * 100.0)
	return {"title": title, "text": " · ".join(parts), "read": rd}


func log_line(e: Dictionary) -> String:
	var p: Array = e["paces"]
	var st := tr("games.race.stretch.%s" % str(e["id"]))
	var mine := tr("games.race.action.%s" % str(p[me]))
	if bool((e["stumbles"] as Array)[me]):
		mine += " (" + tr("games.race.ui.stumble") + ")"
	return tr("games.race.ui.log") % [st, mine, _place(e, me)]


func _place(e: Dictionary, k: int) -> int:
	var dist: Array = e["dist"]
	var place := 1
	for j: int in dist.size():
		if j != k and float(dist[j]) > float(dist[k]):
			place += 1
	return place
