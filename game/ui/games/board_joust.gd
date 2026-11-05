class_name BoardJoust
extends GameBoard
## The lists of the joust (docs/ui/mecanicas/juegos.md §Justa; rules: JoustMatch): the tilt (the barrier) across the
## middle, the two riders at each end with their lances, the points of each and the pass. A pass is animated: they
## charge, meet at the tilt, and what each lance did comes up over the rider it hit («¡Al pecho! +2», «medio punto»,
## «¡Desmontado!»). The horses and riders are greybox until the art (assets/art/ui/games/joust/) arrives.

var _shown: int = 0
var _rec: Dictionary = {}
var _k: float = 0.0


func reset() -> void:
	super.reset()
	_shown = 0
	_rec = {}


func new_entries(match_: GameMatch) -> Array:
	var lg := match_.log_entries()
	var out: Array = lg.slice(_shown)
	_shown = lg.size()
	_step_time = 1.0
	return out


func _start_entry(e: Dictionary) -> void:
	_rec = e
	_k = 0.0


func _animate(k: float) -> void:
	_k = k


func _end_entry(_e: Dictionary) -> void:
	_rec = {}


func _rider(x: float, facing: float, side: int, fallen: bool) -> void:
	var y := size.y * 0.55
	var horse := VisualPaths.game_art("joust", "horse")
	if horse != null:
		var r := Rect2(Vector2(x - 24, y - 20), Vector2(48, 32))
		draw_texture_rect(horse, r if facing > 0 else Rect2(r.position + Vector2(r.size.x, 0), Vector2(-r.size.x, r.size.y)), false)
	else:
		if not "joust/horse" in missing:
			missing.append("joust/horse")
		draw_rect(Rect2(Vector2(x - 22, y - 10), Vector2(44, 16)), Color(0.42, 0.3, 0.2))
		draw_rect(Rect2(Vector2(x + 14 * facing - 5, y - 18), Vector2(10, 10)), Color(0.42, 0.3, 0.2))
		for lx: float in [-16.0, -8.0, 8.0, 16.0]:
			draw_line(Vector2(x + lx, y + 6), Vector2(x + lx, y + 18), Color(0.3, 0.2, 0.12), 3.0)
	var col := GOLD if side == me else Color(0.55, 0.6, 0.75)
	if fallen:
		draw_rect(Rect2(Vector2(x - 6 - 18 * facing, y + 10), Vector2(18, 8)), col)
		return
	draw_rect(Rect2(Vector2(x - 5, y - 30), Vector2(10, 20)), col)
	draw_circle(Vector2(x, y - 34), 5.0, Color(0.75, 0.75, 0.78))
	draw_line(Vector2(x, y - 22), Vector2(x + 44 * facing, y - 30), Color(0.85, 0.8, 0.6), 2.0)


func _draw() -> void:
	missing.clear()
	art_or_box("joust", "lists", Rect2(Vector2.ZERO, size), Color(0.36, 0.42, 0.26), tr("games.ui.art_missing") % "joust/lists")
	if m == null:
		return
	# the tilt
	draw_rect(Rect2(Vector2(20, size.y * 0.55 + 20), Vector2(size.x - 40, 5)), Color(0.55, 0.3, 0.18))
	var done := _shown - (_queue.size() + (1 if playing else 0))
	var lg := m.log_entries()
	var pts: Array = (lg[done - 1]["points"] as Array) if done > 0 else [0.0, 0.0]
	var other := 1 - me
	var k := _k if playing else 0.0
	var meet := minf(1.0, k * 1.6)
	var left_x := lerpf(40.0, size.x / 2.0 - 30.0, meet)
	var right_x := lerpf(size.x - 40.0, size.x / 2.0 + 30.0, meet)
	var un := int(_rec.get("unhorsed", -1)) if playing and k > 0.65 else -1
	if not playing and m.over() and str(m.d["how"]) == "unhorsed":
		un = int((m.d["facts"] as Array).back().get("side", -1)) if not (m.d["facts"] as Array).is_empty() else -1
	_rider(left_x, 1.0, me, un == me)
	_rider(right_x, -1.0, other, un == other)
	text(Vector2(10, 18), who(me), GOLD, 16)
	text(Vector2(size.x - 10, 18), who(other), INK, 16, -1.0, HORIZONTAL_ALIGNMENT_RIGHT)
	text(Vector2(10, 34), tr("games.joust.ui.points") + " " + _pts(float(pts[me])), INK, 8)
	text(Vector2(size.x - 10, 34), tr("games.joust.ui.points") + " " + _pts(float(pts[other])), INK, 8, -1.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var ps := int(_rec.get("pass", int(v.get("pass", 0)))) if playing else int(v.get("pass", 0))
	text(Vector2(0, 18), tr("games.joust.ui.pass") % (ps + 1), DIM, 8, size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if playing and k > 0.6:
		var got: Array = _rec["got"]
		var aims: Array = _rec["stances"]
		for s: int in [0, 1]:
			var x := size.x / 2.0 + (-70.0 if s == other else 70.0)
			var word := tr("games.joust.ui.hit") % [tr("games.joust.aim.%s" % (m as JoustMatch).aim_of(str(aims[s]))), _pts(float(got[s]))]
			if int(_rec.get("unhorsed", -1)) == 1 - s:
				word = tr("games.joust.how.unhorsed")
			text(Vector2(x, size.y * 0.25), word, GOLD if s == me else INK, 16, -1.0, HORIZONTAL_ALIGNMENT_CENTER)



func _pts(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x


func info_busy() -> Dictionary:
	return {"title": tr("games.joust.ui.charge"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": tr("games.joust.how.%s" % str(m.d["how"])), "read": ""}
	var cue: Dictionary = view.get("cue", {})
	var h: Dictionary = view.get("hits", {})
	var hits := tr("games.joust.ui.blind_text") % [roundi(float(h.get("helm", 0.0)) * 100.0),
		roundi(float(h.get("chest", 0.0)) * 100.0), roundi(float(h.get("shield", 0.0)) * 100.0)]
	match str(view.get("role", "blind")):
		"read":
			return {"title": tr("games.joust.prompt.read") % who(1 - me), "text": tr(str(cue.get("text", ""))) + "  " + hits,
				"read": tr("games.ui.reliable") % roundi(float(cue.get("read", 0.0)) * 10.0)}
		"lead":
			return {"title": tr("games.joust.prompt.lead"), "text": tr("games.joust.ui.lead_text") % who(1 - me) + "  " + hits,
				"read": tr("games.ui.read_by") % [who(1 - me), roundi(float(view.get("read_by", 0.0)) * 10.0)]}
	return {"title": tr("games.joust.prompt.blind"), "text": hits, "read": ""}


func log_line(e: Dictionary) -> String:
	var a: Array = e["stances"]
	var p: Array = e["points"]
	var o := 1 - me
	return tr("games.joust.ui.log") % [int(e["pass"]) + 1, tr("games.joust.action.%s" % str(a[me])),
		tr("games.joust.action.%s" % str(a[o])), _pts(float(p[me])), _pts(float(p[o]))]
