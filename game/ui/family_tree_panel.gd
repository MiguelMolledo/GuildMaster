class_name FamilyTreePanel
extends PanelContainer
## The family tree (GDD 4.10.7, key F; docs/ui/mecanicas/familia.md), a big modal that does not pause. Header: the
## family's ribbon, name, title badge, generation and score, the tabs Árbol / Dinastía and, when nobody can inherit,
## a red band «Sin heredero: si Hugo muere, la dinastía termina» (the Game Over rule of 4.10.4). The tree: founder at
## the top, spouses beside joined by a line with a ring, children hanging from the couple; zoom −/+ and «Centrar en el
## cabeza». Each node: portrait (family colours, the person's hair and skin: 4.10.9), name, age (or † age), a row of
## badges (key 1-2-3, office, school pending «!», regent) and in its tooltip the role and the death risk this year as
## a band (Lifecycle.death_chance: bajo < 5 % · medio < 15 % · alto). The side sheet (220 px): portrait 64, roles,
## the stats as bars 1-10, where it works and the actions Switch, Routine (the family AI), Designate heir (asks
## first; off with its reason), the school choice (asks first) and Court. The Dinastía tab: the score by kind, the
## goals with their box, the heads with their days and the voluntary close only when the data allows it (D19). Only
## reads the state and gives orders (order_sink); the lines are ColorRect nodes.

signal switch_requested(id: String)
signal court_requested(id: String)
signal kin_ai_requested(id: String)  # H14: the AI of the picked member
signal closed

const NODE_W: float = 120.0
const NODE_H: float = 44.0
const GAP: float = 24.0
const VGAP: float = 32.0
const STATS: Array[String] = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial",
	"constitution", "rhetoric", "stealth"]

var order_sink: Callable = Callable()
var sim: Sim
var fam: String = ""
var actor: String = ""      # who gives the orders (the selected person or the head)
var active: String = ""     # the selected person on the map
var picked: String = ""     # the person of the side sheet
var zoom: float = 1.0
var tab: String = "tree"    # "tree" | "dynasty"
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
	(%HeirButton as Button).pressed.connect(request_heir)
	(%SwitchButton as Button).pressed.connect(func() -> void: switch_requested.emit(picked))
	(%CourtButton as Button).pressed.connect(func() -> void: court_requested.emit(picked))
	(%KinAiButton as Button).pressed.connect(func() -> void: kin_ai_requested.emit(picked))
	(%SchoolButton as Button).pressed.connect(request_school)
	(%SchoolOption as OptionButton).item_selected.connect(func(_i: int) -> void: _school_preview())
	(%AssignOption as OptionButton).item_selected.connect(_assign)
	(%CloseDynasty as Button).pressed.connect(func() -> void:
		SocialKit.ask(self, SimQuery.t_("ui.pause.close_q"), SimQuery.t_("ui.pause.close_body"),
			SimQuery.t_("ui.pause.close_yes"), func() -> void: _give({"type": "close_dynasty", "actor": actor}),
			SimQuery.t_("ui.menu.cannot_undo")))
	(%TabTree as Button).pressed.connect(func() -> void: show_tab("tree"))
	(%TabDynasty as Button).pressed.connect(func() -> void: show_tab("dynasty"))
	(%CenterButton as Button).pressed.connect(center_on_head)


func setup(s: Sim, family: String, who: String) -> void:
	_bind()
	sim = s
	fam = family
	active = who
	actor = who if s.state.characters.has(who) and str(s.state.characters[who].get("family", "")) == family \
		else Kin.head(s.state, family)
	if picked == "" or not s.state.characters.has(picked) or str(s.state.characters[picked].get("family", "")) != family:
		picked = actor
	(%HeirButton as Button).text = SimQuery.t_("ui.family.designate_heir")
	(%SwitchButton as Button).text = SimQuery.t_("ui.family.switch_short")
	(%CourtButton as Button).text = SimQuery.t_("ui.family.court")
	(%KinAiButton as Button).text = SimQuery.t_("ui.family.routine")
	(%SchoolButton as Button).text = SimQuery.t_("ui.family.school_pick")
	(%AssignLabel as Label).text = SimQuery.t_("ui.family.assign")
	(%GoalsTitle as Label).text = SimQuery.t_("ui.family.goals")
	(%HeadsTitle as Label).text = SimQuery.t_("ui.family.heads")
	(%ScoreTitle as Label).text = SimQuery.t_("ui.ending.score_title")
	(%CloseDynasty as Button).text = SimQuery.t_("ui.family.close_dynasty")
	(%TabTree as Button).text = SimQuery.t_("ui.family.tab_tree")
	(%TabDynasty as Button).text = SimQuery.t_("ui.family.tab_dynasty")
	(%CenterButton as Button).text = SimQuery.t_("ui.family.center")
	(%Legend as Label).text = SimQuery.t_("ui.family.legend")
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


