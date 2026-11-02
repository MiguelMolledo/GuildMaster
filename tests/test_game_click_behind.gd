extends "res://tests/test_case.gd"
## Pulido del MVP, arreglo 4 (scale B): with the taller buildings, a right click on a street tile hidden behind a
## building's drawn volume sends the selected person into that building: those tiles could not be reached. Now, with
## Shift held or when that building is see-through (the selected person behind it), the ground tile under the pointer
## decides (WorldView.command_target_building): every walkable tile that is not a door nor a building's own tile is a
## walk. A plain right click on a building still enters it.

const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _click(v: WorldView, button: MouseButton, screen: Vector2, shift: bool = false) -> bool:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.shift_pressed = shift
	ev.position = screen
	return v.handle_input(ev)


func test_every_hidden_street_tile_can_be_reached() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_e_start")["state"], cat)
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.select(HUGO)
	var grid := Grid.of(cat, sim.state.map_id)
	var doors := {}
	for id: String in sim.state.buildings:
		var d: Array = sim.state.buildings[id].get("door", [])
		if d.size() == 2:
			doors[Vector2i(int(d[0]), int(d[1]))] = true
	var hidden := 0
	var reached := 0
	for r: int in grid.height:
		for c: int in grid.width:
			var t := Vector2i(c, r)
			if not grid.walkable(c, r) or doors.has(t):
				continue
			v.camera().center_on(Iso.tile_to_world(t))
			var screen := v.tile_to_screen(t)
			if v.screen_to_tile(screen) != t or v.pick_building(screen) == "":
				continue  # not covered by a building's drawing
			hidden += 1
			got.clear()
			_click(v, MOUSE_BUTTON_RIGHT, screen, true)
			if got.size() == 1 and str(got[0]["type"]) == "move_to" and Vector2i(int(got[0]["tile"][0]),
					int(got[0]["tile"][1])) == t:
				reached += 1

	check(hidden > 0, "scale B: some street tiles are drawn behind buildings (%d)" % hidden)
	eq(reached, hidden, "every one of them is a walk with Shift + right click")
	v.free()


func test_a_building_is_still_entered_by_its_tiles_and_door() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_e_start")["state"], cat)
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.select(HUGO)
	var b: Dictionary = sim.state.buildings["bld_0001"]
	var o: Array = b["origin"]
	v.camera().center_on(Iso.tile_to_world(Vector2i(int(o[0]), int(o[1]))))
	_click(v, MOUSE_BUTTON_RIGHT, v.tile_to_screen(Vector2i(int(o[0]), int(o[1]))))
	eq(got[0], {"type": "enter_building", "actor": HUGO, "building": "bld_0001"}, "its own tile: enter")
	var d: Array = b["door"]
	_click(v, MOUSE_BUTTON_RIGHT, v.tile_to_screen(Vector2i(int(d[0]), int(d[1]))))
	eq(got[1], {"type": "enter_building", "actor": HUGO, "building": "bld_0001"}, "its door: enter")
	_click(v, MOUSE_BUTTON_RIGHT, v.tile_to_screen(Vector2i(int(d[0]), int(d[1]))), true)
	eq(got[2], {"type": "enter_building", "actor": HUGO, "building": "bld_0001"}, "with Shift too")
	v.free()


func test_a_see_through_building_lets_the_click_through() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_e_start")["state"], cat)
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.select(HUGO)
	var t := Vector2i(24, 22)  # a street tile drawn behind the forge (test_game_forja)
	v.camera().center_on(Iso.tile_to_world(t))
	var screen := v.tile_to_screen(t)
	eq(v.pick_building(screen), "bld_0001", "the forge's volume covers it")
	_click(v, MOUSE_BUTTON_RIGHT, screen)
	eq(str(got[0]["type"]), "enter_building", "opaque forge: a plain click enters it (as before)")
	(v.get("_building_visuals")["bld_0001"] as Node2D).modulate.a = 0.45  # Hugo behind it: see-through
	_click(v, MOUSE_BUTTON_RIGHT, screen)
	eq(got[1], {"type": "move_to", "actor": HUGO, "tile": [24, 22]}, "see-through: the click goes to the tile")
	v.free()
