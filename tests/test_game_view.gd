extends "res://tests/test_case.gd"
## The town view (H1): a real mouse click becomes a move_to order (D3), screen <-> tile with the camera moved and
## zoomed, interpolation between tiles and the day/night tint (GDD 4.15). Windowless: the view is built by hand.

var cat := Catalog.load_from()


func _view() -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	var r := NewGame.from_scenario("town_e_start")
	v.setup(r["state"], cat)
	return v


func _click(v: WorldView, button: MouseButton, screen: Vector2) -> bool:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = screen
	return v.handle_input(ev)


## Screen point on a person's body (a bit above the feet).
func _body(v: WorldView, id: String) -> Vector2:
	return v.camera().world_to_screen(v.view_of(id).position + Vector2(0, -20))


func test_real_click_gives_move_to() -> void:
	var v := _view()
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	check(_click(v, MOUSE_BUTTON_LEFT, _body(v, "chr_0001")), "left click used")
	eq(v.selected_id, "chr_0001", "left click on Hugo selects him")
	check(v.view_of("chr_0001").selected, "selection indicator on")
	var target := Vector2i(20, 18)  # the plaza on the main street (clear of the forge's drawing)
	check(_click(v, MOUSE_BUTTON_RIGHT, v.tile_to_screen(target) + Vector2(6, 2)), "right click used")
	eq(got.size(), 1, "one order")
	eq(SaveFile.canonical(got[0]), SaveFile.canonical({"type": "move_to", "actor": "chr_0001", "tile": [20, 18]}),
		"the order")
	# the same order through the sim: accepted, the walk starts
	var sim := Sim.new(v.state, cat)
	var ev := sim.step(got)
	check(not ev.any(func(e: Dictionary) -> bool: return e["type"] == "order_refused"), "the sim takes it")
	check(not (v.state.characters["chr_0001"]["path"] as Array).is_empty(), "Hugo has a path")
	v.free()


func test_only_the_human_family_is_selectable() -> void:
	var v := _view()
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.camera().center_on(v.view_of("chr_0004").position)
	_click(v, MOUSE_BUTTON_LEFT, _body(v, "chr_0004"))
	eq(v.selected_id, "", "Marta (AI family) is not selectable")
	check(not _click(v, MOUSE_BUTTON_RIGHT, v.tile_to_screen(Vector2i(8, 13))), "right click with nobody selected")
	eq(got.size(), 0, "no order")
	v.camera().center_on(v.view_of("chr_0002").position)
	_click(v, MOUSE_BUTTON_LEFT, _body(v, "chr_0002"))
	eq(v.selected_id, "chr_0002", "Elena selected")
	_click(v, MOUSE_BUTTON_LEFT, v.tile_to_screen(Vector2i(3, 3)))
	eq(v.selected_id, "", "left click on empty ground deselects")
	v.free()


func test_screen_tile_round_trip_with_camera() -> void:
	var v := _view()
	var cam := v.camera()
	for z: int in cam.zoom_levels.size():
		cam.zoom_index = z
		for c: Vector2 in [Vector2(0, 600), Vector2(-300, 400), Vector2(500, 900)]:
			cam.center_on(c)
			for t: Vector2i in [Vector2i(20, 21), Vector2i(5, 30), Vector2i(33, 8), Vector2i(18, 18)]:
				var s := v.tile_to_screen(t)
				eq(v.screen_to_tile(s), t, "zoom x%d centre %s tile %s" % [cam.current_zoom(), c, t])
				eq(v.screen_to_tile(s + Vector2(12, 4) * cam.current_zoom()), t, "inside the diamond")
				eq(v.screen_to_tile(s + Vector2(0, 20) * cam.current_zoom()), t + Vector2i(1, 1), "one tile below")
	v.free()


func test_camera_zoom_pan_and_bounds() -> void:
	var v := _view()
	var cam := v.camera()
	cam.zoom_index = 0
	cam.center_on(Vector2(100, 500))
	var anchor := Vector2(700, 120)
	var before := cam.screen_to_world(anchor)
	cam.zoom_step(1, anchor)
	eq(cam.current_zoom(), 2, "zoom in")
	check(cam.screen_to_world(anchor).distance_to(before) <= 1.0, "the point under the mouse stays")
	cam.zoom_step(1, anchor)
	eq(cam.current_zoom(), 2, "no zoom past the last level")
	for z: int in cam.zoom_levels:
		eq(float(z), roundf(float(z)), "whole zoom levels only (D2)")
	cam.pan(Vector2(33.3, -7.7))
	eq(cam.position, cam.position.round(), "drawn at whole pixels")
	cam.center_on(Vector2(99999, -99999))
	check(cam.bounds.grow(0.5).has_point(cam.position), "clamped to the map (%s in %s)" % [cam.position, cam.bounds])
	eq(cam.position, Vector2(cam.bounds.end.x, cam.bounds.position.y).round(), "at the top-right corner")
	v.free()


