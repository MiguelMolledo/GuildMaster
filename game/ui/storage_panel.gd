class_name StoragePanel
extends PanelContainer
## Storage panel of a building (GDD 4.3.4, 4.6.4): the building's stacks (quality as a suffix, "Espada buena") and
## those of the selected person inside, with buttons to move items either way (transfer). The provisional purchase of
## raw materials of H2 (buy_raw) is gone since the market of H3: materials are bought at the stalls (with an errand
## they arrive here). Only gives orders; the sim decides.

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var actor: String = ""   # the selected person inside ("" = nobody: no transfers, no purchase)
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)


func setup(s: Sim, bld: String, who: String) -> void:
	_bind()
	sim = s
	building = bld
	actor = who
	(%Title as Label).text = SimQuery.t_("ui.storage.title") % SimQuery.building_name(s.state, s.catalog, bld)
	refresh(true)


func open() -> void:
	visible = true
	refresh(true)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func set_actor(who: String) -> void:
	if who != actor:
		actor = who
		refresh(true)


func _process(_delta: float) -> void:
	if visible:
		refresh()


## Rebuilds the lists when what they show changed (or always with `force`).
func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var b: Dictionary = sim.state.buildings.get(building, {})
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var sig := str(b.get("inventory", {})) + "|" + actor + "|" + str(ch.get("inventory", {}))
	if sig == _sig and not force:
		return
	_sig = sig
	var inv: Dictionary = b.get("inventory", {})
	(%BuildingLabel as Label).text = SimQuery.t_("ui.storage.building_stacks") % [(inv.get("stacks", []) as Array).size(),
		int(inv.get("limit", 0))]
	_fill(%BuildingList as VBoxContainer, inv, true)
	var has_actor := not ch.is_empty()
	(%CharLabel as Label).visible = has_actor
	(%CharList as Control).visible = has_actor
	if has_actor:
		(%CharLabel as Label).text = SimQuery.t_("ui.storage.carried") % [str(ch.get("name", actor)),
			SimQuery.carried_weight(sim, actor), SimQuery.max_weight(sim, actor)]
		_fill(%CharList as VBoxContainer, ch.get("inventory", {}), false)
	var hint := %Hint as Label
	hint.visible = not has_actor
	hint.text = SimQuery.t_("ui.storage.no_actor")


func _fill(list: VBoxContainer, inv: Dictionary, from_building: bool) -> void:
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var stacks: Array = inv.get("stacks", [])
	if stacks.is_empty():
		var l := Label.new()
		l.text = SimQuery.t_("ui.storage.empty")
		l.modulate = Color(1, 1, 1, 0.6)
		list.add_child(l)
		return
	var seen := {}
	for s: Dictionary in stacks:
		var item := str(s["item"])
		var q := int(s["quality"])
		var key := "%s_%d" % [item, q]
		if seen.has(key):
			continue  # one row per (item, quality): several full stacks show as one total
		seen[key] = true
		var total := Inventory.count(inv, item, q)
		var row := HBoxContainer.new()
		row.name = key
		var icon := UiIcons.item_rect(item)
		if icon != null:
			row.add_child(icon)
		var name_l := Label.new()
		name_l.name = "Name"
		name_l.text = "%s ×%d" % [SimQuery.item_label(sim.catalog, item, q), total]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var spin := SpinBox.new()
		spin.name = "Qty"
		spin.min_value = 1
		spin.max_value = total
		spin.value = total
		spin.custom_minimum_size = Vector2(52, 0)
		row.add_child(spin)
		var btn := Button.new()
		btn.name = "Move"
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = actor == "" or not sim.state.characters.has(actor)
		if from_building:
			btn.text = SimQuery.t_("ui.storage.to_actor")
			btn.tooltip_text = SimQuery.t_("ui.storage.to_actor_tip")
			btn.pressed.connect(func() -> void: move_to_actor(item, q, int(spin.value)))
		else:
			btn.text = SimQuery.t_("ui.storage.to_building")
			btn.tooltip_text = SimQuery.t_("ui.storage.to_building_tip")
			btn.pressed.connect(func() -> void: move_to_building(item, q, int(spin.value)))
		row.add_child(btn)
		list.add_child(row)


## The row of (item, quality) in the building's list (true) or the person's (false), or null.
func row_of(item: String, quality: int, in_building: bool) -> HBoxContainer:
	var list := (%BuildingList if in_building else %CharList) as VBoxContainer
	return list.get_node_or_null("%s_%d" % [item, quality]) as HBoxContainer


func move_to_actor(item: String, quality: int, qty: int) -> void:
	_give({"type": "transfer", "actor": actor, "from": building, "to": actor, "item": item, "quality": quality,
		"qty": qty})


func move_to_building(item: String, quality: int, qty: int) -> void:
	_give({"type": "transfer", "actor": actor, "from": actor, "to": building, "item": item, "quality": quality,
		"qty": qty})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("StoragePanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
