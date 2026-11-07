class_name UpgradePanel
extends PanelContainer
## Upgrade tree of a building (docs/ui/mecanicas/mejoras.md; GDD 4.8), in the wide zone of the HUD. On top, the works
## in progress with their bar and when they end (or «No works: one at a time»). The 8 branches as rows, each with its
## icon (icon_rama_*), and their 3 levels as cells: the thumbnail of what the upgrade puts in the building (its
## furniture, station or facade sprite), its name whole, its price and its status as an icon and a colour (built,
## under construction with a 2 px bar, payable, short of something, one at a time, locked, needs a title); a key mark on
## a cell whose prerequisites are in another branch. Hovering a cell lights its prerequisites with a gold edge (the
## chosen one's otherwise). The detail of the chosen cell: «what you will see» (UpgradePreview: the building with the
## upgrade lit in gold), the effect with its consequence in figures (presentation sums on the effect's figure, no rule),
## the cost item by item with what there is and a tick or a warning, the requirements (a click on a missing upgrade
## chooses it), the works and what they mean, why it cannot be built, and Build, which always asks in the confirmation
## modal (it is dear and cannot be cancelled). At the bottom, the inspections when the building has a risk or a history.
## Reads only SimQuery / Upgrades (tree_view and read helpers); every change is an order through order_sink, signed by
## the selected person if they belong to the building's family, else by its first member.

signal closed

const BRANCH_ICONS: Dictionary = {"production": "icon_rama_produccion", "capacity": "icon_rama_capacidad",
	"quality": "icon_rama_calidad", "commerce": "icon_rama_comercio", "staff": "icon_rama_personal",
	"facade": "icon_rama_fachada", "security": "icon_rama_seguridad", "secrets": "icon_rama_secretos"}
const CELL_SIZE := Vector2(180, 22)
const SHORT: Array[String] = ["missing_materials", "not_enough_gold"]
const LOCKED: Array[String] = ["needs_upgrade", "stat_too_low", "title_too_low"]

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var preferred: String = ""   # the person selected (signs the orders if they are of the building's family)
var selected: String = ""    # the upgrade whose detail is shown
var _cells: Dictionary = {}  # upgrade id -> Button
var _view: Dictionary = {}   # the last Upgrades.tree_view
var _sig: String = ""
var _bound: bool = false
var _hover: String = ""      # the cell under the mouse ("" = none: the chosen one's prerequisites are lit)


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%BuyButton as Button).pressed.connect(func() -> void: buy(selected))


func setup(s: Sim, bld: String, who: String = "") -> void:
	_bind()
	sim = s
	building = bld
	preferred = who
	selected = ""
	(%Title as Label).text = SimQuery.t_("ui.upgrades.title") % SimQuery.building_label(s.state, s.catalog, bld)
	(%BuyButton as Button).text = SimQuery.t_("ui.upgrades.build")
	(%BuyButton as Button).tooltip_text = SimQuery.t_("ui.upgrades.buy_tip")
	(%SeesLabel as Label).text = SimQuery.t_("ui.upgrades.sees_caption")
	(%Preview as UpgradePreview).setup(s, bld)
	refresh(true)


func set_actor(who: String) -> void:
	preferred = who
	_sig = ""


## Who signs this panel's orders ("" if the building has no family with people).
func actor() -> String:
	if sim == null:
		return ""
	return SimQuery.building_actor(sim.state, building, preferred)


func open() -> void:
	visible = true
	refresh(true)
	ViewConfig.info("UpgradePanel", "open (building=%s, actor=%s, selected=%s)" % [building, actor(), selected])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible:
		refresh()


## The cell of `upgrade` (null if not in the tree): tests press it.
func cell_of(upgrade: String) -> Button:
	return _cells.get(upgrade, null)


## The status of `upgrade` as the panel shows it (Upgrades.status_of through tree_view; "" if unknown).
func status_of(upgrade: String) -> String:
	return str(_entry(upgrade).get("status", ""))


func _entry(upgrade: String) -> Dictionary:
	for br: Dictionary in _view.get("branches", []):
		for u: Dictionary in br.get("upgrades", []):
			if str(u["id"]) == upgrade:
				return u
	return {}


