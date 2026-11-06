class_name StoragePanel
extends PanelContainer
## Storage panel of a building (docs/ui/mecanicas/almacen_y_personaje.md §4.1; GDD 4.3.4, 4.6.4), in the management
## zone. On top the building's squares, every one of them (ItemSlot): its stacks with icon, quantity and quality dot and
## the empty ones, so the capacity is seen without reading; when an upgrade would add more (extra_storage, «Almacén
## ampliado»), a row of locked squares with its name. The errands on their way, with their arrival time. Two shortcuts:
## Drop materials (every raw material or material the person carries) and Take products (the building's products,
## dearest first, while they fit by weight). Under them the bag of the person inside with its weight bar (amber at 90 %,
## red at 100 %). A click on a stack moves all that fits, a right click moves 1; when not all fit it says so («Solo
## caben 3 de 8»). Without anybody of the family inside, a line says why nothing can be moved. Only gives orders
## (transfer); the sim decides.

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var actor: String = ""   # the selected person inside ("" = nobody: no transfers)
var _sig: String = ""
var _bound: bool = false
var _reason_left: float = 0.0


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%DropButton as Button).pressed.connect(drop_materials)
	(%TakeButton as Button).pressed.connect(take_products)


func setup(s: Sim, bld: String, who: String) -> void:
	_bind()
	sim = s
	building = bld
	actor = who
	(%Title as Label).text = SimQuery.t_("ui.storage.title") % SimQuery.building_name(s.state, s.catalog, bld)
	(%DropButton as Button).text = SimQuery.t_("ui.storage.drop_materials")
	(%TakeButton as Button).text = SimQuery.t_("ui.storage.take_products")
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


func _process(delta: float) -> void:
	if visible:
		refresh()
	if _reason_left > 0.0:
		_reason_left -= delta
		if _reason_left <= 0.0:
			(%Reason as Label).visible = false


func _has_actor() -> bool:
	return actor != "" and sim.state.characters.has(actor)


## Rebuilds the grids when what they show changed (or always with `force`).
func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var b: Dictionary = sim.state.buildings.get(building, {})
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var fam := str(b.get("owner", ""))
	var errands := Market.pending(sim, SimQuery.building_family(sim.state, building)) if sim.state.buildings.has(building) else []
	var sig := str(b.get("inventory", {})) + "|" + actor + "|" + str(ch.get("inventory", {})) + "|" + str(errands) + fam
	if (sig == _sig or UiFeel.hold_rebuild(self)) and not force:
		return
	_sig = sig
	var inv: Dictionary = b.get("inventory", {})
	var used := (inv.get("stacks", []) as Array).size()
	var limit := int(inv.get("limit", 0))
	var label := %BuildingLabel as Label
	label.text = SimQuery.t_("ui.storage.building_stacks") % [used, limit]
	label.theme_type_variation = &"ReasonLabel" if used >= limit and limit > 0 else &"BoldLabel"
	_fill_building(inv, limit, errands)
	var has := _has_actor()
	for n: String in ["%CharLabel", "%WeightBar", "%CharGrid", "%Shortcuts"]:
		(get_node(n) as Control).visible = has
	if has:
		var w := SimQuery.carried_weight(sim, actor)
		var mx := SimQuery.max_weight(sim, actor)
		(%CharLabel as Label).text = SimQuery.t_("ui.storage.carries") % [str(ch.get("name", actor)).to_upper(),
			String.num(w, 1), String.num(mx, 0)]
		var bar := %WeightBar as ProgressBar
		bar.value = clampf(w / mx, 0.0, 1.0) if mx > 0.0 else 0.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color.html(StationMenu._token("negativo" if bar.value >= 1.0 else ("aviso" if bar.value > 0.9 else "positivo")))
		bar.add_theme_stylebox_override("fill", fill)
		_fill_bag(ch.get("inventory", {}))
		(%DropButton as Button).disabled = _materials_carried().is_empty()
		(%TakeButton as Button).disabled = _products_stored().is_empty()
		(%DropButton as Button).tooltip_text = SimQuery.t_("ui.storage.drop_tip")
		(%TakeButton as Button).tooltip_text = SimQuery.t_("ui.storage.take_tip")
	(%Hint as Label).text = SimQuery.t_("ui.storage.help") if has else SimQuery.t_("ui.storage.no_actor_why")


