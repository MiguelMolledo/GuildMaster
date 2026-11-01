class_name FamilyTreePanel
extends PanelContainer
## The family tree (GDD 4.10.7, key F): an overlay that does not pause. Founder at the top, descendants below, spouses
## beside them joined by a line with a ring, children hanging from the couple; scroll and zoom (+/−). Each node: portrait
## (family colours, the person's hair and skin: GDD 4.10.9), name, age (or age at death), class; gold ring =
## controllable, grey = not, faded with a cross = dead, crown = heir, highlighted = active. A click opens the side
## sheet: attributes and the actions Designate heir, Assign building, Switch to this person, the school choice and
## Court. Below, the dynasty: generation, score and goals (GDD 4.17), and the voluntary close only when the data
## allows it (D19). Only reads the state and gives orders (order_sink); the lines are ColorRect nodes.

signal switch_requested(id: String)
signal court_requested(id: String)
signal closed

const NODE_W: float = 112.0
const NODE_H: float = 48.0
const GAP: float = 16.0
const VGAP: float = 28.0
const LINE: Color = Color(0.85, 0.75, 0.5)

var order_sink: Callable = Callable()
var sim: Sim
var fam: String = ""
var actor: String = ""      # who gives the orders (the selected person or the head)
var active: String = ""     # the selected person on the map
var picked: String = ""     # the person of the side sheet
var zoom: float = 1.0
var _sig: String = ""
var _bound: bool = false
var _node_scene: PackedScene = preload("res://game/ui/family_tree_node.tscn")


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%ZoomIn as Button).pressed.connect(func() -> void: set_zoom(zoom + 0.25))
	(%ZoomOut as Button).pressed.connect(func() -> void: set_zoom(zoom - 0.25))
	(%HeirButton as Button).pressed.connect(func() -> void: _give({"type": "designate_heir", "actor": actor, "heir": picked}))
	(%SwitchButton as Button).pressed.connect(func() -> void: switch_requested.emit(picked))
	(%CourtButton as Button).pressed.connect(func() -> void: court_requested.emit(picked))
	(%SchoolButton as Button).pressed.connect(_school)
	(%AssignOption as OptionButton).item_selected.connect(_assign)
	(%CloseDynasty as Button).pressed.connect(func() -> void: _give({"type": "close_dynasty", "actor": actor}))


func setup(s: Sim, family: String, who: String) -> void:
	_bind()
	sim = s
	fam = family
	active = who
	actor = who if s.state.characters.has(who) and str(s.state.characters[who].get("family", "")) == family \
		else Kin.head(s.state, family)
	if picked == "" or not s.state.characters.has(picked) or str(s.state.characters[picked].get("family", "")) != family:
		picked = actor
	(%Title as Label).text = SimQuery.t_("ui.family.title") % str(s.state.families.get(family, {}).get("name", ""))
	(%HeirButton as Button).text = SimQuery.t_("ui.family.designate_heir")
	(%SwitchButton as Button).text = SimQuery.t_("ui.family.switch")
	(%CourtButton as Button).text = SimQuery.t_("ui.family.court")
	(%SchoolButton as Button).text = SimQuery.t_("ui.family.school")
	(%AssignLabel as Label).text = SimQuery.t_("ui.family.assign")
	(%GoalsTitle as Label).text = SimQuery.t_("ui.family.goals")
	(%CloseDynasty as Button).text = SimQuery.t_("ui.family.close_dynasty")
	refresh(true)


func open() -> void:
	visible = true
	refresh(true)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func set_zoom(z: float) -> void:
	zoom = clampf(z, 0.5, 2.0)
	refresh(true)


func pick(id: String) -> void:
	picked = id
	refresh(true)


func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh(force: bool = false) -> void:
	if sim == null or fam == "":
		return
	var st := sim.state
	var f: Dictionary = st.families.get(fam, {})
	var sig := "%s|%s|%s|%s|%s|%s|%d|%s|%s" % [f.get("members", []), f.get("head", ""), Kin.heir(sim, fam),
		f.get("regent", ""), active, picked, Clock.year(int(st.clock["minute"]), sim.catalog.time), zoom,
		_people_sig(st, f)]
	if sig == _sig and not force:
		return
	_sig = sig
	_build_tree()
	_build_sheet()
	_build_dynasty()


