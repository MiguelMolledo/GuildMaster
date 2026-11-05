class_name BoardPulso
extends GameBoard
## The arm-wrestling table (docs/ui/mecanicas/juegos.md §Pulso; rules: PulsoMatch): two forearms that meet over the
## table; the clasped hands lean towards whoever is losing the push, and fall onto the table when someone takes it.
## Under each arm, the strength bar (its pips) and the pushes taken. The log tells each push.

var _shown: int = 0
var _lean: float = 0.0        # -1: side 0's hand on the table (side 1 took it), +1: side 1's
var _from: float = 0.0
var _to: float = 0.0
var _rec: Dictionary = {}


func reset() -> void:
	super.reset()
	_shown = 0
	_lean = 0.0
	_rec = {}


func new_entries(match_: GameMatch) -> Array:
	var lg := match_.log_entries()
	var out: Array = lg.slice(_shown)
	_shown = lg.size()
	_step_time = 0.7
	return out


func _start_entry(e: Dictionary) -> void:
	_rec = e
	_from = 0.0
	_to = 1.0 if int(e["winner"]) == 0 else -1.0


func _animate(k: float) -> void:
	# first the struggle (a sway), then the fall to the winner's side
	if k < 0.5:
		_lean = sin(k * 18.0) * 0.18
	else:
		_lean = lerpf(0.0, _to, ease((k - 0.5) * 2.0, 0.4))


func _end_entry(_e: Dictionary) -> void:
	_lean = 0.0


func _draw() -> void:
	missing.clear()
	art_or_box("pulso", "table", Rect2(Vector2.ZERO, size), WOOD, tr("games.ui.art_missing") % "pulso/table")
	if m == null:
		return
	var c := Vector2(size.x / 2.0, size.y * 0.52)
	# the arms: elbows on the table, forearms up to the clasped hands
	var lean := _lean if playing else 0.0
	var hand := c + Vector2(lean * 70.0, -40.0 + absf(lean) * 32.0)
	var e0 := c + Vector2(-80, 28)
	var e1 := c + Vector2(80, 28)
	draw_line(e0, hand, Color(0.78, 0.6, 0.45), 14.0)
	draw_line(e1, hand, Color(0.7, 0.52, 0.38), 14.0)
	draw_circle(hand, 11.0, Color(0.82, 0.64, 0.48))
	draw_circle(e0, 8.0, Color(0.5, 0.36, 0.25))
	draw_circle(e1, 8.0, Color(0.5, 0.36, 0.25))
	draw_line(Vector2(c.x - 150, c.y + 36), Vector2(c.x + 150, c.y + 36), WOOD.lightened(0.25), 3.0)
	var sm: Array = v.get("strength_max", [3, 3])
	# only what has been shown: the figures after the last push animated (during a push, those before it)
	var lg := m.log_entries()
	var done := _shown - (_queue.size() if playing else 0)
	var pts: Array = (lg[done - 1]["points"] as Array) if done > 0 else [0, 0]
	var st: Array = (lg[done - 1]["strength"] as Array) if done > 0 else sm
	for s: int in 2:
		var x := 12.0 if s == 0 else size.x - 100.0
		text(Vector2(x, 18), who(s), GOLD if s == me else INK, 16)
		text(Vector2(x, 34), tr("games.pulso.ui.strength"), DIM, 8)
		pips(Vector2(x, 38), int(st[s]), int(sm[s]), Color(0.36, 0.55, 0.78))
		text(Vector2(x, 60), tr("games.pulso.ui.pushes"), DIM, 8)
		pips(Vector2(x, 64), int(pts[s]), int(m.sec().get("to_win", 2)), GOLD, 9.0)
	if playing and not _rec.is_empty():
		var acts: Array = _rec["actions"]
		text(Vector2(0, size.y - 14), "%s  ·  %s" % [tr("games.pulso.action.%s" % str(acts[0])),
			tr("games.pulso.action.%s" % str(acts[1]))], INK, 16, size.x, HORIZONTAL_ALIGNMENT_CENTER)


func info_busy() -> Dictionary:
	return {"title": tr("games.pulso.ui.pushing"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": "", "read": ""}
	var role := str(view.get("role", "blind"))
	var cue: Dictionary = view.get("cue", {})
	match role:
		"read":
			return {"title": tr("games.pulso.prompt.read") % who(1 - me), "text": tr(str(cue.get("text", ""))),
				"read": tr("games.ui.reliable") % roundi(float(cue.get("read", 0.0)) * 10.0)}
		"lead":
			return {"title": tr("games.pulso.prompt.lead"), "text": tr("games.pulso.ui.lead_text") % who(1 - me),
				"read": tr("games.ui.read_by") % [who(1 - me), roundi(float(view.get("read_by", 0.0)) * 10.0)]}
	return {"title": tr("games.pulso.prompt.blind"), "text": tr("games.pulso.ui.blind_text"), "read": ""}


func log_line(e: Dictionary) -> String:
	var acts: Array = e.get("actions", ["", ""])
	return tr("games.pulso.ui.log") % [int(e["push"]) + 1, tr("games.pulso.action.%s" % str(acts[0])),
		tr("games.pulso.action.%s" % str(acts[1])), who(int(e["winner"]))]