func _fill_building(inv: Dictionary, limit: int, errands: Array) -> void:
	var grid := %BuildingGrid as GridContainer
	_clear(grid)
	for s: Dictionary in inv.get("stacks", []):
		var slot := _slot(str(s["item"]), int(s["quality"]), int(s["qty"]), true)
		grid.add_child(slot)
	for i: int in maxi(0, limit - (inv.get("stacks", []) as Array).size()):
		var e := ItemSlot.new()
		e.name = "Empty%d" % i
		e.show_item("")
		grid.add_child(e)
	var extra := _extra_storage()
	(%LockedLine as Label).visible = not extra.is_empty()
	if not extra.is_empty():
		for i: int in int(extra["amount"]):
			var l := ItemSlot.new()
			l.name = "Locked%d" % i
			l.set_locked()
			l.tooltip_text = SimQuery.t_("ui.storage.locked_tip") % str(extra["name"])
			grid.add_child(l)
		(%LockedLine as Label).text = SimQuery.t_("ui.storage.more_with") % [int(extra["amount"]), str(extra["name"])]
	var list := %Errands as VBoxContainer
	_clear(list)
	for d: Dictionary in errands:
		if str(d.get("to", "")) != building:
			continue
		var l := Label.new()
		l.theme_type_variation = &"DimLabel"
		l.text = SimQuery.t_("ui.storage.on_the_way") % [int(d.get("qty", 0)), SimQuery.item_name(sim.catalog, str(d.get("item", ""))).to_lower(),
			SimQuery.minute_label(int(d.get("arrive", 0)))]
		list.add_child(l)


## The upgrade of this building that adds squares and is not done yet: {name, amount}, or {}.
func _extra_storage() -> Dictionary:
	var owned: Array = sim.state.buildings.get(building, {}).get("upgrades", [])
	var tree := Upgrades.tree_of(sim, building)
	if tree == "":
		return {}
	for id: String in sim.catalog.upgrade_tree(tree):
		if id in owned:
			continue
		for e: Dictionary in sim.catalog.upgrade(id).get("effects", []):
			if str(e.get("kind", "")) == "extra_storage":
				return {"id": id, "name": SimQuery.upgrade_name(sim.catalog, id), "amount": int(e.get("amount", 0))}
	return {}


func _fill_bag(inv: Dictionary) -> void:
	var grid := %CharGrid as GridContainer
	_clear(grid)
	for s: Dictionary in inv.get("stacks", []):
		grid.add_child(_slot(str(s["item"]), int(s["quality"]), int(s["qty"]), false))
	var e := ItemSlot.new()
	e.name = "Empty"
	e.show_item("")
	grid.add_child(e)


func _slot(item: String, q: int, n: int, in_building: bool) -> ItemSlot:
	var slot := ItemSlot.new()
	slot.name = "%s_%d" % [item, q]
	slot.show_item(item, q, n)
	var def := sim.catalog.item(item)
	slot.tooltip_text = SimQuery.t_("ui.storage.slot_tip") % [SimQuery.item_label(sim.catalog, item, q), n,
		String.num(float(def.get("weight", 0.0)), 1), String.num(float(def.get("weight", 0.0)) * n, 1),
		Market.price(sim, item, q, "sell")]
	slot.set_meta("in_building", in_building)
	slot.clicked.connect(_on_slot)
	return slot


func _on_slot(slot: ItemSlot, right: bool) -> void:
	if slot.item == "" or not _has_actor():
		return
	var n := 1 if right else slot.qty
	if bool(slot.get_meta("in_building", false)):
		move_to_actor(slot.item, slot.quality, n)
	else:
		move_to_building(slot.item, slot.quality, n)


## The square of (item, quality) in the building's grid (true) or the person's (false), or null.
func row_of(item: String, quality: int, in_building: bool) -> Control:
	var grid := (%BuildingGrid if in_building else %CharGrid) as GridContainer
	return grid.get_node_or_null("%s_%d" % [item, quality]) as Control