func test_walker_interpolates_between_tiles() -> void:
	var ch := {"position": [10, 10], "path": [[11, 10], [12, 10]], "move_progress": 1}
	eq(CharacterView.tile_position(ch, 2, 0.0), Vector2(10.5, 10), "half-way at progress 1 of 2")
	eq(CharacterView.tile_position(ch, 2, 0.5), Vector2(10.75, 10), "the step fraction adds in")
	eq(CharacterView.tile_position({"position": [3, 4], "path": [], "move_progress": 0}, 2, 0.9), Vector2(3, 4),
		"still without a path")


func test_day_night_tint() -> void:
	var t := cat.time
	var cfg: Dictionary = ViewConfig.value("day_night")
	var noon := 12 * 60
	eq(DayNight.tint(noon, 0.0, t, cfg), Color.WHITE, "noon is untinted")
	var night := DayNight.tint(23 * 60, 0.0, t, cfg)
	check(night.v < 0.6 and night.b > night.r, "23:00 is dark and blue (%s)" % night)
	var dawn_start := int(t["phase_starts"]["spring"]["dawn"])
	near(DayNight.tint(dawn_start, 0.0, t, cfg).v, night.v, 0.001, "dawn starts from the night colour")
	check(DayNight.tint(dawn_start + 30, 0.0, t, cfg).v > night.v, "and brightens gradually")
	near(DayNight.phase_progress(noon, 0.0, t), float(noon - 420) / (1140 - 420), 0.0001, "day phase progress")
	near(DayNight.phase_progress(2 * 60, 0.0, t), float(2 * 60 + 1440 - 1260) / (1440 - 1260 + 300), 0.0001,
		"night wraps midnight")


func test_empty_town_view_has_no_map() -> void:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario("empty_town")["state"], cat)
	eq(v.objects().get_child_count(), 0, "nothing to draw")
	eq(v.first_selectable(), "", "nobody to select")
	v.free()


## --- Walking with the keys (WASD, WorldView.key_walk): a move_to with its own route ---

func _keys_view(at: Vector2i) -> Array:
	var v := _view()
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.state.characters["chr_0001"]["position"] = [at.x, at.y]
	v.state.characters["chr_0001"]["path"] = []
	v.select("chr_0001")
	return [v, got]


## Gives the view's pending orders to a sim and runs `steps` minutes.
func _run(v: WorldView, got: Array, steps: int = 1) -> Array:
	var sim := Sim.new(v.state, cat)
	var events: Array = sim.step(got.duplicate(true))
	got.clear()
	for i: int in steps - 1:
		events.append_array(sim.step([]))
	return events


func test_keys_walk_the_selected_person() -> void:
	var a := _keys_view(Vector2i(22, 19))  # the plaza: open ground all around
	var v: WorldView = a[0]
	var got: Array = a[1]
	check(v.key_walk(Vector2i(0, -1)), "the keys have somebody to walk")
	eq(got.size(), 1, "one order")
	eq(str(got[0]["type"]), "move_to", "a move_to")
	eq(got[0]["route"], [[21, 18], [20, 17], [19, 16]], "W = up the screen = a diagonal of the grid, three tiles ahead")
	eq(got[0]["tile"], [19, 16], "its tile is the end of the route")
	v.key_walk(Vector2i(0, -1))
	eq(got.size(), 1, "the same route is not given twice")
	var ev := _run(v, got)
	check(not ev.any(func(e: Dictionary) -> bool: return e["type"] == "order_refused"), "the sim takes the route")
	eq(v.state.characters["chr_0001"]["path"], [[21, 18], [20, 17], [19, 16]], "and walks exactly it")
	v.key_walk(Vector2i(0, -1))
	eq(got.size(), 0, "walking it already: no new order")
	v.free()


func test_keys_two_keys_walk_along_the_grid() -> void:
	var a := _keys_view(Vector2i(22, 19))
	var v: WorldView = a[0]
	var got: Array = a[1]
	v.key_walk(Vector2i(1, -1))  # W+D: up-right on screen = a row less
	eq(got[0]["route"], [[22, 18], [22, 17], [22, 16]], "W+D walks north-east along the grid")
	got.clear()
	v.key_walk(Vector2i.ZERO)
	v.key_walk(Vector2i(1, 1))   # S+D
	eq(got[got.size() - 1]["route"][0], [23, 19], "S+D walks south-east along the grid")
	v.free()


func test_keys_slide_along_a_wall() -> void:
	var a := _keys_view(Vector2i(7, 14))  # the west street (col 7), grass on both sides... a house block at cols 1-5
	var v: WorldView = a[0]
	var got: Array = a[1]
	v.state.characters["chr_0001"]["position"] = [6, 16]  # grass beside the houses of cols 1-5, rows 15-17
	v.key_walk(Vector2i(-1, 0))  # A = left on screen = (-1, +1) of the grid: the house is in the way of the diagonal
	eq(got.size(), 1, "an order")
	eq(got[0]["route"][0], [6, 17], "slides down the wall instead of stopping")
	v.free()


