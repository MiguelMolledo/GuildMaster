class_name RoutineEditor
extends VBoxContainer
## The routine of a controlled person in its sheet (GDD 4.10.8): one row per phase of the day (Dawn, Day, Dusk, Night)
## with the action (Work / Rest / Free) and, for Work, the recipe ("automatic" = the best one it can make) and the way
## of working. "Turn on" gives the default routine; "Turn off" leaves only manual orders. Every change gives the whole
## routine as one set_schedule order (management). The line on top says what the routine does now and whether a manual
## order is ruling. Only reads Schedules.view and the catalog.

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""   # who gives the order (the selected person)
var who: String = ""     # whose routine
var _sig: String = ""
var _bound: bool = false
var _building: String = ""


func setup(s: Sim, giver: String, person: String) -> void:
	if not _bound:
		_bound = true
		(%ToggleButton as Button).pressed.connect(_toggle)
	sim = s
	actor = giver
	who = person
	(%RoutineTitle as Label).text = SimQuery.t_("ui.routine.title")
	refresh(true)


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var ch: Dictionary = sim.state.characters.get(who, {})
	var ok := not ch.is_empty() and bool(ch.get("alive", true)) and str(ch.get("controlled_by", "")) == "human"
	visible = ok
	if not ok:
		return
	var v := Schedules.view(sim, who)
	var now: Dictionary = v.get("now", {})
	var state_text := SimQuery.t_("ui.routine.now") % [SimQuery.t_("phase." + str(v.get("phase", ""))),
		SimQuery.t_("routine." + str(now.get("action", "free"))) if not now.is_empty() and str(now.get("action", "")) != "idle" \
		else SimQuery.t_("ui.routine.none")]
	if bool(v.get("manual", false)):
		state_text += " · " + SimQuery.t_("ui.routine.manual")
	(%StateLabel as Label).text = state_text
	var sig := "%s|%s|%s" % [who, ch.get("schedule"), actor]
	if sig == _sig and not force:
		return
	_sig = sig
	_building = Kin.assigned_building(sim, who)
	var sched: Variant = ch.get("schedule")
	(%ToggleButton as Button).text = SimQuery.t_("ui.routine.off" if sched is Dictionary else "ui.routine.on")
	var rows := %Rows as GridContainer
	for c: Node in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	rows.visible = sched is Dictionary
	if not sched is Dictionary:
		return
	for ph: String in Clock.PHASES:
		var slot: Dictionary = (sched as Dictionary).get(ph, {"action": "free"})
		var l := Label.new()
		l.text = SimQuery.t_("phase." + ph)
		l.custom_minimum_size = Vector2(54, 0)
		rows.add_child(l)
		var act := _option("Action_" + ph)
		for a: String in sim.catalog.family.get("routine", {}).get("actions", ["work", "rest", "free"]):
			act.add_item(SimQuery.t_("routine." + a))
			act.set_item_metadata(act.item_count - 1, a)
			if a == str(slot.get("action", "free")):
				act.select(act.item_count - 1)
		rows.add_child(act)
		var rec := _option("Recipe_" + ph)
		rec.add_item(SimQuery.t_("ui.routine.auto"))
		rec.set_item_metadata(0, "")
		for r: String in SimQuery.building_recipes(sim.state, sim.catalog, _building):
			rec.add_item(SimQuery.recipe_name(sim.catalog, r))
			rec.set_item_metadata(rec.item_count - 1, r)
			if r == str(slot.get("recipe", "")):
				rec.select(rec.item_count - 1)
		rec.disabled = str(slot.get("action", "")) != "work"
		rows.add_child(rec)
		var mode := _option("Mode_" + ph)
		var modes: Array = (sim.catalog.production.get("modes", {}) as Dictionary).keys()
		modes.sort()
		for m: String in modes:
			mode.add_item(SimQuery.mode_name(m))
			mode.set_item_metadata(mode.item_count - 1, m)
			if m == str(slot.get("mode", "normal")):
				mode.select(mode.item_count - 1)
		mode.disabled = str(slot.get("action", "")) != "work"
		rows.add_child(mode)
		for o: OptionButton in [act, rec, mode]:
			o.item_selected.connect(func(_i: int) -> void: _changed())


func _option(n: String) -> OptionButton:
	var o := OptionButton.new()
	o.name = n
	o.focus_mode = Control.FOCUS_NONE
	o.fit_to_longest_item = false
	o.custom_minimum_size = Vector2(70, 0)
	return o


## The routine as the rows say now.
func current() -> Dictionary:
	var out := {}
	var rows := %Rows as GridContainer
	for ph: String in Clock.PHASES:
		var act := rows.get_node_or_null("Action_" + ph) as OptionButton
		if act == null or act.selected < 0:
			continue
		var slot := {"action": str(act.get_item_metadata(act.selected))}
		if slot["action"] == "work":
			var rec := rows.get_node("Recipe_" + ph) as OptionButton
			var mode := rows.get_node("Mode_" + ph) as OptionButton
			if rec.selected > 0:
				slot["recipe"] = str(rec.get_item_metadata(rec.selected))
			if mode.selected >= 0 and str(mode.get_item_metadata(mode.selected)) != "normal":
				slot["mode"] = str(mode.get_item_metadata(mode.selected))
		out[ph] = slot
	return out


func _changed() -> void:
	_give(current())


func _toggle() -> void:
	var sched: Variant = sim.state.characters.get(who, {}).get("schedule")
	_give(null if sched is Dictionary else Schedules.default_schedule(sim, who))


func _give(sched: Variant) -> void:
	var o := {"type": "set_schedule", "actor": actor, "character": who, "schedule": sched}
	ViewConfig.info("RoutineEditor", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
