extends "res://tests/test_case.gd"
## The forge seen and played by hand (H2, GDD 4.6.4 / 4.4.5 / 4.3): real clicks on the real scenes become the right
## orders, and those orders through the sim have their effect. Windowless: the views are built by hand.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start")["state"], cat)


func _world(sim: Sim) -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat)
	return v


func _interior(sim: Sim, manage: bool = false) -> InteriorView:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, BLD, HUGO, manage)
	return v


func _click(target: Object, button: MouseButton, screen: Vector2, double: bool = false) -> bool:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.double_click = double
	ev.position = screen
	return target.call("handle_input", ev)


func _refusals(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == "order_refused")


func _same(got: Dictionary, want: Dictionary, msg: String) -> void:
	eq(SaveFile.canonical(got), SaveFile.canonical(want), msg)


## Runs the sim until `cond` holds (at most `limit` minutes). Returns every event on the way.
func _run_until(sim: Sim, cond: Callable, limit: int = 600) -> Array:
	var all: Array = []
	for i: int in limit:
		if cond.call():
			break
		all.append_array(sim.step())
	return all


## Hugo goes into the forge the way the game does it (enter_building, walk to the door, in).
func _hugo_inside(sim: Sim) -> void:
	var ev := sim.step([{"type": "enter_building", "actor": HUGO, "building": BLD}])
	ev.append_array(_run_until(sim, func() -> bool: return str(sim.state.characters[HUGO]["location"]) == BLD))
	eq(str(sim.state.characters[HUGO]["location"]), BLD, "Hugo is inside the forge")
	eq(_refusals(ev).size(), 0, "no refusals going in")


func _add(inv: Dictionary, item: String, quality: int, qty: int) -> void:
	check(Inventory.add(inv, cat, item, quality, qty), "setup: add %s x%d" % [item, qty])


## A point on the forge block's left face (3x4 footprint at (25..27, 20..23)).
func _forge_screen(v: WorldView) -> Vector2:
	return v.camera().world_to_screen(Iso.tile_to_world(Vector2i(25, 22)) + Vector2(-16, -14))


# --- the map ---------------------------------------------------------------------------------------------------------

func test_forge_is_drawn_apart_with_sign_and_door() -> void:
	var sim := _sim()
	var v := _world(sim)
	check(v.sign_of(BLD) != null, "the forge has a sign")
	var door := v.overlay().get_node_or_null(BLD + "_door") as Node2D
	check(door != null, "a door mark")
	eq(door.position, Iso.tile_to_world(Vector2i(26, 19)), "on the door tile")
	var forge_color := _greybox_color("buildings", "forge")
	var at_forge := 0
	var house_color := _greybox_color("props", "building")
	for pair: Array in _blocks(v.objects(), Vector2.ZERO):
		var bv: BlockView = pair[0]
		var t := Iso.world_to_tile(pair[1])
		var in_forge := Rect2i(25, 20, 3, 4).has_point(t)
		if in_forge:
			at_forge += 1
			eq(bv.color, forge_color, "forge block colour at %s" % t)
			eq(pair[1], Iso.tile_to_world(t), "each forge block on its own tile (Y-sort by tile)")
		elif t == Vector2i(28, 20):
			eq(bv.color, house_color, "the house next door keeps the greybox colour")
	eq(at_forge, 12, "one forge block per footprint tile")
	v.free()


## The colour of the greybox of a visual scene (game/visuals/<kind>/<id>.tscn).
func _greybox_color(kind: String, id: String) -> Color:
	var n := VisualPaths.instantiate(kind, id)
	var c: Color = n.get_node("Greybox").get("color")
	n.free()
	return c


## Every BlockView under `n` with its position in `n`'s parent layer: [[BlockView, Vector2]].
func _blocks(n: Node, origin: Vector2) -> Array:
	var out: Array = []
	for c: Node in n.get_children():
		if not c is Node2D:
			continue
		var p := origin + (c as Node2D).position
		if c is BlockView:
			out.append([c, p])
		out.append_array(_blocks(c, p))
	return out