func _people_sig(st: WorldState, f: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m: Variant in f.get("members", []):
		var ch: Dictionary = st.characters.get(str(m), {})
		parts.append("%s%s%s%s%s" % [ch.get("alive", true), ch.get("controlled_by", ""), ch.get("spouse", ""),
			(ch.get("children", []) as Array).size(), ch.get("life", {}).get("school", "") if ch.get("life") is Dictionary else ""])
	return ",".join(parts)


# --- Layout ------------------------------------------------------------------------------------------------------------

## The tree as positions (presentation only): {nodes: {id: Vector2 (slot x, generation)}, couples: [[a, b]],
## families: [{parents: [ids], children: [ids]}]}. Roots: the founder, then members not reached from it (and not
## spouses). Each person's unit = itself + its spouses (current and former) to its right; children under the unit.
static func layout(st: WorldState, fam: String) -> Dictionary:
	var f: Dictionary = st.families.get(fam, {})
	var out := {"nodes": {}, "couples": [], "families": []}
	var roots: Array = []
	var founder := str(f.get("founder", ""))
	if st.characters.has(founder):
		roots.append(founder)
	var reached := {}
	for r: String in roots:
		_reach(st, r, reached)
	for m: Variant in f.get("members", []):
		var id := str(m)
		if not reached.has(id) and _parents_in(st, id, reached) == false:
			roots.append(id)
			_reach(st, id, reached)
	var x := 0.0
	for r: String in roots:
		x += _place(st, r, x, 0, out)
	return out


static func _parents_in(st: WorldState, id: String, reached: Dictionary) -> bool:
	for p: Variant in st.characters.get(id, {}).get("parents", []):
		if reached.has(str(p)):
			return true
	return false


static func _reach(st: WorldState, id: String, reached: Dictionary) -> void:
	if reached.has(id):
		return
	reached[id] = true
	for s: String in _spouses(st, id):
		reached[s] = true
	for c: String in _children(st, id):
		_reach(st, c, reached)


static func _spouses(st: WorldState, id: String) -> Array:
	var ch: Dictionary = st.characters.get(id, {})
	var out: Array = []
	var life: Dictionary = ch.get("life", {}) if ch.get("life") is Dictionary else {}
	for s: Variant in life.get("former_spouses", []):
		if st.characters.has(str(s)) and not str(s) in out:
			out.append(str(s))
	var sp := str(ch.get("spouse", ""))
	if sp != "" and st.characters.has(sp) and not sp in out:
		out.append(sp)
	return out


static func _children(st: WorldState, id: String) -> Array:
	var kids: Array = (st.characters.get(id, {}).get("children", []) as Array).duplicate()
	kids = kids.filter(func(k: Variant) -> bool: return st.characters.has(str(k)))
	kids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ba := int(st.characters[str(a)].get("birth_day", 0))
		var bb := int(st.characters[str(b)].get("birth_day", 0))
		return ba < bb if ba != bb else str(a) < str(b))
	return kids.map(func(k: Variant) -> String: return str(k))


static func _width(st: WorldState, id: String) -> float:
	var own := 1.0 + _spouses(st, id).size()
	var kids := 0.0
	for c: String in _children(st, id):
		kids += _width(st, c)
	return maxf(own, kids)


## Places `id` and its descendants from slot `x0` at generation `depth`; returns the width used.
static func _place(st: WorldState, id: String, x0: float, depth: int, out: Dictionary) -> float:
	var w := _width(st, id)
	var sps := _spouses(st, id)
	var own := 1.0 + sps.size()
	var ux := x0 + (w - own) / 2.0
	out["nodes"][id] = Vector2(ux, depth)
	for i: int in sps.size():
		out["nodes"][sps[i]] = Vector2(ux + 1.0 + i, depth)
		out["couples"].append([id, sps[i]])
	var kids := _children(st, id)
	if not kids.is_empty():
		out["families"].append({"parents": [id] + sps, "children": kids})
	var cx := x0 + (w - _kids_width(st, kids)) / 2.0
	for c: String in kids:
		cx += _place(st, c, cx, depth + 1, out)
	return w


static func _kids_width(st: WorldState, kids: Array) -> float:
	var t := 0.0
	for c: String in kids:
		t += _width(st, c)
	return t


