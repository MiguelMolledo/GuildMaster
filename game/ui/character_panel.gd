class_name CharacterPanel
extends PanelContainer
## The selected person's panel (key I or the HUD button; GDD 4.3.4): gold, carried weight / maximum
## (Equipment.carried_weight / max_weight), the equipment slots (tool, clothes, accessory) with Unequip, and the
## inventory with Equip on items that have a slot. Only gives orders (equip / unequip); the sim decides.
## H8: the age, the buttons Family tree and Court, and the routine editor (GDD 4.10.8, RoutineEditor) of a controlled
## person.

signal closed
signal tree_requested
signal court_requested(id: String)

const SLOTS: Array[String] = ["tool", "clothes", "accessory"]

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var _sig: String = ""
var _bound: bool = false


func setup(s: Sim, who: String) -> void:
	if not _bound:
		_bound = true
		(%CloseButton as Button).pressed.connect(close)
		(%TreeButton as Button).pressed.connect(func() -> void: tree_requested.emit())
		(%CourtButton as Button).pressed.connect(func() -> void: court_requested.emit(actor))
	sim = s
	actor = who
	(%TreeButton as Button).text = SimQuery.t_("ui.family.tree")
	(%CourtButton as Button).text = SimQuery.t_("ui.family.court")
	var editor := %RoutineEditor as RoutineEditor
	editor.order_sink = order_sink
	editor.setup(s, who, who)
	(%SlotsLabel as Label).text = SimQuery.t_("ui.character.equipment")
	(%InvLabel as Label).text = SimQuery.t_("ui.character.inventory")
	refresh(true)


func open() -> void:
	visible = true
	refresh(true)
	if sim != null:
		(%RoutineEditor as RoutineEditor).refresh(true)
		_refresh_family()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func set_actor(who: String) -> void:
	if who != actor:
		actor = who
		(%RoutineEditor as RoutineEditor).setup(sim, who, who)
		refresh(true)


func _process(_delta: float) -> void:
	if visible:
		refresh()
		(%RoutineEditor as RoutineEditor).refresh()
		_refresh_family()


## H8: age and the family buttons (Court only for a single adult).
func _refresh_family() -> void:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	(%FamilyRow as Control).visible = not ch.is_empty()
	if ch.is_empty():
		return
	(%AgeLabel as Label).text = SimQuery.t_("ui.family.age") % Kin.age(sim, actor)
	(%CourtButton as Button).visible = Kin.is_adult(sim, actor) and Kin.is_single(sim.state, actor)


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var sig := actor + "|" + str(ch.get("inventory", {})) + "|" + str(ch.get("equipment", {})) + "|" + str(Money.gold(sim.state, str(ch.get("family", ""))))
	if sig == _sig and not force:
		return
	_sig = sig
	(%Title as Label).text = str(ch.get("name", SimQuery.t_("ui.character.nobody")))
	(%GoldLabel as Label).text = SimQuery.t_("ui.character.gold") % Money.gold(sim.state, str(ch.get("family", "")))  # family purse (H3)
	var w := SimQuery.carried_weight(sim, actor) if not ch.is_empty() else 0.0
	var mx := SimQuery.max_weight(sim, actor) if not ch.is_empty() else 0.0
	(%WeightLabel as Label).text = SimQuery.t_("ui.character.weight") % [w, mx]
	var bar := %WeightBar as ProgressBar
	bar.value = clampf(w / mx, 0.0, 1.0) if mx > 0.0 else 0.0
	var slots := %Slots as VBoxContainer
	_clear(slots)
	var eq: Dictionary = ch.get("equipment", {})
	for slot: String in SLOTS:
		var row := HBoxContainer.new()
		row.name = slot
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var it: Variant = eq.get(slot, null)
		var has := it is Dictionary
		l.text = SimQuery.t_("ui.slot." + slot) + ": " + (SimQuery.item_label(sim.catalog, str(it.get("item", "")),
			int(it.get("quality", 0))) if has else SimQuery.t_("ui.character.empty_slot"))
		row.add_child(l)
		var b := Button.new()
		b.name = "Unequip"
		b.focus_mode = Control.FOCUS_NONE
		b.text = SimQuery.t_("ui.character.unequip")
		b.disabled = not has
		b.pressed.connect(unequip.bind(slot))
		row.add_child(b)
		slots.add_child(row)
	var list := %InvList as VBoxContainer
	_clear(list)
	var stacks: Array = ch.get("inventory", {}).get("stacks", [])
	if stacks.is_empty():
		var l := Label.new()
		l.text = SimQuery.t_("ui.storage.empty")
		l.modulate = Color(1, 1, 1, 0.6)
		list.add_child(l)
	var seen := {}
	for s: Dictionary in stacks:
		var item := str(s["item"])
		var q := int(s["quality"])
		var key := "%s_%d" % [item, q]
		if seen.has(key):
			continue
		seen[key] = true
		var def := sim.catalog.item(item)
		var row := HBoxContainer.new()
		row.name = key
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s ×%d · %s kg" % [SimQuery.item_label(sim.catalog, item, q), Inventory.count(ch["inventory"], item, q),
			String.num(float(def.get("weight", 0.0)), 1)]
		row.add_child(l)
		if def.has("slot"):
			var b := Button.new()
			b.name = "Equip"
			b.focus_mode = Control.FOCUS_NONE
			b.text = SimQuery.t_("ui.character.equip")
			b.tooltip_text = SimQuery.t_("ui.slot." + str(def["slot"]))
			b.pressed.connect(equip.bind(item, q))
			row.add_child(b)
		list.add_child(row)


func _clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


func equip(item: String, quality: int) -> void:
	_give({"type": "equip", "actor": actor, "item": item, "quality": quality})


func unequip(slot: String) -> void:
	_give({"type": "unequip", "actor": actor, "slot": slot})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("CharacterPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