## Shows the detail of `upgrade`.
func select(upgrade: String) -> void:
	selected = upgrade
	ViewConfig.info("UpgradePanel", "select %s (status=%s)" % [upgrade, status_of(upgrade)])
	_sig = ""
	refresh(true)


## Rebuilds the grid and the detail when what they show changed (not every frame: the buttons must stay pressable);
## the works bar follows every frame.
func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var v := SimQuery.upgrade_tree(sim, actor(), building)
	var plain := v.duplicate(true)
	plain["work"] = str((v.get("work", {}) as Dictionary).get("upgrade", ""))
	var inv: Dictionary = sim.state.buildings.get(building, {}).get("inventory", {})
	var sig := JSON.stringify(plain) + selected + JSON.stringify(inv.get("stacks", [])) + str(_gold())
	_view = v
	_show_works(v.get("work", {}))
	if not force and (sig == _sig or UiFeel.hold_rebuild(self)):
		return
	_sig = sig
	if selected == "" or _entry(selected).is_empty():
		selected = _default_selection()
	_build_grid()
	_show_detail()
	_show_inspections()
	_mark_prereqs(_hover if _hover != "" else selected)


## The first available upgrade, else the first one not built, else the first; the Secrets branch (illegal profit, the
## inspections and the court) is never the one proposed while another can be (jugador J: the novice, following the
## tutorial, bought «Doble contabilidad» because it was the only one shown).
func _default_selection() -> String:
	var first := ""
	var not_owned := ""
	var branches: Array = (_view.get("branches", []) as Array).filter(func(b: Dictionary) -> bool:
		return str(b.get("id", "")) != "secrets") + (_view.get("branches", []) as Array).filter(
		func(b: Dictionary) -> bool: return str(b.get("id", "")) == "secrets")
	for br: Dictionary in branches:
		if str(br.get("id", "")) == "secrets" and not_owned != "":
			break   # an honest upgrade not built yet goes first, even if it is not affordable now
		for u: Dictionary in br.get("upgrades", []):
			var st := str(u["status"])
			if first == "":
				first = str(u["id"])
			if st == "available":
				return str(u["id"])
			if not_owned == "" and st != "owned":
				not_owned = str(u["id"])
	return not_owned if not_owned != "" else first


func _gold() -> int:
	return Money.gold(sim.state, SimQuery.building_family(sim.state, building))


func _status_color(status: String) -> Color:
	var cols: Dictionary = (ViewConfig.value("upgrades", {}) as Dictionary).get("status_colors", {})
	var key := status if status in ["owned", "in_works", "available"] else "blocked"
	if status in SHORT or status == "busy":
		key = "available"
	return ViewConfig.color(str(cols.get(key, "#808080")))


## The icon of a status (it must read in grey too, not only by its colour): built, under construction, payable,
## short of something / one at a time (a dot), locked, needs a title.
func status_icon(status: String) -> String:
	match status:
		"owned":
			return "icon_completed"
		"in_works":
			return "icon_in_progress"
		"available":
			return "icon_oro"
		"title_too_low":
			return "icon_crown"
		"needs_upgrade", "stat_too_low":
			return "icon_locked"
	return ""   # a dot


## Whether `id` needs an upgrade of another branch (the key mark on its cell).
func cross_branch(id: String) -> bool:
	var u := sim.catalog.upgrade(id)
	for r: Variant in u.get("requires", {}).get("upgrades", []):
		if str(sim.catalog.upgrade(str(r)).get("branch", "")) != str(u.get("branch", "")):
			return true
	return false


