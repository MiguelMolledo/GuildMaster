class_name FamiliesPanel
extends PanelContainer
## The families of the town (docs/ui/mecanicas/rivales.md, only what the sim has today: the rivalry, the omens and
## the attacks wait for the rival AI 04c), in the management zone; key G. Two groups: «Compiten contigo» (families
## with an AI profile) and «Vecinos» (households, folded). Each row: ribbon, name, title, public reputation, businesses,
## offices and the head's portrait. A click opens the family's sheet (same box, «‹ Volver»): its members (children
## without detail), businesses seen from outside (open / under works), offices, public facts (titles, offices,
## weddings, trials) and what one can do: give the head a gift or accuse (its townsperson's sheet), see it on the map.
## Never its gold, stores, queues or inner upgrades (_social rule 5, 04c 4.21.4): the gold's place says so.
## Reads only; the actions go through the HUD's own calls (open_npc, focus_requested).

signal closed

const GROUP: StringName = &"families_panel"

var sim: Sim
var actor: String = ""
var family: String = ""          # the family of the sheet ("" = the list)
var neighbours_open: bool = false
var _sig: String = ""
var _bound: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	ManageSlot.join(self)


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%BackButton as Button).pressed.connect(func() -> void: show_family(""))
	(%NeighboursButton as Button).pressed.connect(func() -> void:
		neighbours_open = not neighbours_open
		refresh(true))
	(%GiftButton as Button).pressed.connect(func() -> void: _hud_call("open_npc", _head()))
	(%AccuseButton as Button).pressed.connect(func() -> void: _hud_call("open_npc", _head()))
	(%MapButton as Button).pressed.connect(func() -> void:
		var b := _main_business()
		if b != "" and owner != null and owner.has_signal("focus_requested"):
			owner.emit_signal("focus_requested", b))


## Opens the list (or the sheet of `fam`) for the selected person `who`.
func open_for(s: Sim, who: String, fam: String = "") -> void:
	_bind()
	sim = s
	actor = who
	family = fam
	(%Title as Label).text = SimQuery.t_("ui.families.title")
	(%RivalsLabel as Label).text = SimQuery.t_("ui.families.rivals")
	(%BackButton as Button).text = SimQuery.t_("ui.families.back")
	(%GiftButton as Button).text = SimQuery.t_("ui.families.gift")
	(%AccuseButton as Button).text = SimQuery.t_("ui.families.accuse")
	(%MapButton as Button).text = SimQuery.t_("ui.families.map")
	visible = true
	refresh(true)
	ViewConfig.info("FamiliesPanel", "open (actor=%s, family=%s)" % [who, fam])


func show_family(fam: String) -> void:
	family = fam
	refresh(true)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and sim != null:
		refresh()


## Key G toggles the panel (rivales.md: «de gremio»), with the game's sim and the selected person.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo() or (event as InputEventKey).keycode != KEY_G:
		return
	var g := get_node_or_null("/root/Game")
	if g == null or g.get("sim") == null:
		return
	if visible:
		close()
	else:
		var who := str(owner.get("selected_id")) if owner != null and owner.get("selected_id") != null else ""
		open_for(g.get("sim"), who)
	get_viewport().set_input_as_handled()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var sig := "%s|%s|%s|%d" % [family, neighbours_open, sim.state.chronicle.size(), Clock.day(int(sim.state.clock["minute"]))]
	if sig == _sig and not force:
		return
	_sig = sig
	(%ListPage as Control).visible = family == ""
	(%SheetPage as Control).visible = family != ""
	if family == "":
		_fill_list()
	else:
		_fill_sheet()
	reset_size()


func _mine() -> String:
	var f := str(sim.state.characters.get(actor, {}).get("family", ""))
	return f if f != "" else SimQuery.player_family(sim.state)


## The families other than the player's: [rivals (AI profile), neighbours (households)], sorted by id.
func groups() -> Array:
	var rivals: Array = []
	var neighbours: Array = []
	var ids: Array = sim.state.families.keys()
	ids.sort()
	for id: Variant in ids:
		var f: Dictionary = sim.state.families[id]
		if str(id) == _mine() or str(f.get("controlled_by", "")) == "human":
			continue
		if str(f.get("ai_profile", "")) != "":
			rivals.append(str(id))
		elif TownLife.is_household(sim.state, str(id)):
			neighbours.append(str(id))
	return [rivals, neighbours]


func _fill_list() -> void:
	var g := groups()
	var rl := %RivalsList as VBoxContainer
	SocialKit.clear(rl)
	for f: String in g[0]:
		rl.add_child(_row(f))
	if (g[0] as Array).is_empty():
		rl.add_child(SocialKit.label(SimQuery.t_("ui.families.no_rivals"), &"DimLabel", "None"))
	var nb := %NeighboursList as VBoxContainer
	SocialKit.clear(nb)
	(%NeighboursButton as Button).text = SimQuery.t_("ui.families.neighbours") % (g[1] as Array).size() + \
		(" ▾" if neighbours_open else " ▸")
	nb.visible = neighbours_open
	if neighbours_open:
		for f: String in g[1]:
			nb.add_child(_row(f))


