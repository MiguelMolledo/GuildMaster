class_name ProductionPanel
extends PanelContainer
## Production panel of a building (docs/ui/mecanicas/produccion.md; GDD 4.4.1, 4.4.3, 4.7.4), in the management zone,
## with three tabs:
##   Now (default): one row per station: who works there, the recipe and mode, the bar of the cycle with the master
##       touch window in gold, the time left and Stop (stop_work); a free, closed-at-night or under-works station says
##       so. Under them, how many units of the queue's first entry the storage gives for (WorkQueue.can_make).
##   Queue: the employees' queue (WorkQueue.view): each entry with its icon, name, done/total, a bar, its state in
##       words (Working / Waiting / Skipped: reason) and up / down (queue_move) and remove (queue_remove); Loop and
##       Pause say their state in words (queue_loop, queue_pause); at the bottom, fixed, the grid of the building's
##       recipes (icons; the picked one with the gold edge, a locked one with the lock) with the picked one's name and
##       duration, and +1 / +5 / +10 / +siempre (queue_add): «Espada ×5» is 2 clicks.
##   Recipes (read only): the building's chain (iron → ingot → sword) and every recipe with its station and craft,
##       inputs → output, the real duration for you and for each rank, the chances of each quality for you and today's
##       selling price.
## When the queue is stalled a red strip on top (Now and Queue) says why, with the panel that fixes it. Reads only the
## sim; every change is an order through order_sink, signed by the selected person if they belong to the building's
## family, else by its first member.

signal closed
signal panel_requested(panel: String)   # the stalled strip's fix: "staff" / "storage" (the interior opens it)

const QTYS: Array[int] = [1, 5, 10, -1]   # the quantities the UI offers (GDD 4.7.4); -1 = infinite
const TABS: Array[String] = ["now", "queue", "recipes"]
const RANKS: Array[String] = ["apprentice", "journeyman", "master"]

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var preferred: String = ""   # the person selected (signs the queue orders if of the building's family)
var tab: String = "now"
var _rows: Dictionary = {}  # zone -> {label, bar, time, stop, window}
var _entry_rows: Dictionary = {}  # entry id -> row Control
var _queue_sig: String = ""
var _recipes_sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%LoopButton as Button).toggled.connect(func(on: bool) -> void: set_loop(on))
	(%PauseButton as Button).toggled.connect(func(on: bool) -> void: set_paused(on))
	var adds: Array[String] = ["Add1", "Add5", "Add10", "AddInf"]
	for i: int in adds.size():
		(get_node("%" + adds[i]) as Button).pressed.connect(func() -> void: add_selected(QTYS[i]))
	for t: String in TABS:
		_tab_button(t).pressed.connect(show_tab.bind(t))
	(%StalledFix as Button).pressed.connect(func() -> void:
		var p := str((%StalledFix as Button).get_meta("panel", ""))
		if p != "":
			panel_requested.emit(p))


func _tab_button(t: String) -> Button:
	return get_node("%" + {"now": "NowTab", "queue": "QueueTab", "recipes": "RecipesTab"}[t]) as Button


