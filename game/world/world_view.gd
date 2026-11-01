class_name WorldView
extends Node2D
## The town seen from outside (H1): greybox ground, blocked tiles with volume, walkers, the camera and the
## day/night tint. Reads Game.state and the catalog; the only thing it sends back are orders (D3: a right click
## on a tile with someone selected -> {"type": "move_to", "actor", "tile"}). It never writes the state.
##
## Controls: left click on one of the human family's people selects it (left click elsewhere deselects);
## right click on a tile sends the selected person there. Camera: see WorldCamera.

signal selection_changed(char_id: String)

var order_sink: Callable = Callable()  # who receives the orders: Game.give in the game, a test's own in the tests
var state: WorldState
var catalog: Catalog
var selected_id: String = ""
var tint_color: Color = Color.WHITE
var _views: Dictionary = {}  # chr_id -> CharacterView
var _minutes_per_tile: int = 1
var _game: Node = null      # the Game autoload, when in the tree


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	if _game == null:
		return
	order_sink = _game.give
	_game.started.connect(func() -> void: setup(_game.sim.state, _game.sim.catalog))
	if _game.sim != null:
		setup(_game.sim.state, _game.sim.catalog)


func ground() -> GroundLayer:
	return get_node("%Ground")


func objects() -> Node2D:
	return get_node("%Objects")


func camera() -> WorldCamera:
	return get_node("%Camera")


func marker() -> TargetMarker:
	return get_node("%Marker")


## Builds the view of `s`. Called again whenever a new state is loaded.
func setup(s: WorldState, c: Catalog) -> void:
	state = s
	catalog = c
	selected_id = ""
	_views.clear()
	for n: Node in objects().get_children():
		objects().remove_child(n)
		n.queue_free()
	_minutes_per_tile = ViewConfig.minutes_per_tile(c)
	var rows: Array = c.maps().get(s.map_id, {}).get("rows", [])
	ground().build(rows, c)
	var blocks: Dictionary = ViewConfig.value("blocks", {})
	var n_blocks := 0
	for r: int in rows.size():
		var row := str(rows[r])
		for col: int in row.length():
			var kind := c.tile_kind_of_char(row[col])
			if not blocks.has(kind):
				continue
			var b := BlockView.new()
			b.shape = str(blocks[kind].get("shape", "block"))
			b.height = float(blocks[kind].get("height", 32))
			b.color = ViewConfig.color(str(c.tiles[kind].get("color", "#808080")))
			b.position = Iso.tile_to_world(Vector2i(col, r))
			objects().add_child(b)
			n_blocks += 1
	var ids: Array = s.characters.keys()
	ids.sort()
	for id: String in ids:
		_add_view(str(id))
	var cam := camera()
	if rows.is_empty():
		cam.set_bounds(Rect2())
		cam.center_on(Vector2.ZERO)
	else:
		var w := str(rows[0]).length()
		var h := rows.size()
		var left := Iso.tile_to_world(Vector2i(0, h - 1)).x
		var right := Iso.tile_to_world(Vector2i(w - 1, 0)).x
		var bottom := Iso.tile_to_world(Vector2i(w - 1, h - 1)).y
		cam.set_bounds(Rect2(left, 0.0, right - left, bottom))
		cam.center_on(_start_focus(Iso.tile_to_world(Vector2i(w / 2, h / 2))))
	sync(0.0)
	ViewConfig.info("WorldView", "setup (map=%s, rows=%d, blocks=%d, characters=%d, minutes_per_tile=%d)" % [
		s.map_id, rows.size(), n_blocks, _views.size(), _minutes_per_tile])


func _add_view(id: String) -> void:
	var ch: Dictionary = state.characters[id]
	if not bool(ch.get("alive", true)) or not ch.has("position"):
		return
	var v := CharacterView.new()
	v.setup(ch, state.families.get(str(ch.get("family", "")), {}))
	objects().add_child(v)
	_views[id] = v


