class_name BoardTourney
extends GameBoard
## The fighting tournament (docs/ui/mecanicas/juegos.md §Torneo; rules: TourneyMatch): on the left the draw of eight,
## with the winners going up to the semi-finals and the final; on the right the bout being fought: both fighters,
## their points (touches) and breath, the round («Asalto 2 de 3 · lance 5») and the actions of the last lance. The
## played side's lances come in one by one (like the duel); the bouts of others, all at once.

var _shown: int = 0
var _bouts_shown: int = 0
var _rec: Dictionary = {}


func reset() -> void:
	super.reset()
	_shown = 0
	_bouts_shown = 0
	_rec = {}


func new_entries(match_: GameMatch) -> Array:
	var lg := match_.log_entries()
	var out: Array = []
	for i: int in range(_shown, lg.size()):
		var e: Dictionary = lg[i]
		# the lances of the played side's bouts are animated; the others' bouts just appear
		if str(e["kind"]) == "lance" and 0 in (e["sides"] as Array):
			out.append(e)
		elif str(e["kind"]) == "bout":
			out.append(e)
	_shown = lg.size()
	_step_time = 0.4
	return out


func _start_entry(e: Dictionary) -> void:
	_rec = e


func _end_entry(e: Dictionary) -> void:
	if str(e["kind"]) == "bout":
		_bouts_shown += 1


func _on_entries_done() -> void:
	_rec = {}
	if m != null:
		_bouts_shown = (m.d["bouts"] as Array).size()


func _draw() -> void:
	missing.clear()
	art_or_box("tourney", "list", Rect2(Vector2.ZERO, size), Color(0.3, 0.26, 0.18), tr("games.ui.art_missing") % "tourney/list")
	if m == null:
		return
	var tm := m as TourneyMatch
	var bouts: Array = (m.d["bouts"] as Array).slice(0, _bouts_shown)
	var draw_: Array = m.d["draw"]
	# the draw: 8 names in pairs, the winners of each round to the right
	var x0 := 6.0
	var rowh := 19.0
	for i: int in draw_.size():
		var s := int(draw_[i])
		var y := 10.0 + i * rowh + (4.0 if i % 2 == 1 else 0.0)
		var lost := _lost_in(bouts, s)
		text(Vector2(x0, y + 12), _short(who(s), 10), GOLD if s == 0 else (DIM if lost >= 0 else INK), 8)
	var col_x := [72.0, 124.0, 176.0]
	for r: int in 3:
		var k := 0
		for b: Dictionary in bouts:
			if int(b["round"]) != r:
				continue
			var span := pow(2.0, r + 1)
			var y := 10.0 + (k * span + span / 2.0) * rowh - 4.0
			text(Vector2(col_x[r], y), _short(who(int(b["winner"])), 8), GOLD if int(b["winner"]) == 0 else INK, 8)
			k += 1
	# the bout being fought (the played side's), or the last one
	var cs: Array = v.get("bout_sides", [])
	var px := 236.0
	if not cs.is_empty() or not _rec.is_empty():
		var sides: Array = cs if _rec.is_empty() or str(_rec.get("kind", "")) == "bout" else _rec["sides"]
		if sides.is_empty():
			sides = _rec.get("sides", [0, 1])
		var touches: Array = v.get("touches", [0, 0])
		var breath: Array = v.get("breath", [0, 0])
		var bmax: Array = v.get("breath_max", [5, 5])
		if playing and str(_rec.get("kind", "")) == "lance":
			touches = _rec["touches"]
			breath = _rec["breath"]
		for k2: int in 2:
			var y2 := 14.0 + k2 * 62.0
			var s2 := int(sides[k2])
			text(Vector2(px, y2), who(s2), GOLD if s2 == 0 else INK, 16)
			text(Vector2(px, y2 + 14), tr("combat.ui.touches"), DIM, 8)
			pips(Vector2(px + 44, y2 + 7), int(touches[k2]), maxi(3, int(touches[k2])), GOLD)
			text(Vector2(px, y2 + 28), tr("combat.ui.breath") % [int(breath[k2]), int(bmax[k2])], DIM, 8)
			pips(Vector2(px + 64, y2 + 21), int(breath[k2]), int(bmax[k2]), Color(0.36, 0.55, 0.78))
		var lance := int(v.get("lance", 0))
		if playing and str(_rec.get("kind", "")) == "lance":
			lance = int(_rec["lance"])
		var label := tr("games.tourney.ui.sudden") % (lance + 1) if bool(v.get("sudden", false)) else \
			tr("games.tourney.ui.asalto") % [mini(3, lance / 3 + 1), lance + 1]
		text(Vector2(px, 150), label, INK, 8)
		if playing and str(_rec.get("kind", "")) == "lance":
			var acts: Array = _rec["actions"]
			text(Vector2(px, 166), "%s · %s" % [tr("combat.action.%s" % str(acts[0])), tr("combat.action.%s" % str(acts[1]))], INK, 16)
	elif not bool(v.get("alive", true)):
		text(Vector2(px, 40), tr("games.tourney.ui.out"), DIM, 8)
	text(Vector2(px, size.y - 6), tr("games.tourney.ui.weapon") % tr("combat.weapon.%s" % tm.weapon()), DIM, 8)
	var rnd := tm.round_name(int(m.d["round"]))
	text(Vector2(size.x - 8, 12), tr("games.tourney.round.%s" % rnd), GOLD, 8, -1.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _lost_in(bouts: Array, s: int) -> int:
	for b: Dictionary in bouts:
		if int(b["loser"]) == s:
			return int(b["round"])
	return -1


func _short(n: String, max_len: int = 16) -> String:
	return n if n.length() <= max_len else n.substr(0, max_len - 1) + "…"


func info_busy() -> Dictionary:
	return {"title": tr("games.tourney.ui.playing"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": "", "read": ""}
	var dv: Dictionary = view.get("duel", {})
	var cs: Array = view.get("bout_sides", [])
	if dv.is_empty() or cs.is_empty():
		return {"title": tr("games.tourney.ui.out") if not bool(view.get("alive", true)) else tr("games.tourney.ui.playing"),
			"text": "", "read": ""}
	var rival := int(cs[1]) if int(cs[0]) == 0 else int(cs[0])
	match str(dv.get("role", "blind")):
		"read":
			return {"title": tr("combat.ui.rival_leads") % who(rival), "text": tr("combat.cue.%s" % str(dv["cue"])),
				"read": tr("combat.ui.reliable") % roundi(float(dv["read"]) * 10.0)}
		"lead":
			return {"title": tr("combat.ui.you_lead"), "text": tr("combat.ui.you_lead_text") % who(rival),
				"read": tr("combat.ui.read_by") % [who(rival), roundi(float(dv["read_by"]) * 10.0)]}
	return {"title": tr("combat.ui.blind"), "text": tr("combat.ui.blind_text"), "read": ""}


func log_line(e: Dictionary) -> String:
	if str(e["kind"]) == "bout":
		var t: Array = e["touches"]
		var w := int(e["winner"])
		var sides: Array = e["sides"]
		var wi := 0 if int(sides[0]) == w else 1
		return tr("games.tourney.ui.log_bout") % [who(w), who(int(e["loser"])), int(t[wi]), int(t[1 - wi]),
			tr("games.tourney.how.%s" % str(e["how"]))]
	return ""