func setup(s: Sim, bld: String, who: String = "") -> void:
	_bind()
	sim = s
	building = bld
	preferred = who
	(%Title as Label).text = SimQuery.t_("ui.production.title") % SimQuery.building_name(s.state, s.catalog, bld)
	if not Inn.is_inn(s, bld) and Upgrades.tree_of(s, bld) != "":  # Equilibrio 13: the workshop's fame
		var fv := WorkshopFame.view(s, bld)
		(%Title as Label).text += "  ·  " + SimQuery.t_("ui.workshop.fame") % ("%.2f" % float(fv["fame"])).replace(".", ",")
		(%Title as Label).tooltip_text = SimQuery.t_("ui.workshop.fame_tip")
		(%Title as Label).mouse_filter = Control.MOUSE_FILTER_PASS
	for t: String in TABS:
		_tab_button(t).text = SimQuery.t_("ui.production.tab." + t)
	(%Hint as Label).text = SimQuery.t_("ui.production.hint_queue")
	(%QueueTitle as Label).text = SimQuery.t_("ui.queue.title")
	(%LoopButton as Button).tooltip_text = SimQuery.t_("ui.queue.loop_tip")
	(%PauseButton as Button).tooltip_text = SimQuery.t_("ui.queue.pause_tip")
	(%AddLabel as Label).text = SimQuery.t_("ui.production.add")
	(%AddInf as Button).text = SimQuery.t_("ui.production.always")
	(%StalledIcon as TextureRect).texture = UiIcons.ui("icon_warning")
	for n: String in ["Add1", "Add5", "Add10", "AddInf"]:
		(get_node("%" + n) as Button).tooltip_text = SimQuery.t_("ui.queue.add_tip")
	var opt := %RecipeOption as OptionButton
	opt.clear()
	var recipes := SimQuery.building_recipes(s.state, s.catalog, bld)
	for i: int in recipes.size():
		opt.add_item(SimQuery.recipe_name(s.catalog, str(recipes[i])), i)
		opt.set_item_metadata(i, str(recipes[i]))
	if not recipes.is_empty():
		opt.select(0)
	_build_grid(recipes)
	_build_stations()
	_queue_sig = ""
	_recipes_sig = ""
	show_tab(tab)


func _build_stations() -> void:
	var list := %Stations as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var zones: Array = sim.state.buildings.get(building, {}).get("zones", {}).keys()
	var order: Array = []
	for z: Dictionary in sim.catalog.buildings().get(str(sim.state.buildings.get(building, {}).get("type", "")), {}).get("zones", []):
		if str(z.get("id", "")) in zones:
			order.append(str(z["id"]))
	for z: Variant in zones:
		if not str(z) in order:
			order.append(str(z))   # a station an upgrade added (new_zone)
	for z: String in order:
		var row := VBoxContainer.new()
		row.name = z
		row.add_theme_constant_override("separation", 1)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 4)
		var cap := Label.new()
		cap.theme_type_variation = &"CaptionLabel"
		cap.text = SimQuery.zone_name(z).to_upper()
		cap.custom_minimum_size = Vector2(64, 0)
		top.add_child(cap)
		var l := Label.new()
		l.name = "Text"
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		top.add_child(l)
		var t := Label.new()
		t.name = "Time"
		t.theme_type_variation = &"DimLabel"
		top.add_child(t)
		var stop := Button.new()
		stop.name = "Stop"
		stop.focus_mode = Control.FOCUS_NONE
		stop.text = SimQuery.t_("ui.station.stop")
		stop.pressed.connect(stop_at.bind(z))
		top.add_child(stop)
		row.add_child(top)
		var bar_box := Control.new()
		bar_box.custom_minimum_size = Vector2(0, 6)
		bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_box.add_child(bar)
		var win := ColorRect.new()
		win.name = "Window"
		win.color = Color.html("#f2d880")
		win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_box.add_child(win)
		row.add_child(bar_box)
		list.add_child(row)
		_rows[z] = {"label": l, "bar": bar, "box": bar_box, "time": t, "stop": stop, "window": win}


## The grid of the building's recipes (Queue tab): one icon button each, the picked one pressed.
func _build_grid(recipes: Array) -> void:
	var grid := %RecipeGrid as HFlowContainer
	for c: Node in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	for r: Variant in recipes:
		var rid := str(r)
		var rec: Dictionary = sim.catalog.recipes().get(rid, {})
		var b := Button.new()
		b.name = rid
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = &"TabButton"
		b.custom_minimum_size = Vector2(24, 22)
		b.icon = VisualPaths.icon_small(str(rec.get("output", {}).get("item", "")))
		if b.icon == null:
			b.text = SimQuery.recipe_name(sim.catalog, rid).left(2)
		b.tooltip_text = SimQuery.recipe_name(sim.catalog, rid)
		b.pressed.connect(func() -> void:
			select_recipe(rid)
			_show_picked())
		grid.add_child(b)
	_show_picked()