func _build_tree() -> void:
	var canvas := %Canvas as Control
	for c: Node in canvas.get_children():
		canvas.remove_child(c)
		c.queue_free()
	var st := sim.state
	var lay := layout(st, fam)
	var nodes: Dictionary = lay["nodes"]
	var heir := Kin.heir(sim, fam)
	var maxx := 0.0
	var maxy := 0.0
	var pos := {}
	for id: String in nodes:
		var slot: Vector2 = nodes[id]
		var p := Vector2(slot.x * (NODE_W + GAP), slot.y * (NODE_H + VGAP)) * zoom + Vector2(8, 8)
		pos[id] = p
		maxx = maxf(maxx, p.x + NODE_W * zoom)
		maxy = maxf(maxy, p.y + NODE_H * zoom)
	# lines first (under the nodes)
	for cp: Array in lay["couples"]:
		var a: Vector2 = pos[cp[0]]
		var b: Vector2 = pos[cp[1]]
		var y := a.y + NODE_H * zoom / 2.0
		_line(canvas, Vector2(a.x + NODE_W * zoom, y), Vector2(b.x, y))
		var ring := Panel.new()
		ring.name = "Ring_%s_%s" % [cp[0], cp[1]]
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 0.85, 0.3)
		sb.set_corner_radius_all(4)
		ring.add_theme_stylebox_override("panel", sb)
		ring.size = Vector2(8, 8)
		ring.position = Vector2((a.x + NODE_W * zoom + b.x) / 2.0 - 4, y - 4)
		canvas.add_child(ring)
	for fm: Dictionary in lay["families"]:
		var ps: Array = fm["parents"]
		var first: Vector2 = pos[ps[0]]
		var last: Vector2 = pos[ps[ps.size() - 1]]
		var top := Vector2((first.x + last.x + NODE_W * zoom) / 2.0, first.y + NODE_H * zoom / 2.0)
		if ps.size() == 1:
			top = Vector2(first.x + NODE_W * zoom / 2.0, first.y + NODE_H * zoom)
		var bar_y := first.y + NODE_H * zoom + VGAP * zoom / 2.0
		_line(canvas, top, Vector2(top.x, bar_y))
		var xs: Array = []
		for c: String in fm["children"]:
			xs.append((pos[c] as Vector2).x + NODE_W * zoom / 2.0)
		xs.append(top.x)
		_line(canvas, Vector2(xs.min(), bar_y), Vector2(xs.max(), bar_y))
		for c: String in fm["children"]:
			var cp2: Vector2 = pos[c]
			_line(canvas, Vector2(cp2.x + NODE_W * zoom / 2.0, bar_y), Vector2(cp2.x + NODE_W * zoom / 2.0, cp2.y))
	for id: String in nodes:
		var n := _node_scene.instantiate() as FamilyTreeNode
		canvas.add_child(n)
		n.position = pos[id]
		n.scale = Vector2(zoom, zoom)
		var ch: Dictionary = st.characters[id]
		n.show_person(sim, id, {"active": id == active, "heir": id == heir,
			"controlled": str(ch.get("controlled_by", "")) == "human" and bool(ch.get("alive", true)),
			"selected": id == picked})
		n.picked.connect(pick)
	canvas.custom_minimum_size = Vector2(maxx + 8, maxy + 8)


func _line(canvas: Control, a: Vector2, b: Vector2) -> void:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = LINE
	r.position = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(1, 1)
	r.size = Vector2(absf(b.x - a.x), absf(b.y - a.y)) + Vector2(2, 2)
	canvas.add_child(r)


# --- Side sheet --------------------------------------------------------------------------------------------------------

