class_name ProductionPanel
extends PanelContainer
## Production panel of a building (H2 + H4): every station with who is there, the recipe and mode of the cycle, its
## progress (Production.job_view), the master-touch window and a Stop button (stop_work); then the production queue
## of the employees (GDD 4.7.4, WorkQueue.view): each entry with its recipe, quantity (1 / 5 / 10 / ∞), progress
## (units done) and its warning when it is skipped, with up / down (queue_move) and remove (queue_remove); a recipe
## selector with +1 / +5 / +10 / +∞ (queue_add); Loop (queue_loop) and Pause (queue_pause), and the general warning
## when nothing can be made. Reads only SimQuery; every change is an order through order_sink, signed by the selected
## person if they belong to the building's family, else by its first member.

signal closed

const QTYS: Array[int] = [1, 5, 10, -1]   # the quantities the UI offers (GDD 4.7.4); -1 = infinite

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var preferred: String = ""   # the person selected (signs the queue orders if of the building's family)
var _rows: Dictionary = {}  # zone -> {label, bar, stop}
var _entry_rows: Dictionary = {}  # entry id -> row Control
var _queue_sig: String = ""
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


func setup(s: Sim, bld: String, who: String = "") -> void:
	_bind()
	sim = s
	building = bld
	preferred = who
	(%Title as Label).text = SimQuery.t_("ui.production.title") % SimQuery.building_name(s.state, s.catalog, bld)
	(%Hint as Label).text = SimQuery.t_("ui.production.hint_queue")
	(%QueueTitle as Label).text = SimQuery.t_("ui.queue.title")
	(%LoopButton as Button).text = SimQuery.t_("ui.queue.loop")
	(%LoopButton as Button).tooltip_text = SimQuery.t_("ui.queue.loop_tip")
	(%PauseButton as Button).text = SimQuery.t_("ui.queue.pause")
	(%PauseButton as Button).tooltip_text = SimQuery.t_("ui.queue.pause_tip")
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
	var list := %Stations as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var zones: Array = s.state.buildings.get(bld, {}).get("zones", {}).keys()
	var order: Array = []
	for z: Dictionary in s.catalog.buildings().get(str(s.state.buildings.get(bld, {}).get("type", "")), {}).get("zones", []):
		if str(z.get("id", "")) in zones:
			order.append(str(z["id"]))
	for z: String in order:
		var row := VBoxContainer.new()
		row.name = z
		var top := HBoxContainer.new()
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(l)
		var stop := Button.new()
		stop.focus_mode = Control.FOCUS_NONE
		stop.text = SimQuery.t_("ui.station.stop")
		stop.pressed.connect(stop_at.bind(z))
		top.add_child(stop)
		row.add_child(top)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 5)
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		row.add_child(bar)
		list.add_child(row)
		_rows[z] = {"label": l, "bar": bar, "stop": stop}
	_queue_sig = ""
	refresh()


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
	ViewConfig.info("ProductionPanel", "open (building=%s, actor=%s)" % [building, actor()])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh() -> void:
	if sim == null:
		return
	var zones: Dictionary = sim.state.buildings.get(building, {}).get("zones", {})
	for z: String in _rows:
		var r: Dictionary = _rows[z]
		var job := SimQuery.job_view(sim, building, z)
		var occ := str(zones.get(z, {}).get("occupant", ""))
		var who := str(sim.state.characters.get(occ, {}).get("name", "")) if occ != "" else ""
		var text := SimQuery.zone_name(z) + ": "
		if job.is_empty():
			text += who if who != "" else SimQuery.t_("ui.production.free")
		else:
			var jw := str(sim.state.characters.get(str(job.get("actor", "")), {}).get("name", job.get("actor", "")))
			text += "%s · %s (%s)" % [jw, SimQuery.recipe_name(sim.catalog, str(job.get("recipe", ""))),
				SimQuery.mode_name(str(job.get("mode", "normal")))]
			if bool(job.get("window_open", false)) and not bool(job.get("touched", false)):
				text += " · " + SimQuery.t_("ui.production.window")
		(r["label"] as Label).text = text
		(r["bar"] as ProgressBar).visible = not job.is_empty()
		(r["bar"] as ProgressBar).value = float(job.get("progress", 0.0))
		(r["stop"] as Button).visible = not job.is_empty()
	_refresh_queue()


## The queue part: rebuilt only when the sim's view of it changed (the buttons must stay pressable).
func _refresh_queue() -> void:
	var q := SimQuery.queue_view(sim, building)
	(%LoopButton as Button).set_pressed_no_signal(bool(q.get("loop", false)))
	(%PauseButton as Button).set_pressed_no_signal(bool(q.get("paused", false)))
	var stalled := str(q.get("stalled", ""))
	(%StalledLabel as Label).visible = stalled != ""
	(%StalledLabel as Label).text = SimQuery.t_("ui.queue.stalled") % SimQuery.reason_text(stalled)
	var sig := JSON.stringify(q.get("entries", []))
	if sig == _queue_sig:
		return
	_queue_sig = sig
	var list := %QueueList as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	_entry_rows.clear()
	var entries: Array = q.get("entries", [])
	if entries.is_empty():
		var l := Label.new()
		l.text = SimQuery.t_("ui.queue.empty")
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		list.add_child(l)
		return
	for i: int in entries.size():
		var row := _entry_row(entries[i], i, entries.size())
		list.add_child(row)
		_entry_rows[str(entries[i]["id"])] = row


## One entry: "2. Forjar espada · 3/10" with up / down / remove, a bar of the units done and its warning.
func _entry_row(e: Dictionary, i: int, n: int) -> Control:
	var id := str(e["id"])
	var qty := int(e.get("qty", 1))
	var done := int(e.get("done", 0))
	var status := str(e.get("status", ""))
	var box := PanelContainer.new()
	box.theme_type_variation = &"Panel"
	box.name = id
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	box.add_child(v)
	var top := HBoxContainer.new()
	var l := Label.new()
	l.name = "Text"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = SimQuery.t_("ui.queue.entry") % [i + 1, SimQuery.recipe_name(sim.catalog, str(e.get("recipe", ""))),
		done, SimQuery.qty_label(qty)]
	if status == "working":
		l.text += " · " + SimQuery.t_("ui.queue.working")
		l.add_theme_color_override("font_color", Color(0.75, 0.95, 0.6))
	top.add_child(l)
	top.add_child(_small("Up", "▲", SimQuery.t_("ui.queue.up"), move.bind(id, i - 1), i == 0))
	top.add_child(_small("Down", "▼", SimQuery.t_("ui.queue.down"), move.bind(id, i + 1), i == n - 1))
	top.add_child(_small("Remove", "x", SimQuery.t_("ui.queue.remove"), remove.bind(id), false))
	v.add_child(top)
	if qty > 0:
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.custom_minimum_size = Vector2(0, 5)
		bar.show_percentage = false
		bar.max_value = float(qty)
		bar.value = float(mini(done, qty))
		v.add_child(bar)
	if status != "" and status != "ok" and status != "working":
		var w := Label.new()
		w.name = "Warning"
		w.text = "! " + SimQuery.reason_text(status)
		w.add_theme_color_override("font_color", Color(1.0, 0.7, 0.45))
		v.add_child(w)
	return box


func _small(id: String, text: String, tip: String, cb: Callable, off: bool) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = off
	b.pressed.connect(cb)
	return b


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
