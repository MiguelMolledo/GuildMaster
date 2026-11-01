class_name StationMenu
extends PanelContainer
## Context menu of a station (right click in an interior, GDD 4.4.5 / 4.6.4): Work fast / Work / Work carefully, then
## the station's recipes from Production.recipe_options (lock if "locked", disabled if "missing_inputs" or "no_room",
## the reason in the tooltip) -> work_at. Stop -> stop_work. It only gives orders; the sim decides.

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var building: String = ""
var zone: String = ""
var mode: String = ""


var _bound: bool = false


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%FastButton as Button).pressed.connect(choose_mode.bind("fast"))
	(%NormalButton as Button).pressed.connect(choose_mode.bind("normal"))
	(%CarefulButton as Button).pressed.connect(choose_mode.bind("careful"))
	(%StopButton as Button).pressed.connect(stop)
	(%BackButton as Button).pressed.connect(func() -> void: _show_modes())


## Opens the menu of `zone` for `actor` ("" = nobody of the family inside: nothing to order) at `at` (screen).
func open_for(s: Sim, who: String, bld: String, zone_id: String, at: Vector2 = Vector2.ZERO) -> void:
	_bind()
	sim = s
	actor = who
	building = bld
	zone = zone_id
	mode = ""
	(%Title as Label).text = SimQuery.zone_name(zone_id)
	(%FastButton as Button).text = SimQuery.t_("ui.station.work_fast")
	(%NormalButton as Button).text = SimQuery.t_("ui.station.work")
	(%CarefulButton as Button).text = SimQuery.t_("ui.station.work_careful")
	(%StopButton as Button).text = SimQuery.t_("ui.station.stop")
	(%BackButton as Button).text = SimQuery.t_("ui.back")
	_show_modes()
	position = at
	reset_size()
	visible = true
	ViewConfig.info("StationMenu", "open (building=%s, zone=%s, actor=%s, recipes=%d)" % [bld, zone_id, who,
		recipe_options().size()])


func close() -> void:
	visible = false


func recipe_options() -> Array:
	if sim == null:
		return []
	return SimQuery.recipe_options(sim, actor, building, zone)


## The station where `actor` works in this building ("" if none): Stop is offered then.
func _actor_job_zone() -> String:
	if sim == null or actor == "":
		return ""
	return Production.job_zone(sim, actor, building)


func _show_modes() -> void:
	mode = ""
	var hint := %Hint as Label
	var options := recipe_options()
	var can_work := actor != "" and not options.is_empty()
	hint.visible = not can_work
	if actor == "":
		hint.text = SimQuery.t_("ui.station.no_actor")
	elif options.is_empty():
		hint.text = SimQuery.t_("ui.station.no_recipes")
	for b: String in ["FastButton", "NormalButton", "CarefulButton"]:
		(get_node("%" + b) as Button).visible = can_work
	(%StopButton as Button).visible = _actor_job_zone() != ""
	(%Modes as Control).visible = true
	(%Recipes as Control).visible = false
	reset_size()


## Second step: the station's recipes for `m` (fast / normal / careful).
func choose_mode(m: String) -> void:
	mode = m
	(%RecipesTitle as Label).text = SimQuery.t_("ui.station.choose_recipe") % SimQuery.mode_name(m)
	var list := %RecipeList as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for opt: Dictionary in recipe_options():
		var rid := str(opt.get("recipe", ""))
		var status := str(opt.get("status", "ok"))
		var b := Button.new()
		b.name = rid
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = SimQuery.recipe_name(sim.catalog, rid) + "  " + _inputs_text(rid)
		b.disabled = status != "ok"
		b.tooltip_text = _status_tip(rid, status)
		if status == "locked":
			b.icon = UiIcons.lock()
		b.pressed.connect(choose_recipe.bind(rid))
		list.add_child(b)
	(%Modes as Control).visible = false
	(%Recipes as Control).visible = true
	reset_size()


func recipe_buttons() -> Array:
	return (%RecipeList as VBoxContainer).get_children()


func _inputs_text(rid: String) -> String:
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	var parts: PackedStringArray = []
	for i: Dictionary in rec.get("inputs", []):
		parts.append("%d %s" % [int(i.get("qty", 0)), SimQuery.item_name(sim.catalog, str(i.get("item", "")))])
	return "(" + ", ".join(parts) + ")"


func _status_tip(rid: String, status: String) -> String:
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	var out := SimQuery.recipe_name(sim.catalog, rid)
	var hours := float(rec.get("duration_hours", 0.0))
	out += "\n" + SimQuery.t_("ui.recipe.duration") % hours
	match status:
		"locked":
			out += "\n" + SimQuery.t_("ui.recipe.locked") % int(rec.get("min_craft", 0))
		"missing_inputs":
			out += "\n" + SimQuery.t_("ui.recipe.missing_inputs")
		"no_room":
			out += "\n" + SimQuery.t_("ui.recipe.no_room")
	return out


func choose_recipe(rid: String) -> void:
	if actor == "" or mode == "":
		return
	_give({"type": "work_at", "actor": actor, "building": building, "zone": zone, "recipe": rid, "mode": mode})
	close()


func stop() -> void:
	if actor == "":
		return
	_give({"type": "stop_work", "actor": actor})
	close()


func _give(o: Dictionary) -> void:
	ViewConfig.info("StationMenu", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