## The first person of the human family, else `fallback`.
func _start_focus(fallback: Vector2) -> Vector2:
	var id := first_selectable()
	if id == "":
		return fallback
	var pos: Array = state.characters[id]["position"]
	return Iso.tile_to_world(Vector2i(int(pos[0]), int(pos[1])))


func first_selectable() -> String:
	var ids: Array = _views.keys()
	ids.sort()
	for id: String in ids:
		if (_views[id] as CharacterView).selectable:
			return id
	return ""


func view_of(id: String) -> CharacterView:
	return _views.get(id, null)


func _process(_delta: float) -> void:
	if state == null:
		return
	sync(_game.step_fraction() if _game != null else 0.0)


## Follows the state: new or dead walkers, positions, the day/night tint. `frac` = how far towards the next step.
func sync(frac: float) -> void:
	for id: String in state.characters:
		if not _views.has(id):
			_add_view(id)
	for id: String in _views.keys():
		var ch: Dictionary = state.characters.get(id, {})
		if ch.is_empty() or not bool(ch.get("alive", true)):
			(_views[id] as CharacterView).queue_free()
			_views.erase(id)
			if id == selected_id:
				select("")
			continue
		(_views[id] as CharacterView).follow(ch, _minutes_per_tile, frac)
	tint_color = DayNight.tint(int(state.clock["minute"]), frac, catalog.time, ViewConfig.value("day_night", {}))
	(get_node("%Tint") as CanvasModulate).color = tint_color


func select(id: String) -> void:
	if id == selected_id:
		return
	if selected_id != "" and _views.has(selected_id):
		(_views[selected_id] as CharacterView).selected = false
	selected_id = id if _views.has(id) else ""
	if selected_id != "":
		(_views[selected_id] as CharacterView).selected = true
	ViewConfig.info("WorldView", "selected %s" % (selected_id if selected_id != "" else "nobody"))
	selection_changed.emit(selected_id)


## Screen (viewport) pixel -> tile under it, with the camera as drawn.
func screen_to_tile(screen: Vector2) -> Vector2i:
	return Iso.world_to_tile(camera().screen_to_world(screen))


func tile_to_screen(tile: Vector2i) -> Vector2:
	return camera().world_to_screen(Iso.tile_to_world(tile))


## The human family's person under `screen`: the figure first (the front-most one), else whoever stands on the tile.
func pick_character(screen: Vector2) -> String:
	var world := camera().screen_to_world(screen)
	var best := ""
	var best_y := -INF
	for id: String in _views:
		var v: CharacterView = _views[id]
		if v.selectable and v.pick_rect().has_point(world) and v.position.y > best_y:
			best = id
			best_y = v.position.y
	if best != "":
		return best
	var tile := Iso.world_to_tile(world)
	for id: String in _views:
		var pos: Array = state.characters[id].get("position", [])
		if (_views[id] as CharacterView).selectable and Vector2i(int(pos[0]), int(pos[1])) == tile:
			return id
	return ""


## Sends the selected person to `tile` (the sim decides whether it can).
func command_move(tile: Vector2i) -> void:
	if selected_id == "":
		return
	var order := {"type": "move_to", "actor": selected_id, "tile": [tile.x, tile.y]}
	ViewConfig.info("WorldView", "order move_to (actor=%s, tile=%s)" % [selected_id, tile])
	if order_sink.is_valid():
		order_sink.call(order)
	marker().show_at(tile, float(ViewConfig.value("target_marker_seconds", 1.0)))


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


## Clicks of the world: left selects (or deselects), right moves the selected person. True if used.
func handle_input(event: InputEvent) -> bool:
	if state == null or not event is InputEventMouseButton or not event.is_pressed():
		return false
	var mb := event as InputEventMouseButton
	if event.is_action_pressed("select"):
		select(pick_character(mb.position))
		return true
	if event.is_action_pressed("command") and selected_id != "":
		command_move(screen_to_tile(mb.position))
		return true
	return false