func test_right_click_on_forge_with_hugo_selected_enters() -> void:
	var sim := _sim()
	var v := _world(sim)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.camera().center_on(Iso.tile_to_world(Vector2i(24, 21)))
	_click(v, MOUSE_BUTTON_LEFT, v.camera().world_to_screen(v.view_of(HUGO).position + Vector2(0, -20)))
	eq(v.selected_id, HUGO, "Hugo selected")
	check(_click(v, MOUSE_BUTTON_RIGHT, _forge_screen(v)), "right click used")
	eq(got.size(), 1, "one order")
	_same(got[0], {"type": "enter_building", "actor": HUGO, "building": BLD}, "right click on the forge")
	check(_click(v, MOUSE_BUTTON_RIGHT, v.tile_to_screen(Vector2i(26, 19)) + Vector2(4, 2)), "right click on the door")
	_same(got[1], {"type": "enter_building", "actor": HUGO, "building": BLD}, "right click on its door")
	# a plaza tile in front of the forge (scale B: the taller forge now covers the tiles just behind it, like 22,18)
	check(_click(v, MOUSE_BUTTON_RIGHT, v.tile_to_screen(Vector2i(20, 17))), "right click on the street")
	eq(str(got[2]["type"]), "move_to", "the street is still a walk")
	# the order through the sim: he walks to the door and goes in
	var ev := sim.step([got[0]])
	ev.append_array(_run_until(sim, func() -> bool: return str(sim.state.characters[HUGO]["location"]) == BLD))
	eq(_refusals(ev).size(), 0, "the sim takes it")
	check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "building_entered" and e["actor"] == HUGO),
		"building_entered (the game opens the interior on it)")
	v.sync(0.0)
	check(not v.view_of(HUGO).visible, "inside: not drawn on the map")
	eq(v.pick_character(v.camera().world_to_screen(v.view_of(HUGO).position + Vector2(0, -20))), "",
		"and not pickable there")
	v.free()


func test_left_click_picks_forge_and_double_click_manages() -> void:
	var sim := _sim()
	var v := _world(sim)
	var managed: Array = []
	v.manage_requested.connect(func(id: String) -> void: managed.append(id))
	v.select(HUGO)
	v.camera().center_on(Iso.tile_to_world(Vector2i(25, 21)))
	_click(v, MOUSE_BUTTON_LEFT, _forge_screen(v))
	eq(v.picked_building, BLD, "left click picks the forge")
	eq(v.selected_id, HUGO, "and keeps the selected person")
	check((v.sign_of(BLD) as BuildingMarks.Sign).highlighted, "its sign lights up")
	eq(managed.size(), 0, "a single click does not open it")
	_click(v, MOUSE_BUTTON_LEFT, _forge_screen(v), true)
	eq(managed, [BLD], "double click: management mode")
	_click(v, MOUSE_BUTTON_LEFT, v.tile_to_screen(Vector2i(10, 30)))
	eq(v.picked_building, "", "a click elsewhere drops it")
	v.free()


# --- the interior ----------------------------------------------------------------------------------------------------

func test_interior_is_built_from_the_kit_with_the_stations() -> void:
	var sim := _sim()
	_hugo_inside(sim)
	var v := _interior(sim)
	eq(v.size_tiles, Vector2i(10, 8), "size from data/interiors/forge.json (04g 4.6.5.2)")
	eq(v.floor_layer().get_child_count(), 80, "one floor piece per tile (the hidden Kit)")
	eq(v.walls().get_child_count(), 10 + 8, "a wall piece per back edge (the hidden Kit)")
	var door := v.walls().get_node_or_null("Door") as KitWall
	check(door != null and door.door, "the door piece")
	for z: String in ["furnace", "anvil", "counter", "storage"]:
		check(v.station_view(z) != null, "station %s" % z)
	var marker := v.room().get_node("Stations/anvil") as Node2D   # it can be moved in data/interiors/forge.json
	eq(v.station_view("anvil").position, marker.position, "anvil where its Marker2D puts it")
	check(v.view_of(HUGO) != null, "Hugo is drawn inside")
	eq(v.actor(), HUGO, "and is who acts")
	v.free()


