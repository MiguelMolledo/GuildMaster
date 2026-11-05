class_name BoardFight
extends GameBoard
## The town's fights (docs/ui/mecanicas/juegos.md §Rescate; rules: RescueMatch, BrawlMatch): the rescue of a kidnapping
## (the rescuers on the left, the band on the right; who is out goes dim) and the brawl one bets on (the two brawlers).
## In the middle, the bout being fought: touches and breath of each and the lance; the played side's lances come in
## one by one, as in the duel; the helpers' bouts at once.

var _shown: int = 0
var _rec: Dictionary = {}


func reset() -> void:
	super.reset()
	_shown = 0
	_rec = {}


func new_entries(match_: GameMatch) -> Array:
	var lg := match_.log_entries()
	var out: Array = []
	for i: int in range(_shown, lg.size()):
		var e: Dictionary = lg[i]
		if str(e["kind"]) == "bout" or (0 in (e.get("sides", []) as Array) and match_ is RescueMatch):
			out.append(e)
	_shown = lg.size()
	_step_time = 0.45
	return out


func _start_entry(e: Dictionary) -> void:
	_rec = e


func _end_entry(_e: Dictionary) -> void:
	_rec = {}


func _draw() -> void:
	missing.clear()
	art_or_box("fight", "street", Rect2(Vector2.ZERO, size), Color(0.3, 0.27, 0.22), tr("games.ui.art_missing") % "fight/street")
	if m == null:
		return
	var a: Array = m.d.get("a", [0])
	var b: Array = m.d.get("b", [1])
	var out := _out_sides()
	for k: int in a.size():
		var s := int(a[k])
		text(Vector2(8, 18 + k * 18), _short(who(s)), DIM if s in out else (GOLD if s == 0 else INK), 8)
	for k: int in b.size():
		var s := int(b[k])
		text(Vector2(size.x - 8, 18 + k * 18), _short(who(s)), DIM if s in out else RED.lightened(0.35), 8, -1.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var sides: Array = v.get("bout_sides", [0, 1]) if m is RescueMatch else [0, 1]
	if playing and not _rec.is_empty():
		sides = _rec.get("sides", sides)
	if sides.size() != 2:
		text(Vector2(0, size.y / 2.0), tr("games.ui.over"), INK, 16, size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	# a brawl to bet on is not fought here: nothing of its result shows (the incident fights it later)
	var touches: Array = v.get("touches", [0, 0]) if m is RescueMatch else [0, 0]
	var breath: Array = v.get("breath", [0, 0])
	if m is BrawlMatch:
		var bm := m as BrawlMatch
		breath = [CombatRules.breath_max(bm.combat, bm.fighter(0)), CombatRules.breath_max(bm.combat, bm.fighter(1))]
		v["breath_max"] = breath
	if playing and str(_rec.get("kind", "")) == "lance":
		touches = _rec["touches"]
		breath = _rec["breath"]
	var cx := size.x / 2.0
	for k2: int in 2:
		var x := cx - 80.0 if k2 == 0 else cx + 10.0
		var s2 := int(sides[k2])
		text(Vector2(x, 60), _short(who(s2)), GOLD if s2 == 0 else INK, 16)
		text(Vector2(x, 76), tr("combat.ui.touches"), DIM, 8)
		pips(Vector2(x + 44, 69), int(touches[k2]), 3, GOLD)
		text(Vector2(x, 92), tr("combat.ui.breath") % [int(breath[k2]), int((v.get("breath_max", [5, 5]) as Array)[k2])], DIM, 8)
	if playing and str(_rec.get("kind", "")) == "lance":
		var acts: Array = _rec["actions"]
		text(Vector2(0, 124), "%s · %s" % [tr("combat.action.%s" % str(acts[0])), tr("combat.action.%s" % str(acts[1]))],
			INK, 16, size.x, HORIZONTAL_ALIGNMENT_CENTER)


## The fighters already out (the bouts shown so far).
func _out_sides() -> Array:
	var out: Array = []
	var done := _shown - (_queue.size() + (1 if playing else 0))
	var lg := m.log_entries()
	for i: int in mini(done, lg.size()):
		var e: Dictionary = lg[i]
		if str(e["kind"]) != "bout":
			continue
		var sides: Array = e["sides"]
		var w := int(e["winner"])
		if w != 0:
			out.append(int(sides[0]))
		if w != 1:
			out.append(int(sides[1]))
	return out


func _short(n: String) -> String:
	return n if n.length() <= 16 else n.substr(0, 15) + "…"


func info_busy() -> Dictionary:
	return {"title": tr("games.tourney.ui.playing"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": "", "read": ""}
	var dv: Dictionary = view.get("duel", {})
	var cs: Array = view.get("bout_sides", [])
	if dv.is_empty() or cs.is_empty():
		return {"title": tr("games.tourney.ui.playing"), "text": "", "read": ""}
	var rival := int(cs[1])
	match str(dv.get("role", "blind")):
		"read":
			return {"title": tr("combat.ui.rival_leads") % who(rival), "text": tr("combat.cue.%s" % str(dv["cue"])),
				"read": tr("combat.ui.reliable") % roundi(float(dv["read"]) * 10.0)}
		"lead":
			return {"title": tr("combat.ui.you_lead"), "text": tr("combat.ui.you_lead_text") % who(rival),
				"read": tr("combat.ui.read_by") % [who(rival), roundi(float(dv["read_by"]) * 10.0)]}
	return {"title": tr("combat.ui.blind"), "text": tr("combat.ui.blind_text"), "read": ""}


func log_line(e: Dictionary) -> String:
	if str(e["kind"]) != "bout":
		return ""
	var sides: Array = e["sides"]
	var w := int(e["winner"])
	if w < 0:
		return tr("games.rescue.ui.draw") % [who(int(sides[0])), who(int(sides[1]))]
	return tr("games.rescue.ui.bout") % [who(int(sides[w])), who(int(sides[1 - w]))]