func _build_grid() -> void:
	var grid := %Grid as GridContainer
	for c: Node in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_cells.clear()
	var branches: Array = _view.get("branches", [])
	(%Empty as Label).visible = branches.is_empty()
	(%Empty as Label).text = SimQuery.t_("ui.upgrades.no_tree")
	if branches.is_empty():
		return
	var levels := int(sim.catalog.upgrade_rules.get("levels", 3))
	grid.columns = levels + 1
	grid.add_child(Control.new())
	for l: int in levels:
		var h := _label(SimQuery.t_("ui.upgrades.level_head") % (l + 1), &"CaptionLabel")
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(h)
	var preview := %Preview as UpgradePreview
	for br: Dictionary in branches:
		var head := HBoxContainer.new()
		head.name = "Branch_" + str(br["id"])
		head.add_theme_constant_override("separation", 4)
		head.add_child(_icon(UiIcons.ui(str(BRANCH_ICONS.get(str(br["id"]), "icon_martillo")))))
		head.add_child(_label_fit(SimQuery.t_(str(br["name_key"])), &"BoldLabel"))
		grid.add_child(head)
		var by_level := {}
		for u: Dictionary in br.get("upgrades", []):
			by_level[int(u["level"])] = u
		for l: int in range(1, levels + 1):
			if not by_level.has(l):
				grid.add_child(Control.new())
				continue
			var u: Dictionary = by_level[l]
			var c := _cell(u, preview.thumbnail(str(u["id"])))
			grid.add_child(c)
			_cells[str(u["id"])] = c


## One cell: [thumbnail] name · price [status icon], the selected one pressed, the gold edge when it is a lit
## prerequisite, the works bar at the bottom.
func _cell(u: Dictionary, thumb: Texture2D) -> Button:
	var id := str(u["id"])
	var st := str(u["status"])
	var b := Button.new()
	b.name = id
	b.custom_minimum_size = CELL_SIZE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.set_pressed_no_signal(id == selected)
	b.tooltip_text = "%s · %s" % [SimQuery.t_(str(u["name_key"])), _status_text(st)]
	b.pressed.connect(select.bind(id))
	b.mouse_entered.connect(func() -> void:
		_hover = id
		_mark_prereqs(id))
	b.mouse_exited.connect(func() -> void:
		if _hover == id:
			_hover = ""
			_mark_prereqs(selected))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := TextureRect.new()
	th.name = "Thumb"
	th.custom_minimum_size = Vector2(20, 20)
	th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	th.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	th.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.texture = thumb if thumb != null else UiIcons.ui(str(BRANCH_ICONS.get(str(u["branch"]), "icon_martillo")))
	if st in LOCKED or (st == "busy" and not waits_for_works(id)):
		th.modulate = Color(1, 1, 1, 0.45)
	row.add_child(th)
	var name_l := _label(SimQuery.t_(str(u["name_key"])), &"SmallLabel")
	name_l.name = "Name"
	name_l.max_lines_visible = 2   # a long name takes two lines, never cut
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.add_theme_color_override("font_color", _status_color("needs_upgrade" if st == "busy" and not waits_for_works(id) else st))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)
	if cross_branch(id):
		var k := _icon(UiIcons.ui("icon_llave"))
		k.name = "Cross"
		row.add_child(k)
	var price := Label.new()
	price.name = "Price"
	price.theme_type_variation = &"SmallLabel"
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if st == "owned" or st == "in_works":
		price.text = ""
	elif st == "busy" and waits_for_works(id):
		price.text = SimQuery.t_("ui.upgrades.one_at_a_time")
		price.theme_type_variation = &"DimLabel"
	else:
		price.text = str(int(u["cost"].get("gold", 0)))
		price.theme_type_variation = &"GoldLabel"
		if st in SHORT:
			price.add_theme_color_override("font_color", Color.html(StationMenu._token("negativo")))
	price.visible = price.text != ""
	row.add_child(price)
	var ic := _cell_icon(id, st)
	if ic != "":
		var s := _icon(UiIcons.ui(ic))
		s.name = "Status"
		row.add_child(s)
	else:
		var dot := Control.new()
		dot.name = "Status"
		dot.custom_minimum_size = Vector2(16, 16)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dim := Color.html(StationMenu._token("texto_apagado"))
		dot.draw.connect(func() -> void: dot.draw_circle(Vector2(8, 8), 2.5, dim))
		row.add_child(dot)
	b.add_child(row)
	_fill(row, 3)
	var edge := Panel.new()
	edge.name = "Prereq"
	edge.theme_type_variation = &"FrameActive"
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.visible = false
	b.add_child(edge)
	_fill(edge, 0)
	if st == "in_works":
		var w: Dictionary = _view.get("work", {})
		var bar := ColorRect.new()
		bar.name = "WorksBar"
		bar.color = Color.html(StationMenu._token("aviso"))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.offset_top = -2
		bar.anchor_right = clampf(float(w.get("progress", 0.0)), 0.0, 1.0)
		b.add_child(bar)
	return b


