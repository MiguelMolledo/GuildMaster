class_name BoardDice
extends GameBoard
## The dice table (docs/ui/mecanicas/juegos.md §Dados): «azar» (AzarMatch) and «tres dados a la mayor» (MayorMatch).
## Azar: the last throw big in the middle, the earlier ones small below, each side's chance and the stake. A la mayor:
## a row per player with his three dice (the one under the cup hidden until the end), what he decided and the winner.
## The throws come in one by one (play); a long run of throws goes faster.

var _shown_throws: int = 0
var _shown_end: bool = false
var _rolling: Array = []      # the dice of the throw being animated
var _final: Array = []


func reset() -> void:
	super.reset()
	_shown_throws = 0
	_shown_end = false
	_rolling = []


func new_entries(match_: GameMatch) -> Array:
	var out: Array = []
	if match_ is AzarMatch:
		var th: Array = match_.d["throws"]
		for i: int in range(_shown_throws, th.size()):
			out.append({"kind": "throw", "i": i, "dice": th[i]["dice"], "total": th[i]["total"]})
		_shown_throws = th.size()
		_step_time = 0.35 if out.size() <= 4 else 0.16
	elif match_ is MayorMatch:
		if not _shown_end and match_.over():
			out.append({"kind": "reveal"})
			_shown_end = true
		_step_time = 0.6
	return out


func _start_entry(e: Dictionary) -> void:
	if str(e["kind"]) == "throw":
		_final = e["dice"]
		_rolling = _final.duplicate()


func _animate(k: float) -> void:
	if _rolling.is_empty():
		return
	if k < 0.7:
		for i: int in _rolling.size():
			_rolling[i] = 1 + (int(k * 40.0) + i * 3) % 6
	else:
		_rolling = _final.duplicate()


func _end_entry(_e: Dictionary) -> void:
	_rolling = []


func _draw() -> void:
	missing.clear()
	art_or_box("dice", "table", Rect2(Vector2.ZERO, size), FELT, tr("games.ui.art_missing") % "dice/table")
	if m == null:
		return
	if m is AzarMatch:
		_draw_azar()
	elif m is MayorMatch:
		_draw_mayor()


func _draw_azar() -> void:
	var th: Array = v.get("throws", [])
	var shown := mini(th.size(), _shown_throws - (1 if playing else 0))
	var thr := int(v.get("thrower", 0))
	var w := size.x
	text(Vector2(8, 18), tr("games.azar.ui.thrower") % who(thr), INK, 16)
	text(Vector2(w - 8, 18), tr("games.ui.stake_now") % int(v.get("stake_now", 0)), GOLD, 16, -1.0,
		HORIZONTAL_ALIGNMENT_RIGHT)
	# the chances of each side as far as the throws shown tell them (left: me, right: the rival)
	var known := _chances_shown(th, shown, thr)
	for s: int in 2:
		var right := s != me
		var x := w - 10.0 if right else 10.0
		var al := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		var c := int(known[s])
		text(Vector2(x, 40), tr("games.azar.ui.chance") % who(s), DIM, 8, -1.0, al)
		text(Vector2(x, 70), str(c) if c > 0 else "—", GOLD if c > 0 else DIM, 32, -1.0, al)
	# the throw in the middle
	var cur: Array = _rolling if playing and not _rolling.is_empty() else ((th[shown - 1]["dice"] as Array) if shown > 0 else [])
	var side := 30.0
	var x0 := w / 2.0 - (side * 3 + 16) / 2.0
	for i: int in cur.size():
		die(Vector2(x0 + i * (side + 8), 62), int(cur[i]), side)
	if not cur.is_empty() and not (playing and _t / _step_time < 0.7):
		var t := GameRules.total(cur)
		var hot := t in [int(known[0]), int(known[1])] and int(known[0]) > 0 and int(known[1]) > 0
		text(Vector2(0, 116), tr("games.azar.ui.total") % t, GOLD if hot else INK, 16, w, HORIZONTAL_ALIGNMENT_CENTER)
	# the earlier throws, small
	var y := 134.0
	var xs := 10.0
	var first := maxi(0, shown - 1 - 12)
	for i: int in range(first, maxi(0, shown - 1)):
		var tt := int(th[i]["total"])
		text(Vector2(xs, y + 26), str(tt), INK if tt in [int(known[0]), int(known[1])] else DIM, 16)
		xs += 28.0
	if shown > 1:
		text(Vector2(10, y + 8), tr("games.azar.ui.earlier"), DIM, 8)