func _show_picked() -> void:
	var rid := selected_recipe()
	for b: Node in (%RecipeGrid as HFlowContainer).get_children():
		(b as Button).set_pressed_no_signal(str(b.name) == rid)
	if rid == "":
		(%PickedLabel as Label).text = ""
		return
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	(%PickedLabel as Label).text = "%s · %s" % [SimQuery.recipe_name(sim.catalog, rid),
		SimQuery.duration_label(_employee_minutes(rec))]


## The duration the queue's work takes: the building's first employee's, else a journeyman's (shown as a guide).
func _employee_minutes(rec: Dictionary) -> int:
	var staff := Staff.employees_of(sim.state, building)
	if not staff.is_empty():
		return Production.employee_cycle_minutes(sim, str(staff[0]), rec, "normal")
	return Production.rank_cycle_minutes(sim, building, rec, "normal", "journeyman")


func set_actor(who: String) -> void:
	preferred = who


## Who signs the queue orders ("" if the building has no family with people).
func actor() -> String:
	if sim == null:
		return ""
	return SimQuery.building_actor(sim.state, building, preferred)


func open() -> void:
	visible = true
	_queue_sig = ""
	refresh()
	ViewConfig.info("ProductionPanel", "open (building=%s, actor=%s, tab=%s)" % [building, actor(), tab])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## Shows `t`: "now", "queue" or "recipes".
func show_tab(t: String) -> void:
	tab = t if t in TABS else "now"
	for x: String in TABS:
		_tab_button(x).set_pressed_no_signal(x == tab)
	(%NowPage as Control).visible = tab == "now"
	(%QueuePage as Control).visible = tab == "queue"
	(%RecipesPage as Control).visible = tab == "recipes"
	if tab == "recipes":
		_refresh_recipes()
	refresh()


func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh() -> void:
	if sim == null:
		return
	var zones: Dictionary = sim.state.buildings.get(building, {}).get("zones", {})
	var why := Production.may_work(sim, "", building) if Upgrades.under_works(sim.state, building) else ""
	var night := Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time) == "night"
	for z: String in _rows:
		var r: Dictionary = _rows[z]
		var job := SimQuery.job_view(sim, building, z)
		var occ := str(zones.get(z, {}).get("occupant", ""))
		var text := ""
		var time := ""
		if job.is_empty():
			if why == "under_works":
				text = SimQuery.reason_text("under_works")
			elif occ != "":
				text = _name(occ)
			elif night:
				text = SimQuery.t_("ui.production.night")
			else:
				text = SimQuery.t_("ui.production.free")
		else:
			text = "%s · %s" % [_name(str(job.get("actor", ""))), SimQuery.recipe_name(sim.catalog, str(job.get("recipe", "")))]
			if str(job.get("mode", "normal")) != "normal":
				text += " · " + SimQuery.mode_name(str(job.get("mode", "")))
			if bool(job.get("blocked", false)):
				text += " · " + SimQuery.t_("ui.production.blocked")
			time = _left(z)
		(r["label"] as Label).text = text
		(r["time"] as Label).text = time
		(r["box"] as Control).visible = not job.is_empty()
		(r["bar"] as ProgressBar).value = float(job.get("progress", 0.0))
		var win := r["window"] as ColorRect
		var wf := float(job.get("window_from", -1.0))
		win.visible = not job.is_empty() and wf >= 0.0
		if win.visible:
			var w := (r["box"] as Control).size.x
			win.position = Vector2(roundf(w * wf), 4)
			win.size = Vector2(maxf(2.0, roundf(w * (float(job["window_to"]) - wf))), 2)
			win.modulate.a = 1.0 if bool(job.get("window_open", false)) else 0.5
		(r["stop"] as Button).visible = not job.is_empty()
		if not job.is_empty():
			(r["stop"] as Button).tooltip_text = SimQuery.t_("ui.production.stop_tip")
	_refresh_queue()


func _name(id: String) -> String:
	return str(sim.state.characters.get(id, {}).get("name", id))


## The time left of the job at `zone` ("0 h 42").
func _left(zone: String) -> String:
	var job: Variant = sim.state.buildings.get(building, {}).get("zones", {}).get(zone, {}).get("job")
	if not job is Dictionary:
		return ""
	return SimQuery.duration_label(maxi(0, int(job["end"]) - int(sim.state.clock["minute"])))