func _clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _materials_carried() -> Array:
	var out: Array = []
	for s: Dictionary in sim.state.characters.get(actor, {}).get("inventory", {}).get("stacks", []):
		if str(sim.catalog.item(str(s["item"])).get("category", "")) in ["raw", "material"]:
			out.append(s)
	return out


## The building's products (what its recipes make and none of them uses: sword, hammer, armor; not the ingots), dearest
## first.
func _products_stored() -> Array:
	var made := {}
	var used := {}
	for r: Variant in SimQuery.building_recipes(sim.state, sim.catalog, building):
		var rec: Dictionary = sim.catalog.recipes()[str(r)]
		made[str(rec.get("output", {}).get("item", ""))] = true
		for inp: Dictionary in rec.get("inputs", []):
			used[str(inp["item"])] = true
	var out: Array = []
	for s: Dictionary in sim.state.buildings.get(building, {}).get("inventory", {}).get("stacks", []):
		var it := str(s["item"])
		if (made.has(it) and not used.has(it)) or str(sim.catalog.item(it).get("category", "")) == "product":
			out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Market.price(sim, str(a["item"]), int(a["quality"]), "sell") > Market.price(sim, str(b["item"]), int(b["quality"]), "sell"))
	return out


## Drop materials: one transfer per raw material or material the person carries.
func drop_materials() -> void:
	for s: Dictionary in _materials_carried():
		move_to_building(str(s["item"]), int(s["quality"]), int(s["qty"]))


## Take products: one transfer per product of the storage, dearest first, while they fit by weight (what does not fit
## is left, with the reason).
func take_products() -> void:
	var bag: Dictionary = (sim.state.characters[actor]["inventory"] as Dictionary).duplicate(true)
	var left: PackedStringArray = []
	for s: Dictionary in _products_stored():
		var n := Inventory.fit_count(bag, sim.catalog, str(s["item"]), int(s["quality"]), int(s["qty"]))
		if n > 0:
			Inventory.add(bag, sim.catalog, str(s["item"]), int(s["quality"]), n)
			_give({"type": "transfer", "actor": actor, "from": building, "to": actor, "item": str(s["item"]),
				"quality": int(s["quality"]), "qty": n})
		if n < int(s["qty"]):
			left.append("%d × %s" % [int(s["qty"]) - n, SimQuery.item_label(sim.catalog, str(s["item"]), int(s["quality"])).to_lower()])
	if not left.is_empty():
		_say(SimQuery.t_("ui.storage.left_behind") % ", ".join(left))


## A reason in red under the grids for 2 s.
func _say(text: String) -> void:
	(%Reason as Label).text = text
	(%Reason as Label).visible = true
	_reason_left = 2.5
	ViewConfig.info("StoragePanel", "reason: %s" % text)


func last_reason() -> String:
	return (%Reason as Label).text if (%Reason as Label).visible else ""


func move_to_actor(item: String, quality: int, qty: int) -> void:
	if not _has_actor():
		return
	var bag: Dictionary = sim.state.characters[actor]["inventory"]
	var n := Inventory.fit_count(bag, sim.catalog, item, quality, qty)
	if n < qty:
		var free_kg := maxf(0.0, SimQuery.max_weight(sim, actor) - SimQuery.carried_weight(sim, actor))
		_say(SimQuery.t_("ui.storage.only_fit") % [n, qty, String.num(free_kg, 0)])
	if n <= 0:
		return
	_give({"type": "transfer", "actor": actor, "from": building, "to": actor, "item": item, "quality": quality, "qty": n})


func move_to_building(item: String, quality: int, qty: int) -> void:
	if not _has_actor():
		return
	var inv: Dictionary = sim.state.buildings[building]["inventory"]
	var n := Inventory.fit_count(inv, sim.catalog, item, quality, qty)
	if n < qty:
		_say(SimQuery.t_("ui.storage.full") % [(inv.get("stacks", []) as Array).size(), int(inv.get("limit", 0))])
	if n <= 0:
		return
	_give({"type": "transfer", "actor": actor, "from": actor, "to": building, "item": item, "quality": quality, "qty": n})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("StoragePanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