func test_station_menu_gives_work_at_with_the_mode() -> void:
	for mode: String in ["fast", "normal", "live"]:  # 03b §3b.2: at the anvil the third button is Forja viva
		var sim := _sim()
		_hugo_inside(sim)
		_add(sim.state.buildings[BLD]["inventory"], "iron_ingot", 0, 2)
		var v := _interior(sim)
		var got: Array = []
		v.order_sink = func(o: Dictionary) -> void: got.append(o)
		check(_click(v, MOUSE_BUTTON_RIGHT, v.station_screen("anvil")), "right click on the anvil")
		var menu := v.station_menu()
		check(menu.visible, "the station menu opens")
		eq(menu.zone, "anvil", "for the anvil")
		var button := {"fast": "%FastButton", "normal": "%NormalButton", "live": "%CarefulButton"}[mode] as String
		(menu.get_node(button) as Button).pressed.emit()
		var by_id := {}
		for b: Button in menu.recipe_buttons():
			by_id[str(b.name)] = b
		eq(by_id.keys().size(), 3, "the anvil's three recipes")
		check(not (by_id["forge_sword"] as Button).disabled, "sword: enabled")
		check((by_id["forge_armor"] as Button).disabled, "armor: disabled (needs 3 ingots)")
		check((by_id["forge_armor"] as Button).tooltip_text.contains(SimQuery.t_("ui.recipe.missing_inputs")),
			"with the reason in the tooltip")
		(by_id["forge_sword"] as Button).pressed.emit()
		eq(got.size(), 1, "one order (%s)" % mode)
		_same(got[0], {"type": "work_at", "actor": HUGO, "building": BLD, "zone": "anvil", "recipe": "forge_sword",
			"mode": mode}, "work_at %s" % mode)
		check(not menu.visible, "the menu closes")
		var ev := sim.step(got)
		eq(_refusals(ev).size(), 0, "the sim takes it (%s)" % mode)
		var job: Variant = sim.state.buildings[BLD]["zones"]["anvil"]["job"]
		check(job is Dictionary and str(job["mode"]) == mode, "a %s job at the anvil" % mode)
		v.sync()
		check(v.station_view("anvil").occupied and v.station_view("anvil").progress >= 0.0,
			"the anvil shows it busy with its bar")
		v.free()


func test_station_menu_lock_and_stop() -> void:
	var sim := _sim()
	_hugo_inside(sim)
	sim.state.characters[HUGO]["stats"]["craft"] = 3
	var v := _interior(sim)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.open_station_menu("anvil", Vector2(100, 100))
	v.station_menu().choose_mode("normal")
	var sword: Button = null
	for b: Button in v.station_menu().recipe_buttons():
		if str(b.name) == "forge_sword":
			sword = b
	check(sword != null and sword.disabled and sword.icon != null, "sword under the skill: locked, with the lock")
	check(sword.tooltip_text.contains(SimQuery.t_("ui.recipe.locked") % 4), "tooltip says the skill needed")
	# working at the furnace: the menu offers Stop
	sim.step([{"type": "work_at", "actor": HUGO, "building": BLD, "zone": "furnace", "recipe": "forge_ingot",
		"mode": "normal"}])
	v.open_station_menu("furnace", Vector2(100, 100))
	check((v.station_menu().get_node("%StopButton") as Button).visible, "Stop shown while working")
	(v.station_menu().get_node("%StopButton") as Button).pressed.emit()
	_same(got[0], {"type": "stop_work", "actor": HUGO}, "stop_work")
	var ev := sim.step(got)
	check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "work_interrupted"), "the work stops")
	eq(Inventory.count(sim.state.buildings[BLD]["inventory"], "iron"), 10, "the iron comes back (D11)")
	v.free()


