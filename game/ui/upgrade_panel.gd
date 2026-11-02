class_name UpgradePanel
extends PanelContainer
## Upgrade tree of a building (H5, GDD 4.8 and 4.6.4 "Mejoras"): the 8 branches as rows and their 3 levels as cells,
## coloured by status (built / under construction / available / locked, data/view.json upgrades.status_colors). A
## click on a cell shows its detail: branch and level, cost in gold and materials (with what the storage has),
## requirements (upgrades, attribute, title), works time, effects and its status with the reason when it is locked;
## Buy gives buy_upgrade (only when Upgrades.status_of says "available"). On top, the works in progress with their
## bar and the time left; at the bottom, the inspections of the building when it has a risk or a history
## (Inspections.view). Reads only SimQuery (Upgrades.tree_view); every change is an order through order_sink, signed
## by the selected person if they belong to the building's family, else by its first member.

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var preferred: String = ""   # the person selected (signs the orders if they are of the building's family)
var selected: String = ""    # the upgrade whose detail is shown
var _cells: Dictionary = {}  # upgrade id -> Button
var _view: Dictionary = {}   # the last Upgrades.tree_view
var _sig: String = ""
var _bound: bool = false


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
	(%BuyButton as Button).text = SimQuery.t_("ui.upgrades.buy")
	(%BuyButton as Button).tooltip_text = SimQuery.t_("ui.upgrades.buy_tip")
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
	var sig := JSON.stringify(plain) + selected
	_view = v
	_show_works(v.get("work", {}))
	if not force and sig == _sig:
		return
	_sig = sig
	if selected == "" or _entry(selected).is_empty():
		selected = _default_selection()
	_build_grid()
	_show_detail()
	_show_inspections()
	reset_size()


## The first available upgrade, else the first one not built, else the first.
func _default_selection() -> String:
	var first := ""
	var not_owned := ""
	for br: Dictionary in _view.get("branches", []):
		for u: Dictionary in br.get("upgrades", []):
			var st := str(u["status"])
			if first == "":
				first = str(u["id"])
			if st == "available":
				return str(u["id"])
			if not_owned == "" and st != "owned":
				not_owned = str(u["id"])
	return not_owned if not_owned != "" else first


func _status_color(status: String) -> Color:
	var cols: Dictionary = (ViewConfig.value("upgrades", {}) as Dictionary).get("status_colors", {})
	var key := status if status in ["owned", "in_works", "available"] else "blocked"
	return ViewConfig.color(str(cols.get(key, "#808080")))


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
	var corner := _label("", Color(0, 0, 0, 0), false)
	corner.size_flags_horizontal = Control.SIZE_FILL  # the branch column only as wide as its names
	grid.add_child(corner)
	for l: int in levels:
		var h := _label(SimQuery.t_("ui.upgrades.level") % (l + 1), Color(0.85, 0.71, 0.42), false)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(h)
	for br: Dictionary in branches:
		var bl := _label(SimQuery.t_(str(br["name_key"])), Color(0.95, 0.85, 0.6), false)
		bl.size_flags_horizontal = Control.SIZE_FILL
		grid.add_child(bl)
		var by_level := {}
		for u: Dictionary in br.get("upgrades", []):
			by_level[int(u["level"])] = u
		for l: int in range(1, levels + 1):
			if not by_level.has(l):
				grid.add_child(_label("", Color(0, 0, 0, 0), false))
				continue
			var u: Dictionary = by_level[l]
			var id := str(u["id"])
			var b := Button.new()
			b.name = id
			b.text = SimQuery.t_(str(u["name_key"]))
			b.tooltip_text = "%s · %s" % [b.text, _status_text(str(u["status"]))]
			b.clip_text = true
			b.custom_minimum_size = Vector2(118, 0)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.focus_mode = Control.FOCUS_NONE
			b.toggle_mode = true
			b.set_pressed_no_signal(id == selected)
			var col := _status_color(str(u["status"]))
			for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(k, col)
			b.pressed.connect(select.bind(id))
			grid.add_child(b)
			_cells[id] = b


func _status_text(status: String) -> String:
	if status in ["owned", "in_works", "available"]:
		return SimQuery.t_("ui.upgrades.status." + status)
	return SimQuery.t_("ui.upgrades.status.blocked") % SimQuery.reason_text(status)