## The queue part: rebuilt only when the sim's view of it changed (the buttons must stay pressable).
func _refresh_queue() -> void:
	var q := SimQuery.queue_view(sim, building)
	var loop := bool(q.get("loop", false))
	var paused := bool(q.get("paused", false))
	(%LoopButton as Button).set_pressed_no_signal(loop)
	(%PauseButton as Button).set_pressed_no_signal(paused)
	(%LoopButton as Button).text = SimQuery.t_("ui.production.loop_state") % SimQuery.t_("ui.yes" if loop else "ui.no")
	(%PauseButton as Button).text = SimQuery.t_("ui.production.pause_state") % SimQuery.t_("ui.yes" if paused else "ui.no")
	_tab_button("queue").text = SimQuery.t_("ui.production.tab.queue") + (" II" if paused else "")
	var stalled := str(q.get("stalled", ""))
	var staff := Staff.employees_of(sim.state, building)
	var strip := ""
	var fix := ""
	if stalled != "":
		strip = SimQuery.t_("ui.queue.stalled") % SimQuery.reason_text(stalled)
		fix = {"missing_inputs": "", "storage_full": "storage", "no_worker": "staff", "skill_too_low": "staff"}.get(stalled, "")
		if stalled == "missing_inputs":
			strip += " · " + SimQuery.t_("ui.production.buy_hint")
	elif staff.is_empty() and tab == "queue":
		strip = SimQuery.t_("ui.production.no_staff")
		fix = "staff"
	(%Stalled as Control).visible = strip != "" and tab != "recipes"
	(%StalledLabel as Label).text = strip
	(%StalledFix as Button).visible = fix != ""
	(%StalledFix as Button).set_meta("panel", fix)
	if fix != "":
		(%StalledFix as Button).text = SimQuery.t_("ui.interior.staff" if fix == "staff" else "ui.interior.storage")
	var entries: Array = q.get("entries", [])
	var first := str(entries[0].get("recipe", "")) if not entries.is_empty() else ""
	(%CanMake as Label).text = SimQuery.t_("ui.production.can_make") % [WorkQueue.can_make(sim, building, first),
		SimQuery.recipe_name(sim.catalog, first)] if first != "" else SimQuery.t_("ui.production.queue_empty_now")
	var sig := JSON.stringify(entries)
	if sig == _queue_sig:
		return
	_queue_sig = sig
	var list := %QueueList as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	_entry_rows.clear()
	if entries.is_empty():
		var l := Label.new()
		l.text = SimQuery.t_("ui.queue.empty")
		l.theme_type_variation = &"DimLabel"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(l)
		return
	for i: int in entries.size():
		var row := _entry_row(entries[i], i, entries.size())
		list.add_child(row)
		_entry_rows[str(entries[i]["id"])] = row


## One entry: "1 [icon] Forjar espada  3/10" with ↑ ↓ x, a bar of the units done and its state in words.
func _entry_row(e: Dictionary, i: int, n: int) -> Control:
	var id := str(e["id"])
	var qty := int(e.get("qty", 1))
	var done := int(e.get("done", 0))
	var status := str(e.get("status", ""))
	var rid := str(e.get("recipe", ""))
	var box := PanelContainer.new()
	box.theme_type_variation = &"RowPanel"
	box.name = id
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	box.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	var num := Label.new()
	num.text = str(i + 1)
	num.theme_type_variation = &"DimLabel"
	top.add_child(num)
	var icon := UiIcons.item_rect(str(sim.catalog.recipes().get(rid, {}).get("output", {}).get("item", "")))
	if icon != null:
		top.add_child(icon)
	var l := Label.new()
	l.name = "Text"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text = "%s  %d/%s" % [SimQuery.recipe_name(sim.catalog, rid), done, SimQuery.qty_label(qty)]
	top.add_child(l)
	top.add_child(_small("Up", "↑", SimQuery.t_("ui.queue.up"), move.bind(id, i - 1), i == 0))
	top.add_child(_small("Down", "↓", SimQuery.t_("ui.queue.down"), move.bind(id, i + 1), i == n - 1))
	top.add_child(_small("Remove", "x", SimQuery.t_("ui.queue.remove_tip"), remove.bind(id), false))
	v.add_child(top)
	if qty > 0:
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.custom_minimum_size = Vector2(0, 4)
		bar.show_percentage = false
		bar.max_value = float(qty)
		bar.value = float(mini(done, qty))
		v.add_child(bar)
	var st := Label.new()
	st.name = "State"
	if status == "working":
		st.text = SimQuery.t_("ui.queue.working")
		st.theme_type_variation = &"PositiveLabel"
	elif status == "" or status == "ok":
		st.text = SimQuery.t_("ui.production.waiting")
		st.theme_type_variation = &"DimLabel"
	else:
		st.name = "Warning"
		st.text = SimQuery.t_("ui.production.skipped") % SimQuery.reason_text(status)
		st.theme_type_variation = &"ReasonLabel"
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(st)
	return box


