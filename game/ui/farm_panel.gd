class_name FarmPanel
extends PanelContainer
## H12 Patrón (docs/gdd/04d_otras_clases.md 4.22.4.8, docs/ui/mecanicas/campos_y_ganado.md): the farm's panel in the
## manage zone of a building with fields or a pen (the Granja), opened with its bar's «Campos» button (key C):
##  Calendario de siembra: a strip of 8 days from today, each with its season, whether each crop can be sown that day
##    and the day it would be ready if sown then; the days a field becomes ready (and its last day before rotting)
##    are marked on the strip.
##  Campos: a line per field with its state (the station menu's field line).
##  Corral: the herd by animal, heads / capacity, the winter feed in the storage (days) and the young coming.
## Reads the state only (Fields.view, Fields.days_to_ready, Herds.view): the work is given from each field's menu.

signal closed

const STRIP_DAYS: int = 8

var sim: Sim = null
var building: String = ""
var _minute: int = -1
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)


func setup(s: Sim, bld: String) -> void:
	_bind()
	sim = s
	building = bld
	(%Title as Label).text = SimQuery.building_label(s.state, s.catalog, bld)
	refresh()


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _process(_d: float) -> void:
	if not visible or sim == null:
		return
	var m := int(sim.state.clock["minute"]) / 60
	if m != _minute:
		refresh()


## The strip of days: [{day (0-based), season, sow {crop: ready day or -1}, ready [zones ready that day],
## last [zones on their last day that day]}].
func strip() -> Array:
	var out: Array = []
	if sim == null:
		return out
	var time := sim.catalog.time
	var today := Clock.day(int(sim.state.clock["minute"]))
	var rows := Fields.view(sim, building)
	for n: int in STRIP_DAYS:
		var day := today + n
		var season := Clock.season(day * Clock.MINUTES_PER_DAY, time)
		var sow := {}
		for c: String in _sorted(sim.catalog.crops()):
			var crop: Dictionary = sim.catalog.crops()[c]
			if season in (crop.get("sow_seasons", []) as Array):
				var d := Fields.days_to_ready(sim, {"crop": c, "growth": 0.0, "sown_day": day})
				sow[c] = today + d if d >= 0 else -1
		var ready: Array = []
		var last: Array = []
		for r: Dictionary in rows:
			if str(r["state"]) == "growing" and int(r["days_to_ready"]) >= 0 and today + int(r["days_to_ready"]) == day:
				ready.append(str(r["zone"]))
			if str(r["state"]) == "ready" and today + maxi(0, int(r["days_left"]) - 1) == day:
				last.append(str(r["zone"]))
		out.append({"day": day, "season": season, "sow": sow, "ready": ready, "last": last})
	return out


func refresh() -> void:
	if sim == null or not sim.state.buildings.has(building):
		return
	_minute = int(sim.state.clock["minute"]) / 60
	var body := %Body as VBoxContainer
	for c: Node in body.get_children():
		body.remove_child(c)
		c.queue_free()
	if Fields.has_fields(sim, building):
		_section(body, SimQuery.t_("ui.farm.calendar"))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		body.add_child(grid)
		for cell: Dictionary in strip():
			grid.add_child(_day_cell(cell))
		_section(body, SimQuery.t_("ui.farm.fields"))
		for r: Dictionary in Fields.view(sim, building):
			body.add_child(_label("%s · %s" % [SimQuery.zone_name(str(r["zone"])), _field_text(r)]))
	if Herds.has_pen(sim, building):
		_section(body, SimQuery.t_("ui.farm.pen"))
		var hv := Herds.view(sim, building)
		var parts: Array = []
		for a: String in _sorted(hv["herd"]):
			parts.append("%s ×%d" % [SimQuery.item_name(sim.catalog, a), int(hv["herd"][a])])
		body.add_child(_label(SimQuery.t_("ui.farm.herd") % [", ".join(parts) if not parts.is_empty() else "—",
			int(hv["heads"]), int(hv["capacity"])]))
		body.add_child(_label(SimQuery.t_("ui.farm.winter_feed") % int(hv["winter_feed_days"])))
		for a: String in _sorted(hv["young_in"]):
			body.add_child(_label(SimQuery.t_("ui.farm.young") % [SimQuery.item_name(sim.catalog, a),
				maxi(0, int(hv["young_in"][a]))]))
		if int(hv["unfed_days"]) > 0:
			var w := _label(SimQuery.t_("ui.farm.unfed") % int(hv["unfed_days"]))
			w.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
			body.add_child(w)
	if OS.is_debug_build():
		print("[FarmPanel] refresh (building=%s, fields=%d, pen=%s)" % [building, Fields.view(sim, building).size(),
			Herds.has_pen(sim, building)])


func _day_cell(cell: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(80, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var today := Clock.day(int(sim.state.clock["minute"]))
	var head := _label(SimQuery.t_("ui.farm.today") if int(cell["day"]) == today
		else SimQuery.t_("ui.farm.day") % (int(cell["day"]) + 1))
	head.theme_type_variation = &"BoldLabel"
	v.add_child(head)
	v.add_child(_small(SimQuery.t_("season." + str(cell["season"]))))
	var sow: Dictionary = cell["sow"]
	if sow.is_empty():
		v.add_child(_small(SimQuery.t_("ui.farm.no_sowing")))
	for c: String in _sorted(sow):
		var r := int(sow[c])
		v.add_child(_small(SimQuery.t_("ui.farm.sow_ready") % [SimQuery.t_("crop." + c), r + 1] if r >= 0
			else SimQuery.t_("ui.farm.sow_never") % SimQuery.t_("crop." + c)))
	for z: Variant in cell["ready"]:
		var l := _small(SimQuery.t_("ui.farm.field_ready") % SimQuery.zone_name(str(z)))
		l.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
		v.add_child(l)
	for z: Variant in cell["last"]:
		var l := _small(SimQuery.t_("ui.farm.field_last") % SimQuery.zone_name(str(z)))
		l.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
		v.add_child(l)
	return p


func _field_text(r: Dictionary) -> String:
	match str(r["state"]):
		"growing":
			return SimQuery.t_("ui.field.growing") % [int(r["growth"]), int(r["grow"]), int(r["days_to_ready"])]
		"ready":
			return SimQuery.t_("ui.field.ready") % maxi(0, int(r["days_left"]))
		"plowed":
			var d := Fields.sow_preview(sim, "wheat")
			return SimQuery.t_("ui.field.plowed_sow") % d if d >= 0 else SimQuery.t_("ui.field.plowed_wait")
		"rotten":
			return SimQuery.t_("ui.field.rotten")
	return SimQuery.t_("ui.field.fallow")


func _section(body: VBoxContainer, text: String) -> void:
	var l := _label(text)
	l.theme_type_variation = &"BoldLabel"
	body.add_child(l)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _small(text: String) -> Label:
	var l := _label(text)
	l.theme_type_variation = &"SmallLabel"
	return l


static func _sorted(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k