func test_left_click_on_station_goes_there() -> void:
	var sim := _sim()
	_hugo_inside(sim)
	var v := _interior(sim)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	check(_click(v, MOUSE_BUTTON_LEFT, v.station_screen("furnace")), "left click on the furnace")
	_same(got[0], {"type": "go_to_station", "actor": HUGO, "zone": "furnace"}, "go_to_station")
	sim.step(got)
	eq(str(sim.state.characters[HUGO]["station"]), "furnace", "Hugo at the furnace")
	v.sync()
	(v.get_node("InteriorStage") as InteriorStage).tick(10.0)  # he walks there (04g 4.6.5.4): long enough to arrive
	var d := InteriorDefs.def_of("forge")
	var stand: Array = d["stations"]["furnace"]["stand"]
	var spot := InteriorDefs.spot_world(d, 0, Vector2(float(stand[0]), float(stand[1]))).round()
	eq(v.view_of(HUGO).position, spot, "drawn at his station's spot")
	v.free()


## 03b §3b.8: the master touch left the UI (the Forja viva replaces it). A careful cycle (an old save, a trade's bot)
## still has its window in the sim, but the station does not blink and a click in it is a plain click.
func test_the_master_touch_left_the_ui() -> void:
	var sim := _sim()
	_hugo_inside(sim)
	_add(sim.state.buildings[BLD]["inventory"], "iron_ingot", 0, 2)
	sim.step([{"type": "work_at", "actor": HUGO, "building": BLD, "zone": "anvil", "recipe": "forge_sword",
		"mode": "careful"}])
	var v := _interior(sim)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	_run_until(sim, func() -> bool: return bool(Production.job_view(sim, BLD, "anvil").get("window_open", false)))
	v.sync()
	check(not v.station_view("anvil").window_open, "the window is open in the sim, the anvil does not blink")
	check(_click(v, MOUSE_BUTTON_LEFT, v.station_screen("anvil")), "click on it")
	_same(got[0], {"type": "go_to_station", "actor": HUGO, "zone": "anvil"}, "a plain click: no master_touch")
	var r := Orders.apply(sim, {"type": "master_touch", "actor": HUGO, "building": BLD, "zone": "anvil"})
	check(r["ok"], "the sim still takes the order (old saves, the trades' bots): %s" % r["reason"])
	v.free()


func test_storage_panel_transfer() -> void:
	var sim := _sim()
	_hugo_inside(sim)
	var v := _interior(sim)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	(v.get_node("%StorageButton") as Button).toggled.emit(true)
	var panel := v.storage_panel()
	check(panel.visible, "the storage panel opens from the toolbar")
	var row := panel.row_of("iron", 0, true) as ItemSlot
	check(row != null, "a square for the iron")
	var fits := Inventory.fit_count(sim.state.characters[HUGO]["inventory"], cat, "iron", 0, row.qty)
	row.clicked.emit(row, false)   # a click: all that fits (docs/ui/mecanicas/almacen_y_personaje.md §4.1)
	_same(got[0], {"type": "transfer", "actor": HUGO, "from": BLD, "to": HUGO, "item": "iron", "quality": 0, "qty": fits},
		"take the iron that fits")
	eq(_refusals(sim.step(got)).size(), 0, "the sim takes it")
	eq(Inventory.count(sim.state.characters[HUGO]["inventory"], "iron"), fits, "Hugo carries it")
	panel.refresh(true)
	var back := panel.row_of("iron", 0, false) as ItemSlot
	check(back != null, "Hugo's square")
	back.clicked.emit(back, true)   # a right click: 1
	_same(got[1], {"type": "transfer", "actor": HUGO, "from": HUGO, "to": BLD, "item": "iron", "quality": 0, "qty": 1},
		"leave 1 iron")
	check(panel.get_node_or_null("%BuyButton") == null, "no raw purchase in the storage since the market (H3)")
	v.free()


func test_storage_shows_quality_as_suffix() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	eq(SimQuery.item_label(cat, "sword", 1), "Espada buena", "GDD 4.3.3")
	eq(SimQuery.item_label(cat, "iron", 0), "Hierro", "normal quality has no suffix")
	var sim := _sim()
	_hugo_inside(sim)
	_add(sim.state.buildings[BLD]["inventory"], "sword", 1, 1)
	var v := _interior(sim)
	v.show_storage(true)
	var row := v.storage_panel().row_of("sword", 1, true) as ItemSlot
	check(row != null and row.tooltip_text.begins_with("Espada buena"), "the square's tooltip reads Espada buena")
	check(row.quality == 1 and row.state == "item", "with its quality (the silver dot)")
	TranslationServer.set_locale(before)
	v.free()