func _small(id: String, text: String, tip: String, cb: Callable, off: bool) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = off
	b.custom_minimum_size = Vector2(18, 0)
	b.pressed.connect(cb)
	return b


## The Recipes tab: the chain of the building and each recipe in full (read only).
func _refresh_recipes() -> void:
	var sig := "%s|%s" % [building, sim.state.buildings.get(building, {}).get("upgrades", [])]
	if sig == _recipes_sig:
		return
	_recipes_sig = sig
	var list := %RecipesList as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var recipes := SimQuery.building_recipes(sim.state, sim.catalog, building)
	var chain := Label.new()
	chain.name = "Chain"
	chain.text = chain_text(recipes)
	chain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chain.theme_type_variation = &"DimLabel"
	list.add_child(chain)
	list.add_child(HSeparator.new())
	var who := actor()
	for r: Variant in recipes:
		list.add_child(_recipe_card(str(r), who))


## «Hierro ×2 → (horno) Lingote → (yunque) Espada»: the longest line of what feeds what in this building.
func chain_text(recipes: Array) -> String:
	var by_output := {}
	for r: Variant in recipes:
		by_output[str(sim.catalog.recipes()[str(r)].get("output", {}).get("item", ""))] = str(r)
	var lines: PackedStringArray = []
	for r: Variant in recipes:
		var rec: Dictionary = sim.catalog.recipes()[str(r)]
		var out := str(rec.get("output", {}).get("item", ""))
		var fed := false
		for r2: Variant in recipes:
			for inp: Dictionary in sim.catalog.recipes()[str(r2)].get("inputs", []):
				fed = fed or str(inp["item"]) == out
		if fed:
			continue   # an intermediate: it shows inside the chain of what uses it
		var steps: PackedStringArray = []
		var cur := str(r)
		var guard := 0
		while cur != "" and guard < 6:
			guard += 1
			var cr: Dictionary = sim.catalog.recipes()[cur]
			steps.insert(0, "(%s) %s" % [SimQuery.zone_name(str(cr.get("zone", ""))).to_lower(),
				SimQuery.item_name(sim.catalog, str(cr.get("output", {}).get("item", "")))])
			var nxt := ""
			for inp: Dictionary in cr.get("inputs", []):
				if by_output.has(str(inp["item"])):
					nxt = str(by_output[str(inp["item"])])
			if nxt == "":
				var first: Dictionary = (cr.get("inputs", []) as Array)[0] if not (cr.get("inputs", []) as Array).is_empty() else {}
				if not first.is_empty():
					steps.insert(0, "%s ×%d" % [SimQuery.item_name(sim.catalog, str(first["item"])), int(first["qty"])])
			cur = nxt
		lines.append(" → ".join(steps))
	return "\n".join(lines)