## The detail of the selected upgrade: name, branch and level, status, cost, requirements, works time, effects, Buy.
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
	status_label.add_theme_color_override("font_color", _status_color(st))
	# cost: gold and the materials of the building's storage (any quality)
	var inv: Dictionary = sim.state.buildings.get(building, {}).get("inventory", {})
	var parts: PackedStringArray = [SimQuery.t_("ui.upgrades.gold") % int(u["cost"].get("gold", 0))]
	var short := false
	for c: Dictionary in u["cost"].get("items", []):
		var have := Inventory.count(inv, str(c["item"]))
		short = short or have < int(c["qty"])
		parts.append(SimQuery.t_("ui.upgrades.item") % [SimQuery.item_name(cat, str(c["item"])), int(c["qty"]), have])
	var cost := _label(SimQuery.t_("ui.upgrades.cost") % ", ".join(parts),
		Color(1.0, 0.6, 0.5) if st in ["missing_materials", "not_enough_gold"] or (short and st != "owned") else Color(0, 0, 0, 0))
	cost.name = "Cost"
	lines.add_child(cost)
	# requirements: upgrades, attribute of the actor, title of the family
	var req: Dictionary = u.get("requires", {})
	var reqs: PackedStringArray = []
	for r: Variant in req.get("upgrades", []):
		reqs.append(SimQuery.upgrade_name(cat, str(r)))
	var stat: Variant = req.get("stat", null)
	if stat is Dictionary:
		var who := actor()
		var have := int(sim.state.characters.get(who, {}).get("stats", {}).get(str(stat["id"]), 0))
		reqs.append(SimQuery.t_("ui.upgrades.req_stat") % [SimQuery.t_("stat." + str(stat["id"])), int(stat["min"]), have])
	if req.get("title", null) != null:
		reqs.append(SimQuery.t_("ui.upgrades.req_title") % SimQuery.title_name(str(req["title"])))
	var req_l := _label(SimQuery.t_("ui.upgrades.requires") % (", ".join(reqs) if not reqs.is_empty() else
		SimQuery.t_("ui.upgrades.none")),
		Color(1.0, 0.6, 0.5) if st in ["needs_upgrade", "stat_too_low", "title_too_low"] else Color(0, 0, 0, 0))
	req_l.name = "Requires"
	lines.add_child(req_l)
	lines.add_child(_label(SimQuery.t_("ui.upgrades.build_time") % SimQuery.hours_label(float(u["build_days"]) * 24.0)))
	var effs: PackedStringArray = []
	for e: Dictionary in u.get("effects", []):
		effs.append(SimQuery.effect_text(cat, e))
	var eff_l := _label(SimQuery.t_("ui.upgrades.effects") % ", ".join(effs), Color(0.85, 0.85, 0.75))
	eff_l.name = "Effects"
	lines.add_child(eff_l)
	var buy_b := %BuyButton as Button
	buy_b.visible = st != "owned" and st != "in_works"
	buy_b.disabled = st != "available"
	buy_b.tooltip_text = SimQuery.t_("ui.upgrades.buy_tip") if st == "available" else SimQuery.reason_text(st)


## The works in progress: what is being built, its bar and the time left.
func _show_works(w: Dictionary) -> void:
	var box := %WorksBox as Control
	box.visible = not w.is_empty()
	if w.is_empty():
		return
	(%WorksLabel as Label).text = "%s · %s" % [SimQuery.t_("ui.upgrades.works") % SimQuery.upgrade_name(sim.catalog,
		str(w.get("upgrade", ""))), SimQuery.t_("ui.upgrades.works_left") % SimQuery.minutes_left_label(int(w.get("minutes_left", 0)))]
	(%WorksBar as ProgressBar).value = float(w.get("progress", 0.0)) * 100.0


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


## Width of the wrapped lines of the detail (the panel's inner width): without it the panel grew past the screen.
const WRAP_WIDTH: float = 440.0


func _label(text: String, color: Color = Color(0, 0, 0, 0), wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(WRAP_WIDTH, 0)   # a wrapped label without a width asks for one word per line
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


# --- orders ----------------------------------------------------------------------------------------------------------

func buy(upgrade: String) -> void:
	if upgrade == "":
		return
	_give({"type": "buy_upgrade", "actor": actor(), "building": building, "upgrade": upgrade})


func _give(o: Dictionary) -> void:
	ViewConfig.info("UpgradePanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""  # show the effect as soon as the sim has it