func _build_sheet() -> void:
	var st := sim.state
	var ch: Dictionary = st.characters.get(picked, {})
	(%SheetName as Label).text = str(ch.get("name", ""))
	var lines: PackedStringArray = []
	var age := Kin.age(sim, picked)
	lines.append((SimQuery.t_("ui.family.age_dead") if not bool(ch.get("alive", true)) else SimQuery.t_("ui.family.age")) % age)
	lines.append(SimQuery.t_("class." + str(ch.get("class", "artisan"))) + (" · " + SimQuery.t_("profession." + str(ch["profession"]))
		if str(ch.get("profession", "")) != "" else ""))
	var f: Dictionary = st.families.get(fam, {})
	var roles: PackedStringArray = []
	if picked == str(f.get("head", "")):
		roles.append(SimQuery.t_("ui.family.head"))
	if picked == Kin.heir(sim, fam):
		roles.append(SimQuery.t_("ui.family.heir"))
	if picked == str(f.get("regent", "")):
		roles.append(SimQuery.t_("ui.family.regent"))
	if str(ch.get("controlled_by", "")) == "human" and bool(ch.get("alive", true)):
		roles.append(SimQuery.t_("ui.family.controllable"))
	if not roles.is_empty():
		lines.append(" · ".join(roles))
	var sp := str(ch.get("spouse", ""))
	if sp != "":
		lines.append(SimQuery.t_("ui.family.spouse") % str(st.characters.get(sp, {}).get("name", "")))
	(%SheetInfo as Label).text = "\n".join(lines)
	var stats := %Stats as GridContainer
	for c: Node in stats.get_children():
		stats.remove_child(c)
		c.queue_free()
	var sd: Dictionary = ch.get("stats", {})
	var keys: Array = sd.keys()
	for k: Variant in ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution",
			"rhetoric", "stealth"]:
		if not sd.has(k):
			continue
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 9)
		l.text = "%s %d" % [SimQuery.t_("stat." + str(k)), int(sd[k])]
		stats.add_child(l)
	keys.clear()
	var alive := bool(ch.get("alive", true))
	var h := Kin.head(st, fam)
	(%HeirButton as Button).disabled = not (alive and h != "" and Kin.can_inherit(sim, h, picked) and picked != Kin.heir(sim, fam))
	(%SwitchButton as Button).disabled = not (alive and str(ch.get("controlled_by", "")) == "human" and picked != active)
	(%CourtButton as Button).visible = alive and Kin.is_adult(sim, picked) and Kin.is_single(st, picked) \
		and str(ch.get("controlled_by", "")) == "human"
	var school := alive and ch.get("life") is Dictionary and str(ch["life"].get("school", "")) == "pending"
	(%SchoolRow as Control).visible = school
	if school:
		var opt := %SchoolOption as OptionButton
		opt.clear()
		for k: String in ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution",
				"rhetoric", "stealth"]:
			opt.add_item(SimQuery.t_("stat." + k))
			opt.set_item_metadata(opt.item_count - 1, k)
		opt.select(5)
	var assign := %AssignOption as OptionButton
	assign.clear()
	assign.add_item(SimQuery.t_("ui.family.assign_default"))
	assign.set_item_metadata(0, "")
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if str(st.buildings[b].get("owner", "")) == fam and not (st.buildings[b].get("zones", {}) as Dictionary).is_empty():
			assign.add_item(SimQuery.building_name(st, sim.catalog, b))
			assign.set_item_metadata(assign.item_count - 1, b)
			if str(ch.get("assigned", "")) == b:
				assign.select(assign.item_count - 1)
	(%AssignRow as Control).visible = alive and Kin.is_adult(sim, picked)


func _school() -> void:
	var opt := %SchoolOption as OptionButton
	if opt.selected < 0:
		return
	_give({"type": "school_choice", "actor": actor, "child": picked, "stat": str(opt.get_item_metadata(opt.selected))})


func _assign(index: int) -> void:
	var opt := %AssignOption as OptionButton
	_give({"type": "assign_building", "actor": actor, "character": picked, "building": str(opt.get_item_metadata(index))})


# --- Dynasty -----------------------------------------------------------------------------------------------------------

func _build_dynasty() -> void:
	var f: Dictionary = sim.state.families.get(fam, {})
	var sc := Dynasty.score(sim, fam)
	(%DynastyLabel as Label).text = SimQuery.t_("ui.family.dynasty") % [int(f.get("generation", 1)), int(sc["total"])]
	var goals := %Goals as VBoxContainer
	for c: Node in goals.get_children():
		goals.remove_child(c)
		c.queue_free()
	for g: Dictionary in Dynasty.goals_view(sim, fam):
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 9)
		l.text = ("+ " if bool(g["done"]) else "- ") + SimQuery.t_(str(g["name_key"]))
		l.modulate = Color(0.6, 1, 0.6) if bool(g["done"]) else Color(1, 1, 1, 0.75)
		goals.add_child(l)
	(%CloseDynasty as Button).visible = bool(sim.catalog.family.get("succession", {}).get("voluntary_close", false))


func _give(o: Dictionary) -> void:
	if str(o.get("actor", "")) == "":
		return
	ViewConfig.info("FamilyTree", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
