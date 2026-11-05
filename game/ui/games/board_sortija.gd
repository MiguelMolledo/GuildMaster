class_name BoardSortija
extends GameBoard
## Correr la sortija (docs/ui/mecanicas/juegos.md §Sortija; rules: SortijaMatch): the lane with its three signal posts
## and the ring hung over it (large, medium or small this run), the rider galloping from the left, and the scoreboard
## of every rider (points and rings by run). A run is animated: the rider crosses, lowers the lance at the post he
## chose, and the ring is threaded or swings away.

const POSTS: Dictionary = {"first": 0.3, "second": 0.5, "third": 0.7}

var _shown: int = 0
var _rec: Dictionary = {}
var _k: float = 0.0


func reset() -> void:
	super.reset()
	_shown = 0
	_rec = {}


func new_entries(match_: GameMatch) -> Array:
	var lg := match_.log_entries()
	var out: Array = []
	for i: int in range(_shown, lg.size()):
		out.append(lg[i])
	_shown = lg.size()
	_step_time = 0.9 if out.size() <= 2 else 0.45
	return out


func _start_entry(e: Dictionary) -> void:
	_rec = e
	_k = 0.0


func _animate(k: float) -> void:
	_k = k


func _end_entry(_e: Dictionary) -> void:
	_rec = {}


func _draw() -> void:
	missing.clear()
	art_or_box("sortija", "lane", Rect2(Vector2.ZERO, size), Color(0.4, 0.38, 0.26), tr("games.ui.art_missing") % "sortija/lane")
	if m == null:
		return
	var sm := m as SortijaMatch
	var lane_y := 96.0
	var lx := 150.0
	var lw := size.x - lx - 12.0
	draw_line(Vector2(lx, lane_y + 22), Vector2(lx + lw, lane_y + 22), Color(0.55, 0.42, 0.28), 3.0)
	for mo: String in POSTS:
		var px := lx + lw * float(POSTS[mo])
		draw_line(Vector2(px, lane_y - 6), Vector2(px, lane_y + 22), Color(0.3, 0.22, 0.14), 2.0)
		text(Vector2(px, lane_y + 36), tr("games.sortija.moment.%s" % mo), DIM, 8, -1.0, HORIZONTAL_ALIGNMENT_CENTER)
	# the ring over the lane, its size this run
	var ring := str(_rec.get("ring", sm.ring())) if playing else sm.ring()
	var rr := {"large": 9.0, "medium": 6.0, "small": 4.0}.get(ring, 6.0) as float
	var ring_x := lx + lw * 0.5
	draw_line(Vector2(ring_x, 20), Vector2(ring_x, lane_y - 30), Color(0.25, 0.2, 0.15), 1.0)
	var hit := playing and bool(_rec.get("hit", false)) and _k > 0.6
	var ring_at := Vector2(ring_x, lane_y - 30 + rr)
	if playing and not bool(_rec.get("hit", false)) and _k > 0.6:
		ring_at.x += sin(_k * 20.0) * 6.0
	if not hit:
		draw_arc(ring_at, rr, 0.0, TAU, 20, GOLD, 2.0)
	text(Vector2(ring_x, 16), tr("games.sortija.ring.%s" % ring), INK, 8, -1.0, HORIZONTAL_ALIGNMENT_CENTER)
	# the rider of the run being shown
	if playing and not _rec.is_empty():
		var x := lerpf(lx - 10.0, lx + lw + 10.0, _k)
		var y := lane_y
		draw_rect(Rect2(Vector2(x - 16, y), Vector2(32, 12)), Color(0.42, 0.3, 0.2))
		draw_rect(Rect2(Vector2(x - 4, y - 18), Vector2(8, 18)), GOLD if int(_rec["rider"]) == me else Color(0.55, 0.6, 0.75))
		var lowered := _k >= float(POSTS.get(str(_rec["moment"]), 0.5)) - 0.05
		var tip := Vector2(x + 30, y - 30 + (rr if lowered else -14.0))
		draw_line(Vector2(x, y - 12), tip, Color(0.85, 0.8, 0.6), 2.0)
		if hit:
			draw_arc(tip, rr, 0.0, TAU, 20, GOLD, 2.0)
		if _k > 0.7:
			text(Vector2(ring_x, lane_y + 54), tr("games.sortija.ui.threaded") % int(_rec["got"]) if bool(_rec["hit"])
				else tr("games.sortija.ui.missed"), GOLD if bool(_rec["hit"]) else INK, 16, -1.0, HORIZONTAL_ALIGNMENT_CENTER)
	# the scoreboard (what has been shown)
	var done := _shown - (_queue.size() + (1 if playing else 0))
	var lg := m.log_entries()
	var pts: Array = (lg[done - 1]["points"] as Array) if done > 0 else GameMatch._zeros(m.n_players())
	for j: int in m.n_players():
		var y2 := 14.0 + j * 18.0
		text(Vector2(8, y2 + 8), _short(who(j)), GOLD if j == me else INK, 8)
		text(Vector2(142, y2 + 8), str(int(pts[j])), GOLD if j == me else INK, 8, -1.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var run := int(_rec.get("run", int(v.get("run", 0)))) if playing else int(v.get("run", 0))
	text(Vector2(8, 22.0 + m.n_players() * 18.0), tr("games.sortija.ui.run") % [mini(run + 1, 3), 3], DIM, 8)


func _short(n: String) -> String:
	return n if n.length() <= 17 else n.substr(0, 16) + "…"


func info_busy() -> Dictionary:
	return {"title": tr("games.sortija.ui.riding"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": "", "read": ""}
	var ph := str(view.get("phase", ""))
	var ex: Dictionary = view.get("expected", {})
	if ph == "pace":
		var parts: Array[String] = []
		for p: String in SortijaMatch.PACES:
			parts.append(tr("games.sortija.ui.pace_value") % [tr("games.sortija.action.%s" % p), float(ex.get(p, 0.0)),
				roundi(float(ex.get(p + "_hit", 0.0)) * 100.0), roundi(float(ex.get(p + "_read", 0.0)) * 10.0)])
		return {"title": tr("games.sortija.prompt.pace") + " · " + tr("games.sortija.ring.%s" % str(view.get("ring", ""))),
			"text": " · ".join(parts), "read": tr("games.sortija.ui.ev_note")}
	var cue: Dictionary = view.get("cue", {})
	return {"title": tr("games.sortija.prompt.moment"), "text": tr(str(cue.get("text", ""))),
		"read": tr("games.ui.reliable") % roundi(float(cue.get("read", 0.0)) * 10.0)}


func log_line(e: Dictionary) -> String:
	return tr("games.sortija.ui.log") % [int(e["run"]) + 1, who(int(e["rider"])), tr("games.sortija.action.%s" % str(e["pace"])),
		tr("games.sortija.ui.threaded") % int(e["got"]) if bool(e["hit"]) else tr("games.sortija.ui.missed")]