func _row(fam: String) -> Control:
	var st := sim.state
	var f: Dictionary = st.families.get(fam, {})
	var p := PanelContainer.new()
	p.name = "Fam_" + fam
	p.theme_type_variation = &"RowPanel"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			show_family(fam))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(SocialKit.ribbon(st, fam, Vector2(8, 32)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(SocialKit.label(SimQuery.t_("ui.family.title") % str(f.get("name", fam)), &"BoldLabel", "Name"))
	col.add_child(SocialKit.label(public_line(fam), &"DimLabel", "Public"))
	var offs := Offices.of_family(sim, fam)
	if not offs.is_empty():
		var names: PackedStringArray = []
		for o: Variant in offs:
			names.append(SimQuery.office_name(str(o.get("office", o)) if o is Dictionary else str(o)))
		col.add_child(SocialKit.label(", ".join(names), &"GoldLabel", "Offices"))
	h.add_child(col)
	var head := str(f.get("head", ""))
	if st.characters.has(head):
		h.add_child(SocialKit.portrait(st, head))
	return p


## «Ciudadano · rep. 60 · 1 negocio»: what anybody can see of a family.
func public_line(fam: String) -> String:
	var t := SimQuery.title_name(Titles.current(sim, fam))
	return SimQuery.t_("ui.families.public") % [t.substr(0, 1).to_upper() + t.substr(1), Reputation.of(sim.state, fam),
		Titles.businesses(sim, fam)]


func _head() -> String:
	return str(sim.state.families.get(family, {}).get("head", ""))


func _main_business() -> String:
	var ids := Titles.business_ids(sim, family)
	return str(ids[0]) if not ids.is_empty() else ""


func _hud_call(method: String, arg: String) -> void:
	if owner != null and owner.has_method(method) and arg != "":
		owner.call(method, arg)


func _fill_sheet() -> void:
	var st := sim.state
	var f: Dictionary = st.families.get(family, {})
	var slot := %SheetRibbon as Control
	SocialKit.clear(slot)
	slot.add_child(SocialKit.ribbon(st, family, Vector2(12, 34)))
	(%SheetName as Label).text = SimQuery.t_("ui.family.title") % str(f.get("name", family))
	(%SheetPublic as Label).text = public_line(family)
	(%NoGold as Label).text = SimQuery.t_("ui.families.no_gold")
	(%NoGold as Label).tooltip_text = SimQuery.t_("ui.families.no_gold_tip")
	(%GiftButton as Button).disabled = _head() == "" or not Kin.alive(st, _head())
	(%AccuseButton as Button).visible = Tribunal.accuse_options(sim, actor, _head()).get("reason", "") == "" if actor != "" else false
	(%MapButton as Button).disabled = _main_business() == ""
	var members := %Members as VBoxContainer
	SocialKit.clear(members)
	for m: Variant in f.get("members", []):
		var id := str(m)
		var ch: Dictionary = st.characters.get(id, {})
		if ch.is_empty() or not bool(ch.get("alive", true)):
			continue
		var r := HBoxContainer.new()
		r.name = "M_" + id
		r.add_theme_constant_override("separation", 6)
		r.add_child(SocialKit.portrait(st, id))
		var line := str(ch.get("name", id))
		if Kin.is_adult(sim, id):
			line += " · " + SimQuery.t_("ui.npc.age") % Kin.age(sim, id)
			var o := Offices.of_character(st, id)
			if o != "":
				line += " · " + SimQuery.office_name(o)
		else:
			line += " · " + SimQuery.t_("ui.families.child")
		var l := SocialKit.label(line, &"", "Line")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(l)
		members.add_child(r)
	var biz := %Businesses as VBoxContainer
	SocialKit.clear(biz)
	for b: String in Titles.business_ids(sim, family):
		var works := st.buildings.get(b, {}).get("upgrade_work") != null
		biz.add_child(SocialKit.label("%s · %s" % [SimQuery.building_label(st, sim.catalog, b),
			SimQuery.t_("ui.families.works" if works else "ui.families.open")], &"", "B_" + b))
	if biz.get_child_count() == 0:
		biz.add_child(SocialKit.label(SimQuery.t_("ui.families.no_business"), &"DimLabel", "None"))
	var facts := %Facts as VBoxContainer
	SocialKit.clear(facts)
	var lines := public_facts(family)
	for i: int in mini(lines.size(), 6):
		facts.add_child(SocialKit.label(str(lines[i]), &"DimLabel", "F_%d" % i))
	if lines.is_empty():
		facts.add_child(SocialKit.label(SimQuery.t_("ui.families.no_facts"), &"DimLabel", "None"))
	(%MembersTitle as Label).text = SimQuery.t_("ui.families.members")
	(%BusinessesTitle as Label).text = SimQuery.t_("ui.families.businesses")
	(%FactsTitle as Label).text = SimQuery.t_("ui.families.facts")


## The public facts of a family, newest first: titles, offices won, weddings, the facts against it (justice).
func public_facts(fam: String) -> Array:
	var st := sim.state
	var out: Array = []
	for i: int in range(st.chronicle.size() - 1, -1, -1):
		var e: Dictionary = st.chronicle[i]
		if str(e.get("family", "")) != fam:
			continue
		var d := Clock.day(int(e.get("minute", 0))) + 1
		match str(e.get("kind", "")):
			"title":
				out.append(SimQuery.t_("ui.families.f_title") % [SimQuery.title_name(str(e.get("title", ""))), d])
			"office_won":
				out.append(SimQuery.t_("ui.families.f_office") % [SimQuery.office_name(str(e.get("office", ""))), d])
			"wedding":
				out.append(SimQuery.t_("ui.families.f_wedding") % d)
	for fa: Dictionary in Tribunal.facts_against(sim, fam):
		out.append(SimQuery.t_("ui.families.f_fact") % [SimQuery.t_("charge." + str(fa.get("charge", ""))), int(fa.get("day", 0)) + 1])
	return out