func show_tab(t: String) -> void:
	tab = t
	(%TreePage as Control).visible = t == "tree"
	(%DynastyPage as Control).visible = t == "dynasty"
	(%TabTree as Button).set_pressed_no_signal(t == "tree")
	(%TabDynasty as Button).set_pressed_no_signal(t == "dynasty")


## Scrolls the tree so the head of the family is in the middle of the view.
func center_on_head() -> void:
	var h := Kin.head(sim.state, fam) if sim != null else ""
	var n := (%Canvas as Control).get_node_or_null(h) as Control
	if n == null:
		return
	var sc := %Scroll as ScrollContainer
	sc.scroll_horizontal = int(maxf(0.0, n.position.x + NODE_W * zoom / 2.0 - sc.size.x / 2.0))
	sc.scroll_vertical = int(maxf(0.0, n.position.y + NODE_H * zoom / 2.0 - sc.size.y / 2.0))


func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh(force: bool = false) -> void:
	if sim == null or fam == "":
		return
	var st := sim.state
	var f: Dictionary = st.families.get(fam, {})
	var sig := "%s|%s|%s|%s|%s|%s|%d|%s|%s|%s" % [f.get("members", []), f.get("head", ""), Kin.heir(sim, fam),
		f.get("regent", ""), active, picked, Clock.year(int(st.clock["minute"]), sim.catalog.time), zoom,
		_people_sig(st, f), tab]
	if sig == _sig and not force:
		return
	_sig = sig
	_build_header()
	_build_tree()
	_build_sheet()
	_build_dynasty()
	show_tab(tab)