## Whether `id` is held back only by the works in progress (its prerequisite upgrades are built): its cell says «one at
## a time»; a busy one that also lacks a prerequisite keeps its price and its lock.
func waits_for_works(id: String) -> bool:
	for r: Variant in sim.catalog.upgrade(id).get("requires", {}).get("upgrades", []):
		if not Upgrades.has(sim.state, building, str(r)):
			return false
	return true


## The icon of a cell: the status's, a lock for a busy one that also lacks a prerequisite.
func _cell_icon(id: String, st: String) -> String:
	if st == "busy" and not waits_for_works(id):
		return "icon_locked"
	return status_icon(st)


## Lights with a gold edge the prerequisites of `id` (none for "").
func _mark_prereqs(id: String) -> void:
	var req: Array = sim.catalog.upgrade(id).get("requires", {}).get("upgrades", []) if id != "" else []
	for cid: String in _cells:
		var e := (_cells[cid] as Node).get_node_or_null("Prereq") as Control
		if e != null:
			e.visible = cid in req


## Whether the cell of `id` has its prerequisite edge lit now (tests).
func prereq_marked(id: String) -> bool:
	var c := cell_of(id)
	var e := c.get_node_or_null("Prereq") as Control if c != null else null
	return e != null and e.visible


## The cell under the mouse lights its prerequisites (the tests call it as the hover does).
func hover(id: String) -> void:
	_hover = id
	_mark_prereqs(id if id != "" else selected)


func _status_text(status: String) -> String:
	if status in ["owned", "in_works", "available"]:
		return SimQuery.t_("ui.upgrades.status." + status)
	return SimQuery.t_("ui.upgrades.status.blocked") % SimQuery.reason_text(status)


# --- detail ----------------------------------------------------------------------------------------------------------

## The detail of the selected upgrade (see the class doc).
func _show_detail() -> void:
	var lines := %DetailLines as VBoxContainer
	for c: Node in lines.get_children():
		lines.remove_child(c)
		c.queue_free()
	var u := _entry(selected)
	(%Detail as Control).visible = not u.is_empty()
	if u.is_empty():
		return
	var cat := sim.catalog
	var st := str(u["status"])
	(%DetailTitle as Label).text = SimQuery.t_(str(u["name_key"]))
	(%DetailBranch as Label).text = SimQuery.t_("ui.upgrades.branch_level") % [SimQuery.branch_name(str(u["branch"])),
		int(u["level"])]
	var status_label := %DetailStatus as Label
	status_label.text = _status_text(st)
	status_label.add_theme_color_override("font_color", _status_color(st) if not st in LOCKED else
		Color.html(StationMenu._token("negativo")))
	var preview := %Preview as UpgradePreview
	preview.show_upgrade(selected)
	var eff := _label(SimQuery.t_("ui.upgrades.effect_line") % effect_line(selected))
	eff.name = "Effects"
	lines.add_child(eff)
	lines.add_child(_cost_row(u))
	lines.add_child(_requires_row(u))
	var works := _label(works_line(u), &"DimLabel")
	works.name = "Works"
	lines.add_child(works)
	var sees := _label(sees_line(selected), &"DimLabel")
	sees.name = "Sees"
	lines.add_child(sees)
	if str(u["branch"]) == "secrets":
		var risk := 0.0
		for e: Dictionary in u.get("effects", []):
			if str(e.get("kind", "")) == "inspection_risk":
				risk += float(e.get("amount", 0.0))
		var w := _label(SimQuery.t_("ui.upgrades.illegal") % roundi(risk * 100.0) if risk > 0.0
			else SimQuery.t_("ui.upgrades.illegal_norisk"), &"ReasonLabel")
		w.name = "Illegal"
		lines.add_child(w)
	var miss := %Missing as Label
	miss.text = missing_text(selected)
	miss.visible = miss.text != ""
	var buy_b := %BuyButton as Button
	buy_b.visible = st != "owned" and st != "in_works"
	buy_b.disabled = st != "available"
	buy_b.tooltip_text = SimQuery.t_("ui.upgrades.buy_tip") if st == "available" else miss.text


