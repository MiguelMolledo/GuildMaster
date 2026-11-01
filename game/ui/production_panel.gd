class_name ProductionPanel
extends PanelContainer
## Production panel of a building (H2): every station with who is there, the recipe and mode of the cycle, its
## progress (Production.job_view), the master-touch window and a Stop button (stop_work). The queue of production
## orders of employees arrives with H5 (GDD 4.7.4).

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var _rows: Dictionary = {}  # zone -> {label, bar, stop}
var _bound: bool = false


func setup(s: Sim, bld: String) -> void:
	if not _bound:
		_bound = true
		(%CloseButton as Button).pressed.connect(close)
	sim = s
	building = bld
	(%Title as Label).text = SimQuery.t_("ui.production.title") % SimQuery.building_name(s.state, s.catalog, bld)
	(%Hint as Label).text = SimQuery.t_("ui.production.hint")
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
	refresh()


func open() -> void:
	visible = true
	refresh()


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


func stop_at(zone: String) -> void:
	var job := SimQuery.job_view(sim, building, zone)
	if job.is_empty():
		return
	var o := {"type": "stop_work", "actor": str(job.get("actor", ""))}
	ViewConfig.info("ProductionPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