func _people_sig(st: WorldState, f: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m: Variant in f.get("members", []):
		var ch: Dictionary = st.characters.get(str(m), {})
		parts.append("%s%s%s%s%s%s" % [ch.get("alive", true), ch.get("controlled_by", ""), ch.get("spouse", ""),
			(ch.get("children", []) as Array).size(), ch.get("life", {}).get("school", "") if ch.get("life") is Dictionary else "",
			ch.get("stats", {})])
	return ",".join(parts)


# --- Header ----------------------------------------------------------------------------------------------------------

func _build_header() -> void:
	var st := sim.state
	var f: Dictionary = st.families.get(fam, {})
	var slot := %RibbonSlot as Control
	SocialKit.clear(slot)
	slot.add_child(SocialKit.ribbon(st, fam, Vector2(10, 26)))
	(%Title as Label).text = SimQuery.t_("ui.family.title") % str(f.get("name", ""))
	var title := Titles.current(sim, fam)
	(%TitleBadge as TextureRect).texture = UiIcons.mark("badge_title_" + title)
	var t := SimQuery.title_name(title)
	(%Subtitle as Label).text = SimQuery.t_("ui.family.subtitle") % [t.substr(0, 1).to_upper() + t.substr(1),
		int(f.get("generation", 1)), int(Dynasty.score(sim, fam)["total"])]
	var heir := Kin.heir(sim, fam)
	var head := str(f.get("head", ""))
	(%NoHeir as Control).visible = heir == "" and head != ""
	(%NoHeirLabel as Label).text = SimQuery.t_("ui.family.no_heir") % str(st.characters.get(head, {}).get("name", ""))


## The risk band of dying this year (bajo / medio / alto), never the number (familia.md §3).
static func risk_band(chance: float) -> String:
	if chance < 0.05:
		return "low"
	if chance < 0.15:
		return "medium"
	return "high"


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
		sb.border_color = SocialKit.theme_color(&"FamilyTree", &"ring")
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
	r.color = SocialKit.theme_color(&"FamilyTree", &"line")
	r.position = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(1, 1)
	r.size = Vector2(absf(b.x - a.x), absf(b.y - a.y)) + Vector2(2, 2)
	canvas.add_child(r)


# --- Side sheet --------------------------------------------------------------------------------------------------------

func _build_sheet() -> void:
	var st := sim.state
	var ch: Dictionary = st.characters.get(picked, {})
	var slot := %SheetPortrait as Control
	SocialKit.clear(slot)
	if not ch.is_empty():
		var frame := SocialKit.portrait(st, picked, {"controlled": str(ch.get("controlled_by", "")) == "human",
			"heir": picked == Kin.heir(sim, fam)})
		frame.scale = Vector2(2, 2)  # 64 inside (familia.md §3: 64 in the sheet)
		slot.add_child(frame)
	(%SheetName as Label).text = str(ch.get("name", ""))
	var alive := bool(ch.get("alive", true))
	var age := Kin.age(sim, picked)
	var line := (SimQuery.t_("ui.family.age_dead") if not alive else SimQuery.t_("ui.family.age")) % age
	if str(ch.get("profession", "")) != "":
		line += " · " + SimQuery.t_("profession." + str(ch["profession"]))
	(%SheetInfo as Label).text = line
	var f: Dictionary = st.families.get(fam, {})
	var roles: PackedStringArray = []
	if picked == str(f.get("head", "")):
		roles.append(SimQuery.t_("ui.family.head"))
	if picked == Kin.heir(sim, fam):
		roles.append(SimQuery.t_("ui.family.heir"))
	if picked == str(f.get("regent", "")):
		roles.append(SimQuery.t_("ui.family.regent"))
	var office := Offices.of_character(st, picked)
	if office != "" and alive:
		roles.append(SimQuery.office_name(office))
	(%SheetRoles as Label).text = " · ".join(roles).to_lower()
	(%SheetRoles as Label).visible = not roles.is_empty()
	var g := Kin.group(st, fam)
	var key := g.find(picked)
	var group_line := ""
	if alive and key >= 0:
		group_line = SimQuery.t_("ui.family.in_group") % (key + 1)
	var sp := str(ch.get("spouse", ""))
	if sp != "":
		group_line += ("\n" if group_line != "" else "") + SimQuery.t_("ui.family.spouse") % str(st.characters.get(sp, {}).get("name", ""))
	(%SheetGroup as Label).text = group_line
	(%SheetGroup as Label).visible = group_line != ""
	var stats := %Stats as GridContainer
	SocialKit.clear(stats)
	var sd: Dictionary = ch.get("stats", {})
	var smax := float(sim.catalog.family.get("life", {}).get("stat_max", 10))
	for k: String in STATS:
		if not sd.has(k):
			continue
		var l := SocialKit.label(SimQuery.t_("stat." + k), &"DimLabel", "Name_" + k)
		l.custom_minimum_size = Vector2(92, 0)
		stats.add_child(l)
		var bar := SocialKit.bar(float(sd[k]) / smax, 80.0, "Bar_" + k)
		stats.add_child(bar)
		var v := SocialKit.label(str(int(sd[k])), &"", "Value_" + k)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(18, 0)
		stats.add_child(v)
	var h := Kin.head(st, fam)
	var heir_why := heir_reason(picked)
	(%HeirButton as Button).disabled = heir_why != ""
	(%HeirButton as Button).visible = alive
	(%HeirReason as Label).text = heir_why
	(%HeirReason as Label).visible = alive and heir_why != ""
	var switch_why := ""
	if not alive:
		switch_why = "dead"
	elif str(ch.get("controlled_by", "")) != "human":
		switch_why = SimQuery.t_("ui.family.not_in_group")
	elif picked == active:
		switch_why = SimQuery.t_("ui.family.already_active")
	(%SwitchButton as Button).disabled = switch_why != ""
	(%SwitchButton as Button).tooltip_text = switch_why if switch_why != "dead" else ""
	(%SwitchButton as Button).visible = alive
	(%KinAiButton as Button).visible = alive and Kin.is_adult(sim, picked)  # H14
	(%CourtButton as Button).visible = alive and Kin.is_adult(sim, picked) and Kin.is_single(st, picked) \
		and str(ch.get("controlled_by", "")) == "human"
	var school := alive and ch.get("life") is Dictionary and str(ch["life"].get("school", "")) == "pending"
	(%SchoolRow as Control).visible = school
	(%SchoolPreview as Label).visible = school
	if school:
		var opt := %SchoolOption as OptionButton
		opt.clear()
		for k: String in STATS:
			opt.add_item(SimQuery.t_("stat." + k))
			opt.set_item_metadata(opt.item_count - 1, k)
		opt.select(STATS.find("craft"))
		_school_preview()
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
	if h == "":
		(%HeirButton as Button).visible = false


## Why `chr` cannot be designated heir now ("" if it can), as a text for the sheet.
func heir_reason(chr: String) -> String:
	var st := sim.state
	var h := Kin.head(st, fam)
	if h == "" or not Kin.alive(st, chr):
		return SimQuery.t_("ui.family.why_heir_dead")
	if chr == Kin.heir(sim, fam):
		return SimQuery.t_("ui.family.why_heir_already")
	if chr == h:
		return SimQuery.t_("ui.family.why_heir_head")
	if not Kin.can_inherit(sim, h, chr):
		return SimQuery.t_("ui.family.why_heir_not_descendant")
	return ""


## Designate heir asks first (familia.md §4): «Pere pasará a ser el heredero en lugar de Clara».
func request_heir() -> void:
	if heir_reason(picked) != "":
		return
	var st := sim.state
	var now := Kin.heir(sim, fam)
	var who := str(st.characters.get(picked, {}).get("name", picked))
	var body := SimQuery.t_("ui.family.heir_body") % [who, str(st.characters.get(now, {}).get("name", ""))] if now != "" \
		else SimQuery.t_("ui.family.heir_body_none") % who
	var heir_id := picked
	SocialKit.ask(self, SimQuery.t_("ui.family.heir_q") % who, body, SimQuery.t_("ui.family.designate_heir"),
		func() -> void: _give({"type": "designate_heir", "actor": actor, "heir": heir_id}), "", true)


func _school_preview() -> void:
	var opt := %SchoolOption as OptionButton
	if opt.selected < 0:
		return
	var k := str(opt.get_item_metadata(opt.selected))
	var v := int(sim.state.characters.get(picked, {}).get("stats", {}).get(k, 0))
	(%SchoolPreview as Label).text = SimQuery.t_("ui.family.school_preview") % [SimQuery.t_("stat." + k), v, v + 1]


## The school choice asks first: it is for ever (familia.md §4).
func request_school() -> void:
	var opt := %SchoolOption as OptionButton
	if opt.selected < 0:
		return
	var k := str(opt.get_item_metadata(opt.selected))
	var child := picked
	var who := str(sim.state.characters.get(child, {}).get("name", child))
	SocialKit.ask(self, SimQuery.t_("ui.family.school_q") % [SimQuery.t_("stat." + k), who], SimQuery.t_("ui.family.school_body"),
		SimQuery.t_("ui.family.school_pick"), func() -> void:
			_give({"type": "school_choice", "actor": actor, "child": child, "stat": k}), SimQuery.t_("ui.menu.cannot_undo"))


func _assign(index: int) -> void:
	var opt := %AssignOption as OptionButton
	_give({"type": "assign_building", "actor": actor, "character": picked, "building": str(opt.get_item_metadata(index))})


# --- Dynasty -----------------------------------------------------------------------------------------------------------

func _build_dynasty() -> void:
	var st := sim.state
	var f: Dictionary = st.families.get(fam, {})
	var sc := Dynasty.score(sim, fam)
	(%DynastyLabel as Label).text = SimQuery.t_("ui.family.dynasty") % [int(f.get("generation", 1)), int(sc["total"])]
	var rows := %ScoreRows as VBoxContainer
	SocialKit.clear(rows)
	var kinds: Array = (sc["by_kind"] as Dictionary).keys()
	kinds.sort()
	for k: String in kinds:
		var r := HBoxContainer.new()
		r.name = "Score_" + k
		var n := SocialKit.label(SimQuery.t_("score." + k), &"", "Name")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		r.add_child(SocialKit.label(str(int(sc["facts"].get(k, 0))) if k != "wealth_peak" else "", &"DimLabel", "Count"))
		var p := SocialKit.label(str(int(sc["by_kind"][k])), &"BoldLabel", "Points")
		p.custom_minimum_size = Vector2(48, 0)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(p)
		rows.add_child(r)
	if kinds.is_empty():
		rows.add_child(SocialKit.label(SimQuery.t_("ui.family.no_score"), &"DimLabel", "None"))
	var goals := %Goals as VBoxContainer
	SocialKit.clear(goals)
	for g: Dictionary in Dynasty.goals_view(sim, fam):
		var r := HBoxContainer.new()
		r.name = "Goal_" + str(g["id"])
		var box := TextureRect.new()
		box.texture = load("res://assets/art/ui/theme/check_on.png" if bool(g["done"]) else "res://assets/art/ui/theme/check_off.png")
		box.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		r.add_child(box)
		r.add_child(SocialKit.label(SimQuery.t_(str(g["name_key"])), &"PositiveLabel" if bool(g["done"]) else &"", "Name"))
		goals.add_child(r)
	var heads := %Heads as VBoxContainer
	SocialKit.clear(heads)
	for hd: Dictionary in Dynasty.summary(sim, fam)["heads"]:
		var to := int(hd.get("to_day", -1))
		heads.add_child(SocialKit.label(SimQuery.t_("ui.family.head_days") % [str(hd["name"]), int(hd["from_day"]) + 1,
			(str(to + 1) if to >= 0 else "—")], &"DimLabel"))
	(%CloseDynasty as Button).visible = bool(sim.catalog.family.get("succession", {}).get("voluntary_close", false))


func _give(o: Dictionary) -> void:
	if str(o.get("actor", "")) == "":
		return
	ViewConfig.info("FamilyTree", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