func test_keys_stop_when_let_go() -> void:
	var a := _keys_view(Vector2i(22, 19))
	var v: WorldView = a[0]
	var got: Array = a[1]
	v.key_walk(Vector2i(1, -1))
	v.key_walk(Vector2i.ZERO)  # a tap: let go before the sim took the order
	eq(got.size(), 2, "the route and its cut")
	eq(got[1]["route"], [[22, 18]], "a tap walks one tile")
	_run(v, got)
	eq(v.state.characters["chr_0001"]["path"], [[22, 18]], "one tile left to walk")
	check(not v.key_walking, "the keys no longer drive")
	_run(v, got, 3)
	eq(v.state.characters["chr_0001"]["position"], [22, 18], "there")
	v.key_walk(Vector2i.ZERO)
	eq(got.size(), 0, "nothing more to cut")
	v.free()


func test_keys_turn_on_the_tile_being_entered() -> void:
	var a := _keys_view(Vector2i(22, 19))
	var v: WorldView = a[0]
	var got: Array = a[1]
	v.key_walk(Vector2i(1, -1))
	_run(v, got)  # on its way to (22, 18), a minute in
	var progress := int(v.state.characters["chr_0001"]["move_progress"])
	v.key_walk(Vector2i(1, 1))  # S+D now: a column more
	eq(got.size(), 1, "the turn is an order")
	eq(got[0]["route"], [[22, 18], [23, 18], [24, 18], [25, 18]], "it finishes the step and turns there")
	_run(v, got)
	eq(progress, 1, "half the step done when the keys turned")
	eq(v.state.characters["chr_0001"]["position"], [22, 18], "the step under way went on (no restart)")
	eq(v.state.characters["chr_0001"]["path"], [[23, 18], [24, 18], [25, 18]], "and the turn follows")
	v.free()


func test_keys_extend_the_route_when_one_tile_is_left() -> void:
	var a := _keys_view(Vector2i(10, 18))  # the main street, east
	var v: WorldView = a[0]
	var got: Array = a[1]
	v.key_walk(Vector2i(1, 1))
	eq(got[0]["route"], [[11, 18], [12, 18], [13, 18]], "three tiles ahead")
	_run(v, got, 2)
	eq(v.state.characters["chr_0001"]["position"], [11, 18], "a tile walked")
	v.key_walk(Vector2i(1, 1))
	eq(got.size(), 0, "two tiles left: nothing to give")
	_run(v, got, 2)
	v.key_walk(Vector2i(1, 1))
	eq(got.size(), 1, "one left: the route goes on")
	eq(got[0]["route"], [[13, 18], [14, 18], [15, 18], [16, 18]], "from the tile being entered")
	var ev := _run(v, got)
	check(not ev.any(func(e: Dictionary) -> bool: return e["type"] == "order_refused"), "taken")
	v.free()


func test_keys_with_nobody_to_walk_pan() -> void:
	var a := _keys_view(Vector2i(22, 19))
	var v: WorldView = a[0]
	var got: Array = a[1]
	v.select("")
	check(not v.key_walk(Vector2i(1, 0)), "nobody selected: the keys are the camera's")
	v.select("chr_0001")
	v.state.characters["chr_0001"]["location"] = "bld_0001"
	check(not v.key_walk(Vector2i(1, 0)), "inside a building: the camera's too")
	eq(got.size(), 0, "no order")
	v.free()


func test_move_to_route_is_checked_by_the_sim() -> void:
	var a := _keys_view(Vector2i(22, 19))
	var v: WorldView = a[0]
	var sim := Sim.new(v.state, cat)
	var grid := Grid.for_state(cat, v.state)
	check(Movement.can_step(grid, Vector2i(19, 15), Vector2i(1, 0)), "a step on the plaza")
	check(not Movement.can_step(grid, Vector2i(6, 16), Vector2i(-1, 0)), "not into a house")
	check(not Movement.can_step(grid, Vector2i(6, 16), Vector2i(-1, 1)), "no corner cutting")
	check(not Movement.can_step(grid, Vector2i(19, 15), Vector2i(2, 0)), "a step is one tile")
	for bad: Array in [[[21, 15]], [[20, 15], [22, 15]], [[20, 15]], [[5, 16]], []]:
		var tile: Array = [21, 15] if bad != [[5, 16]] else [5, 16]
		var ev := sim.step([{"type": "move_to", "actor": "chr_0001", "tile": tile, "route": bad}])
		check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "order_refused" and e["reason"] == "blocked"),
			"route %s refused" % str(bad))
	v.free()