func test_exit_by_door_and_manage_mode_closes() -> void:
	var sim := _sim()
	_hugo_inside(sim)
	var v := _interior(sim)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	check(_click(v, MOUSE_BUTTON_LEFT, v.door_screen()), "click on the door")
	_same(got[0], {"type": "exit_building", "actor": HUGO}, "exit_building")
	var ev := sim.step(got)
	check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "building_left"), "building_left (the view closes)")
	v.free()
	# management mode: no person, leaving just closes
	var sim2 := _sim()
	var m := _interior(sim2, true)
	var closed: Array = []
	m.close_requested.connect(func() -> void: closed.append(true))
	var got2: Array = []
	m.order_sink = func(o: Dictionary) -> void: got2.append(o)
	eq(m.actor(), "", "nobody acts in management mode while Hugo is outside")
	_click(m, MOUSE_BUTTON_RIGHT, m.station_screen("anvil"))
	check(m.station_menu().visible and not (m.station_menu().get_node("%Hint") as Label).text.is_empty(),
		"the menu says to select someone inside")
	m.request_exit()
	eq(closed.size(), 1, "closes")
	eq(got2.size(), 0, "without orders")
	m.free()


func test_character_panel_weight_and_equipment() -> void:
	var sim := _sim()
	_add(sim.state.characters[HUGO]["inventory"], "hammer", 0, 1)
	var p: CharacterPanel = (load("res://game/ui/character_panel.tscn") as PackedScene).instantiate()
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.setup(sim, HUGO)
	check((p.get_node("%WeightLabel") as Label).text.contains("6.0"), "carried weight 6 kg")
	check((p.get_node("%WeightLabel") as Label).text.contains("30"), "of 30 kg")
	check((p.get_node("%GoldLabel") as Label).text.contains("100"), "the family's gold")
	var row := p.get_node("%InvList").get_node("hammer_0")
	(row.get_node("Equip") as Button).pressed.emit()
	_same(got[0], {"type": "equip", "actor": HUGO, "item": "hammer", "quality": 0}, "equip")
	eq(_refusals(sim.step(got)).size(), 0, "the sim takes it")
	p.refresh(true)
	var unequip := p.get_node("%Slots").get_node("tool").get_node("Unequip") as Button
	check(not unequip.disabled, "the tool slot holds the hammer")
	check((p.get_node("%WeightLabel") as Label).text.contains("6.0"), "the weight still counts it (GDD 4.3.4)")
	unequip.pressed.emit()
	_same(got[1], {"type": "unequip", "actor": HUGO, "slot": "tool"}, "unequip")
	p.free()


func test_order_queue_lines_in_pause() -> void:
	var sim := _sim()
	var orders := [
		{"type": "enter_building", "actor": HUGO, "building": BLD, "queued": true},
		{"type": "go_to_station", "actor": HUGO, "zone": "furnace", "queued": true},
		{"type": "work_at", "actor": HUGO, "building": BLD, "zone": "furnace", "recipe": "forge_ingot", "mode": "careful",
			"queued": true},
	]
	eq(SimQuery.queue_lines(sim, HUGO, orders, true).size(), 3, "given in pause: three lines")
	eq(SimQuery.queue_lines(sim, HUGO, orders, false).size(), 0, "pending orders count only while paused")
	sim.step(orders)
	var lines := SimQuery.queue_lines(sim, HUGO, [], true)
	eq(lines.size(), 3, "in the sim's queue after the step (or started: %s)" % [lines])
	eq(lines[0], SimQuery.order_label(sim.state, cat, orders[0]), "in order")
	check(lines[2].contains(SimQuery.recipe_name(cat, "forge_ingot")), "the work line names the recipe")