## The chances [side 0, side 1] that the first `shown` throws have set (0 = not yet).
func _chances_shown(th: Array, shown: int, thr: int) -> Array:
	var out: Array = [0, 0]
	var am := m as AzarMatch
	for i: int in shown:
		var t := int(th[i]["total"])
		if i == 0:
			if not am.is_azar(t):
				out[1 - thr] = t
		elif int(out[thr]) == 0 and not am.is_azar(t) and t != int(out[1 - thr]):
			out[thr] = t
	return out


func _draw_mayor() -> void:
	var dice: Array = v.get("dice", [])
	var dec: Array = v.get("decisions", [])
	var n := dice.size()
	var row := minf(40.0, (size.y - 16.0) / maxf(1.0, n))
	var revealed := m.over() and _shown_end and not playing
	var ranking: Array = m.d.get("ranking", []) if revealed else []
	for j: int in n:
		var y := 8.0 + j * row
		var hot := not ranking.is_empty() and j == int(ranking[0]) and int(m.d["winner"]) >= 0
		draw_rect(Rect2(6, y, size.x - 12, row - 4), Color(0, 0, 0, 0.18 if j != me else 0.32))
		if hot:
			draw_rect(Rect2(6, y, size.x - 12, row - 4), GOLD, false, 1.0)
		text(Vector2(12, y + row * 0.5 + 4), who(j), GOLD if j == me else INK, 16)
		var th: Array = (dice[j] as Array).duplicate()
		if not revealed and j != me and m.over():  # the cups are lifted when the reveal is shown
			for i: int in range((m as MayorMatch).hidden_n()):
				th[th.size() - 1 - i] = 0
		for i: int in th.size():
			var hidden := int(th[i]) == 0
			die(Vector2(150 + i * 26, y + (row - 4) / 2.0 - 10), int(th[i]), 20.0, false)
			if hidden and j != me:
				pass
		var tot := GameRules.total(th)
		var known := true
		for x: Variant in th:
			known = known and int(x) > 0
		text(Vector2(236, y + row * 0.5 + 4), (tr("games.azar.ui.total") % tot) if known else (tr("games.mayor.ui.shows") % tot),
			INK if known else DIM, 16)
		var dj := str(dec[j]) if j < dec.size() else ""
		if revealed:
			dj = str((m.d["decisions"] as Array)[j])
		if dj != "":
			text(Vector2(size.x - 12, y + row * 0.5 + 4), tr("games.mayor.action.%s" % dj), GREEN.lightened(0.3) if dj == "stay" else RED.lightened(0.3), 16,
				-1.0, HORIZONTAL_ALIGNMENT_RIGHT)


func info_busy() -> Dictionary:
	return {"title": tr("games.azar.ui.rolling"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if m is AzarMatch:
		var ph := str(view.get("phase", ""))
		var p := float(view.get("win", 0.5))
		if bool(view.get("over", false)):
			return {"title": tr("games.ui.over"), "text": tr("games.azar.how.%s" % str(m.d["how"])), "read": ""}
		if ph == "offer":
			return {"title": tr("games.azar.prompt.offer"), "text": tr("games.azar.ui.odds") % [roundi(p * 100.0),
				roundi(float(view["double_at"]) * 100.0)], "read": tr("games.ui.ev") % [float(view["ev_keep"]), float(view["ev_double"])]}
		if ph == "answer":
			return {"title": tr("games.azar.prompt.answer") % who(1 - me), "text": tr("games.azar.ui.odds_answer") % [
				roundi(p * 100.0), roundi(float(view["accept_at"]) * 100.0)], "read": tr("games.azar.ui.refuse_cost") % int(view["stake_now"])}
		return {"title": tr("games.azar.ui.rolling"), "text": tr("games.azar.rules"), "read": ""}
	if m is MayorMatch:
		if bool(view.get("over", false)):
			return {"title": tr("games.ui.over"), "text": tr("games.mayor.how.%s" % str(m.d["how"])), "read": ""}
		return {"title": tr("games.mayor.prompt"), "text": tr("games.mayor.ui.odds") % roundi(float(view.get("share", 0.0)) * 100.0),
			"read": tr("games.mayor.ui.ev") % [float(view.get("ev_stay", 0.0)), float(view.get("ev_retire", 0.0))]}
	return super.info(view)