func _recipe_card(rid: String, who: String) -> VBoxContainer:
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	var box := VBoxContainer.new()
	box.name = "Recipe_" + rid
	box.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var icon := UiIcons.item_rect(str(rec.get("output", {}).get("item", "")))
	if icon != null:
		head.add_child(icon)
	var n := Label.new()
	n.theme_type_variation = &"BoldLabel"
	n.text = SimQuery.recipe_name(sim.catalog, rid)
	head.add_child(n)
	var where := Label.new()
	where.theme_type_variation = &"DimLabel"
	where.text = SimQuery.t_("ui.production.where") % [SimQuery.zone_name(str(rec.get("zone", ""))).to_lower(),
		int(rec.get("min_craft", 1))]
	head.add_child(where)
	box.add_child(head)
	var parts: PackedStringArray = []
	for inp: Dictionary in rec.get("inputs", []):
		parts.append("%s ×%d" % [SimQuery.item_name(sim.catalog, str(inp["item"])), int(inp["qty"])])
	var io := Label.new()
	io.text = "%s → %s ×%d" % [" + ".join(parts), SimQuery.item_name(sim.catalog, str(rec.get("output", {}).get("item", ""))),
		int(rec.get("output", {}).get("qty", 1))]
	io.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(io)
	var times: PackedStringArray = [SimQuery.t_("ui.production.time_you") % SimQuery.duration_label(
		Production.owner_cycle_minutes(sim, building, rec, "normal"))]
	for rank: String in RANKS:
		times.append("%s: %s" % [SimQuery.rank_name(sim.catalog, rank), SimQuery.duration_label(
			Production.rank_cycle_minutes(sim, building, rec, "normal", rank))])
	var t := Label.new()
	t.name = "Times"
	t.theme_type_variation = &"DimLabel"
	t.text = " · ".join(times)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	if who != "":
		var q := Production.quality_view(sim, who, building, "normal")
		var c: Array = q.get("chances", [100, 0, 0])
		var ql := Label.new()
		ql.theme_type_variation = &"DimLabel"
		ql.text = SimQuery.t_("ui.production.quality_you") % [int(c[0]), int(c[1]), int(c[2])]
		box.add_child(ql)
	var item := str(rec.get("output", {}).get("item", ""))
	var p := Label.new()
	p.name = "Price"
	p.theme_type_variation = &"GoldLabel"
	p.text = SimQuery.t_("ui.production.price_today") % [Market.price(sim, item, 0, "sell"),
		String.num(Market.demand(sim, item), 1).replace(".", ",")]
	box.add_child(p)
	return box


## The row of a queue entry (null if not there): tests press its buttons.
func entry_row(entry: String) -> Control:
	return _entry_rows.get(entry, null)


func selected_recipe() -> String:
	var opt := %RecipeOption as OptionButton
	return str(opt.get_item_metadata(opt.selected)) if opt.selected >= 0 else ""


func select_recipe(recipe: String) -> void:
	var opt := %RecipeOption as OptionButton
	for i: int in opt.item_count:
		if str(opt.get_item_metadata(i)) == recipe:
			opt.select(i)
	_show_picked()


# --- orders ----------------------------------------------------------------------------------------------------------

func stop_at(zone: String) -> void:
	var job := SimQuery.job_view(sim, building, zone)
	if job.is_empty():
		return
	_give({"type": "stop_work", "actor": str(job.get("actor", ""))})


func add_selected(qty: int) -> void:
	var r := selected_recipe()
	if r != "":
		add(r, qty)


func add(recipe: String, qty: int) -> void:
	_give({"type": "queue_add", "actor": actor(), "building": building, "recipe": recipe, "qty": qty})


func remove(entry: String) -> void:
	_give({"type": "queue_remove", "actor": actor(), "building": building, "entry": entry})


func move(entry: String, to: int) -> void:
	_give({"type": "queue_move", "actor": actor(), "building": building, "entry": entry, "to": maxi(0, to)})


func set_loop(on: bool) -> void:
	_give({"type": "queue_loop", "actor": actor(), "building": building, "on": on})


func set_paused(on: bool) -> void:
	_give({"type": "queue_pause", "actor": actor(), "building": building, "on": on})


func _give(o: Dictionary) -> void:
	ViewConfig.info("ProductionPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_queue_sig = ""
