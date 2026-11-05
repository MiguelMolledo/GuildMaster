class_name BoardBulls
extends GameBoard
## Correr el toro (docs/ui/mecanicas/juegos.md §Toros; rules: BullsMatch): the plaza closed with carts, the bull and
## the mozo whose turn it is, and the applause of each mozo. A charge is animated: the bull goes for him and he cites,
## breaks away or gets behind the carts; what came of it comes up («¡Quiebro! +2», «¡Susto!»).

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
	_step_time = 0.8 if out.size() <= 3 else 0.4
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
	art_or_box("bulls", "plaza", Rect2(Vector2.ZERO, size), Color(0.55, 0.46, 0.32), tr("games.ui.art_missing") % "bulls/plaza")
	if m == null:
		return
	var c := Vector2(size.x * 0.62, size.y * 0.52)
	draw_arc(c, 74.0, 0.0, TAU, 40, Color(0.35, 0.24, 0.14), 4.0)  # the ring of carts
	for i: int in 10:
		var a := TAU * i / 10.0
		draw_rect(Rect2(c + Vector2(cos(a), sin(a)) * 74.0 - Vector2(6, 4), Vector2(12, 8)), Color(0.4, 0.28, 0.16))
	var k := _k if playing else 0.0
	var mozo := c + Vector2(30, 10)
	var bull_from := c + Vector2(-60, -10)
	var bull_at := bull_from.lerp(mozo + Vector2(-8, 0), minf(1.0, k * 1.6))
	var act := str(_rec.get("action", "")) if playing else ""
	if act == "break" and k > 0.55:
		mozo += Vector2(0, -16)
	elif act == "safe" and k > 0.3:
		mozo = mozo.lerp(c + Vector2(60, 40), minf(1.0, (k - 0.3) * 2.0))
	var bt := VisualPaths.game_art("bulls", "bull")
	if bt != null:
		draw_texture_rect(bt, Rect2(bull_at - Vector2(18, 12), Vector2(36, 24)), false)
	else:
		if not "bulls/bull" in missing:
			missing.append("bulls/bull")
		draw_rect(Rect2(bull_at - Vector2(16, 8), Vector2(32, 14)), Color(0.12, 0.08, 0.06))
		draw_line(bull_at + Vector2(14, -6), bull_at + Vector2(22, -12), Color(0.9, 0.88, 0.8), 2.0)
	var who_k := int(_rec.get("mozo", int(v.get("mozo", 0)))) if playing else int(v.get("mozo", 0))
	draw_rect(Rect2(mozo - Vector2(4, 16), Vector2(8, 16)), GOLD if who_k == me else Color(0.55, 0.6, 0.75))
	draw_circle(mozo - Vector2(0, 20), 4.0, Color(0.85, 0.7, 0.55))
	if playing and k > 0.6:
		var got := float(_rec["got"])
		var word := tr("games.bulls.ui.got.%s" % ("good" if got > 0.0 else ("safe" if got == 0.0 else "fail"))) % \
			[tr("games.bulls.action.%s" % act), _pts(got)]
		text(Vector2(c.x, 22), word, GOLD if got > 0.0 else (INK if got == 0.0 else RED.lightened(0.3)), 16, -1.0,
			HORIZONTAL_ALIGNMENT_CENTER)
	# the applause so far
	var done := _shown - (_queue.size() + (1 if playing else 0))
	var lg := m.log_entries()
	var pts: Array = (lg[done - 1]["points"] as Array) if done > 0 else GameMatch._zeros(m.n_players())
	for j: int in m.n_players():
		text(Vector2(8, 18 + j * 18), "%s  %s" % [_short(who(j)), _pts(float(pts[j]))], GOLD if j == me else INK, 8)
	var ch := int(_rec.get("charge", int(v.get("charge", 0)))) if playing else int(v.get("charge", 0))
	text(Vector2(8, size.y - 22), tr("games.bulls.ui.charge") % [mini(ch + 1, 3), 3], DIM, 8)
	text(Vector2(8, size.y - 10), tr("games.bulls.bull.%s" % str(m.d["bull"])), DIM, 8)


func _pts(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x


func _short(n: String) -> String:
	return n if n.length() <= 17 else n.substr(0, 16) + "…"


func info_busy() -> Dictionary:
	return {"title": tr("games.bulls.ui.charging"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": "", "read": ""}
	var cue: Dictionary = view.get("cue", {})
	var o: Dictionary = view.get("odds", {})
	var ex: Dictionary = view.get("expected", {})
	var txt := tr(str(cue.get("text", ""))) + "  " + tr("games.bulls.ui.odds") % [roundi(float(o.get("charge", 0.0)) * 100.0),
		roundi(float(o.get("feint", 0.0)) * 100.0), roundi(float(o.get("hook", 0.0)) * 100.0)]
	var rd := tr("games.ui.reliable") % roundi(float(cue.get("read", 0.0)) * 10.0) + "  ·  " + tr("games.bulls.ui.expected") % [
		float(ex.get("cite", 0.0)), float(ex.get("break", 0.0)), float(ex.get("safe", 0.0))]
	return {"title": tr("games.bulls.prompt"), "text": txt, "read": rd}


func log_line(e: Dictionary) -> String:
	if int(e["mozo"]) != me:
		return ""
	return tr("games.bulls.ui.log") % [int(e["charge"]) + 1, tr("games.bulls.action.%s" % str(e["action"])),
		tr("games.bulls.what.%s" % str(e["bull"])), _pts(float(e["got"]))]