## The effects of `id` in words, each with its consequence in figures when the effect gives one: «New station: Second
## anvil: two people can work at once» · «Production speed ×1,2: the sword goes from 3 h 54 to 3 h 15» · «Storage +10
## stacks: from 10 to 20» · «Employee places +1: 2 places».
func effect_line(id: String) -> String:
	var parts: PackedStringArray = []
	for e: Dictionary in sim.catalog.upgrade(id).get("effects", []):
		var t := SimQuery.effect_text(sim.catalog, e)
		var more := consequence(id, e)
		parts.append(t + (": " + more if more != "" else ""))
	return " · ".join(parts)


## The view's sum of one effect (presentation only, on the effect's figure and the base data); "" when there is none.
func consequence(id: String, e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	match kind:
		"production_speed":
			var rid := _slow_recipe()
			if rid == "":
				return ""
			var base := float(sim.catalog.recipes()[rid].get("duration_hours", 1.0)) * 60.0
			var now := base / maxf(Upgrades.mult(sim, building, kind), 0.01)
			var after := base / maxf(Upgrades.mult_if(sim, building, kind, id), 0.01)
			if Upgrades.has(sim.state, building, id):
				return SimQuery.t_("ui.upgrades.cons.speed_now") % [SimQuery.recipe_name(sim.catalog, rid),
					SimQuery.duration_label(roundi(now))]
			return SimQuery.t_("ui.upgrades.cons.speed") % [SimQuery.recipe_name(sim.catalog, rid),
				SimQuery.duration_label(roundi(now)), SimQuery.duration_label(roundi(after))]
		"extra_storage":
			var lim := int(sim.state.buildings.get(building, {}).get("inventory", {}).get("limit", 0))
			if Upgrades.has(sim.state, building, id):
				return ""
			return SimQuery.t_("ui.upgrades.cons.storage") % [lim, lim + int(e.get("amount", 0))]
		"max_employees":
			var s := SimQuery.slots(sim.state, building)
			return SimQuery.t_("ui.upgrades.cons.slots") % (s if Upgrades.has(sim.state, building, id) else s + int(e.get("amount", 0)))
		"new_zone":
			return SimQuery.t_("ui.upgrades.cons.zone") % SimQuery.zone_name(str(e.get("like", e.get("zone", "")))).to_lower()
	return ""


## The building's recipe that takes longest among those it can make (the speed's example).
func _slow_recipe() -> String:
	var best := ""
	var best_h := -1.0
	for rid: Variant in SimQuery.building_recipes(sim.state, sim.catalog, building):
		var r: Dictionary = sim.catalog.recipes()[str(rid)]
		var need := str(r.get("requires_upgrade", ""))
		if need != "" and not Upgrades.has(sim.state, building, need):
			continue
		if float(r.get("duration_hours", 0.0)) > best_h:
			best_h = float(r.get("duration_hours", 0.0))
			best = str(rid)
	return best


## The cost item by item: gold (you have N), each material (there are N in the storage, any quality), a tick or a
## warning on each.
func _cost_row(u: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.name = "Cost"
	row.add_theme_constant_override("h_separation", 4)
	row.add_child(_label_fit(SimQuery.t_("ui.upgrades.cost_head"), &"BoldLabel"))
	var owned := str(u["status"]) in ["owned", "in_works"]
	var gold := int(u["cost"].get("gold", 0))
	var have_g := _gold()
	row.add_child(_icon(UiIcons.ui("icon_oro")))
	row.add_child(_label_fit(SimQuery.t_("ui.upgrades.cost_gold") % [gold, have_g], &"" if owned or have_g >= gold else &"ReasonLabel"))
	if not owned:
		row.add_child(_icon(UiIcons.ui("icon_completed" if have_g >= gold else "icon_warning")))
	var inv: Dictionary = sim.state.buildings.get(building, {}).get("inventory", {})
	for c: Dictionary in u["cost"].get("items", []):
		var item := str(c["item"])
		var have := Inventory.count(inv, item)
		var ic := UiIcons.item_rect(item)
		if ic != null:
			row.add_child(ic)
		row.add_child(_label_fit(SimQuery.t_("ui.upgrades.cost_item") % [int(c["qty"]), SimQuery.item_name(sim.catalog, item),
			have], &"" if owned or have >= int(c["qty"]) else &"ReasonLabel"))
		if not owned:
			row.add_child(_icon(UiIcons.ui("icon_completed" if have >= int(c["qty"]) else "icon_warning")))
	return row


## The requirements, each with a tick or a warning: the upgrades (a click on one chooses it), the attribute of who
## signs, the family's title; «none».
func _requires_row(u: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.name = "Requires"
	row.add_theme_constant_override("h_separation", 4)
	row.add_child(_label_fit(SimQuery.t_("ui.upgrades.requires_head"), &"BoldLabel"))
	var req: Dictionary = u.get("requires", {})
	var any := false
	for r: Variant in req.get("upgrades", []):
		any = true
		var rid := str(r)
		var ok := Upgrades.has(sim.state, building, rid)
		var l := _label_fit(SimQuery.upgrade_name(sim.catalog, rid) + " (" + SimQuery.branch_name(
			str(sim.catalog.upgrade(rid).get("branch", ""))) + " " + str(int(sim.catalog.upgrade(rid).get("level", 0))) + ")",
			&"" if ok else &"ReasonLabel")
		l.name = "Req_" + rid
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		l.tooltip_text = SimQuery.t_("ui.upgrades.choose_tip")
		l.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				select(rid))
		row.add_child(l)
		row.add_child(_icon(UiIcons.ui("icon_completed" if ok else "icon_warning")))
	var stat: Variant = req.get("stat", null)
	if stat is Dictionary:
		any = true
		var who := actor()
		var have := int(sim.state.characters.get(who, {}).get("stats", {}).get(str(stat["id"]), 0))
		row.add_child(_label_fit(SimQuery.t_("ui.upgrades.req_stat_who") % [SimQuery.t_("stat." + str(stat["id"])),
			int(stat["min"]), str(sim.state.characters.get(who, {}).get("name", "")), have],
			&"" if have >= int(stat["min"]) else &"ReasonLabel"))
		row.add_child(_icon(UiIcons.ui("icon_completed" if have >= int(stat["min"]) else "icon_warning")))
	if req.get("title", null) != null:
		any = true
		var fam := SimQuery.building_family(sim.state, building)
		var mine := Upgrades.family_title(sim, fam)
		var ok := Upgrades.title_rank(sim, mine) >= Upgrades.title_rank(sim, str(req["title"]))
		row.add_child(_icon(UiIcons.ui("icon_crown")))
		row.add_child(_label_fit(SimQuery.t_("ui.upgrades.req_title_have") % [SimQuery.title_name(str(req["title"])),
			SimQuery.title_name(mine)], &"" if ok else &"ReasonLabel"))
		row.add_child(_icon(UiIcons.ui("icon_completed" if ok else "icon_warning")))
	if not any:
		row.add_child(_label_fit(SimQuery.t_("ui.upgrades.none"), &"DimLabel"))
	return row


## «Works: 1 day. The Forge does not produce: the queue stops; wages are paid all the same. Ends day 4 · 10:00.»
func works_line(u: Dictionary) -> String:
	var st := str(u["status"])
	var bname := SimQuery.building_label(sim.state, sim.catalog, building)
	if st == "owned":
		return SimQuery.t_("ui.upgrades.works_done")
	var w: Dictionary = _view.get("work", {})
	if st == "in_works":
		var mode := Upgrades.mode_of(sim.state, building)  # Equilibrio 9: night, half or (a save from before) closed
		if mode == Upgrades.NIGHT:
			return SimQuery.t_("ui.upgrades.works_now_night") % [SimQuery.minute_label(int(w.get("end", 0))).to_lower(),
				bname]
		return SimQuery.t_("ui.upgrades.works_now_half" if mode == Upgrades.HALF else "ui.upgrades.works_now") % [
			SimQuery.minutes_left_label(int(w.get("minutes_left", 0))), SimQuery.minute_label(int(w.get("end", 0))).to_lower()]
	var end := SimQuery.minute_label(end_minute(str(u["id"]))).to_lower()
	match Upgrades.works_mode(sim, str(u["id"])):
		Upgrades.NIGHT:
			return SimQuery.t_("ui.upgrades.works_line_night") % [end, bname]
		Upgrades.HALF:
			return SimQuery.t_("ui.upgrades.works_line_half") % [days_label(float(u["build_days"])), bname, end]
	return SimQuery.t_("ui.upgrades.works_line") % [days_label(float(u["build_days"])), bname, end]


## «1 day», «1,5 days», «12 h» (under a day) of a works' length in days.
func days_label(days: float) -> String:
	if days < 1.0:
		return SimQuery.hours_label(days * 24.0)
	var n := str(int(days)) if is_equal_approx(days, roundf(days)) else String.num(days, 1).replace(".", ",")
	return SimQuery.t_("ui.upgrades.day_one" if is_equal_approx(days, 1.0) else "ui.upgrades.days_n") % n


## When the works of `id` would end if started now.
func end_minute(id: String) -> int:
	return Upgrades.would_end(sim, id, int(sim.state.clock["minute"]))  # Equilibrio 9: the small ones at night


## «What you will see»: lit in gold in the room, on the facade, or nothing to see.
func sees_line(id: String) -> String:
	var side := (%Preview as UpgradePreview).side_of(id)
	if side == "":
		return SimQuery.t_("ui.upgrades.sees_nothing")
	if Upgrades.has(sim.state, building, id):
		return SimQuery.t_("ui.upgrades.sees_built")
	return SimQuery.t_("ui.upgrades.sees_" + side)


## Why `id` cannot be built now, with the figure: «Missing: 3 iron ingots in the storage», «You are 15 gold short»,
## «Other works are going on (one at a time)», «Needs Stone facade (Facade 1)», «Craft 6 (Hugo has 5)», «Title
## Citizen (you are Commoner)»; "" when it can (or it is built / being built).
func missing_text(id: String) -> String:
	var u := _entry(id)
	var st := str(u.get("status", ""))
	var cat := sim.catalog
	match st:
		"", "owned", "in_works", "available":
			return ""
		"missing_materials":
			var inv: Dictionary = sim.state.buildings.get(building, {}).get("inventory", {})
			var parts: PackedStringArray = []
			for c: Dictionary in u["cost"].get("items", []):
				var short := int(c["qty"]) - Inventory.count(inv, str(c["item"]))
				if short > 0:
					parts.append("%d %s" % [short, SimQuery.item_name(cat, str(c["item"]))])
			return SimQuery.t_("ui.upgrades.miss.materials") % ", ".join(parts)
		"not_enough_gold":
			return SimQuery.t_("ui.upgrades.miss.gold") % (int(u["cost"].get("gold", 0)) - _gold())
		"busy":
			return SimQuery.t_("ui.upgrades.miss.busy")
		"needs_upgrade":
			for r: Variant in u.get("requires", {}).get("upgrades", []):
				if not Upgrades.has(sim.state, building, str(r)):
					return SimQuery.t_("ui.upgrades.miss.upgrade") % [SimQuery.upgrade_name(cat, str(r)),
						SimQuery.branch_name(str(cat.upgrade(str(r)).get("branch", ""))), int(cat.upgrade(str(r)).get("level", 0))]
		"stat_too_low":
			var stat: Dictionary = u.get("requires", {}).get("stat", {})
			var who := actor()
			return SimQuery.t_("ui.upgrades.miss.stat") % [SimQuery.t_("stat." + str(stat.get("id", ""))), int(stat.get("min", 0)),
				str(sim.state.characters.get(who, {}).get("name", "")),
				int(sim.state.characters.get(who, {}).get("stats", {}).get(str(stat.get("id", "")), 0))]
		"title_too_low":
			return SimQuery.t_("ui.upgrades.miss.title") % [SimQuery.title_name(str(u.get("requires", {}).get("title", ""))),
				SimQuery.title_name(Upgrades.family_title(sim, SimQuery.building_family(sim.state, building)))]
	return SimQuery.reason_text(st)


## The works in progress: what is being built, its bar and when it ends; without works, «No works: one at a time».
func _show_works(w: Dictionary) -> void:
	(%DoneLabel as Label).text = SimQuery.t_("ui.upgrades.done_count") % (_view.get("owned", []) as Array).size()
	var bar := %WorksBar as ProgressBar
	bar.visible = not w.is_empty()
	(%WorksIcon as TextureRect).texture = UiIcons.ui("icon_martillo" if not w.is_empty() else "icon_completed")
	if w.is_empty():
		(%WorksLabel as Label).text = SimQuery.t_("ui.upgrades.no_works_line") % SimQuery.building_label(sim.state,
			sim.catalog, building)
		return
	(%WorksLabel as Label).text = SimQuery.t_("ui.upgrades.works_strip") % [SimQuery.upgrade_name(sim.catalog,
		str(w.get("upgrade", ""))), SimQuery.minutes_left_label(int(w.get("minutes_left", 0))),
		SimQuery.minute_label(int(w.get("end", 0))).to_lower()]
	bar.value = float(w.get("progress", 0.0)) * 100.0


## The inspections of the building, when it has a risk or a history (GDD 4.8, Secrets branch).
func _show_inspections() -> void:
	var l := %InspectionLabel as Label
	var iv := SimQuery.inspection_view(sim, building)
	var on := float(iv.get("risk", 0.0)) > 0.0 or int(iv.get("caught", 0)) > 0 or int(iv.get("escaped", 0)) > 0
	l.visible = on
	if not on:
		return
	var t: String = SimQuery.t_("ui.upgrades.inspections") % [roundi(float(iv.get("risk", 0.0)) * 100.0),
		int(iv.get("caught", 0)), int(iv.get("escaped", 0)), int(iv.get("fines", 0))]
	if Upgrades.flag(sim, building, "inspection_escape"):
		t += " · " + SimQuery.t_("ui.upgrades.passage_ready" if bool(iv.get("can_escape", false)) else "ui.upgrades.passage_wait")
	l.text = t


# --- pieces ----------------------------------------------------------------------------------------------------------

## Anchors `c` to its parent's whole rect with `pad` px each side (after add_child: the offsets are the pad).
func _fill(c: Control, pad: int) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = pad
	c.offset_top = 0
	c.offset_right = -pad
	c.offset_bottom = 0

func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _label_fit(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _icon(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(16, 16)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# --- orders ----------------------------------------------------------------------------------------------------------

## Build always asks first in the confirmation modal (buy_spec: it is dear and cannot be cancelled); without the HUD's
## modal (tests) it gives the order.
func buy(upgrade: String) -> void:
	if upgrade == "":
		return
	var o := {"type": "buy_upgrade", "actor": actor(), "building": building, "upgrade": upgrade}
	if is_inside_tree() and ConfirmModal.ask_in(get_tree(), buy_spec(upgrade), func() -> void: _give(o)):
		return
	_give(o)


## The confirmation of building `id`: every figure, how long the building does not produce and until when.
func buy_spec(id: String) -> Dictionary:
	var u := sim.catalog.upgrade(id)
	var cost: PackedStringArray = [SimQuery.t_("ui.upgrades.gold") % int(u.get("cost", {}).get("gold", 0))]
	for c: Dictionary in u.get("cost", {}).get("items", []):
		cost.append("%d %s" % [int(c["qty"]), SimQuery.item_name(sim.catalog, str(c["item"]))])
	var keys := {Upgrades.NIGHT: "ui.upgrades.confirm_body_night", Upgrades.HALF: "ui.upgrades.confirm_body_half"}
	var key := str(keys.get(Upgrades.works_mode(sim, id), "ui.upgrades.confirm_body"))
	var body := SimQuery.t_(key) % [SimQuery.upgrade_name(sim.catalog, id), ", ".join(cost),
		SimQuery.building_label(sim.state, sim.catalog, building), days_label(float(u.get("build_days", 0.0))),
		SimQuery.minute_label(end_minute(id)).to_lower()]
	return {"title": SimQuery.t_("ui.upgrades.confirm_title") % SimQuery.upgrade_name(sim.catalog, id), "body": body,
		"action": SimQuery.t_("ui.upgrades.build"), "irreversible": true, "seal": true}


func _give(o: Dictionary) -> void:
	ViewConfig.info("UpgradePanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""  # show the effect as soon as the sim has it
