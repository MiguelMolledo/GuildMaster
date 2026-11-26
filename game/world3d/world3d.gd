class_name WorldView3D
extends Node3D
## The town in 3D (docs/3d/plan.md, M3D-1): what app.gd shows instead of WorldView when data/view.json view_mode is
## "3d" (or with --view=3d). It holds the Town3D of the game loaded now (built again on every Game.started: a new
## game, a load) and offers the app the same signals and calls as WorldView: select, first_selectable,
## pick_building_id, selected_id, rebuild_town, set_active, the camera on a tile. It only reads the state; the orders
## (from M3D-2) go out through order_sink (Game.give).
## Camera (as in Prueba3D): W/A/S/D or the arrows pan, Shift faster, Q/E turn, RePág/AvPág tilt, the wheel or a
## trackpad pinch zoom (orthographic size 3-90), all continuous and eased.
## Clicks (the first of M3D-2, as in WorldView): left on a person of the player's family selects them (a ring under
## the feet), on somebody else opens their sheet, on a building picks it (double click: manage it), elsewhere
## deselects; right with someone selected: on a stall, the board or the town hall goes to its service tile and opens
## its panel on arrival, on a building goes in (enter_building), elsewhere walks there (move_to). The building under
## the pointer is looked for at roof, wall and ground height along the camera ray.

signal selection_changed(char_id: String)
signal building_picked(building_id: String)   # "" = none
signal manage_requested(building_id: String)
signal service_requested(actor: String, kind: String, id: String, service: Vector2i)
signal npc_picked(char_id: String)
signal plot_picked(plot_id: String)
signal town_built(ms: int)                     # a town was built (how long it took)

var order_sink: Callable = Callable()
var town: Town3D = null
var sim: Sim = null  # the sim of the town shown (the Game's; a test's own)
var selected_id: String = ""
var picked_building: String = ""
var tint_color: Color = Color.WHITE  # WorldView's: the app tints its 2D background with it (none in 3D)
var build_ms: int = 0
var keys_on: bool = true  # the camera keys act (the app turns them off while a menu screen is open)
var _game: Node = null
var _active: bool = true
var _baseline: Dictionary = {}  # orphan node ids (debug builds) before the town was built: what is not its own


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	if _game == null:
		return
	order_sink = _game.give
	_game.started.connect(func() -> void: build(_game.sim))
	_first_build.call_deferred()


## The game already loaded when the view comes in, unless a Game.started of the same frame built it (the title).
func _first_build() -> void:
	if town == null and _game.sim != null:
		build(_game.sim)


## Builds the town of `s` (the one of the game loaded now), dropping the one before.
func build(s: Sim) -> void:
	if s == null:
		return
	sim = s
	var t0 := Time.get_ticks_msec()
	_drop_town()
	_baseline.clear()
	for id: int in Node.get_orphan_node_ids():
		_baseline[id] = true
	selected_id = ""
	picked_building = ""
	if (s.catalog.maps().get(s.state.map_id, {}).get("rows", []) as Array).is_empty():
		ViewConfig.info("WorldView3D", "no town: map %s has no rows" % s.state.map_id)  # a state without a map (empty_town)
		return
	town = Town3D.new()
	town.name = "Town3D"
	town.setup(s)
	add_child(town)
	town.set_process(_active)
	town.set_process_unhandled_input(_active)
	_feed_time()
	build_ms = Time.get_ticks_msec() - t0
	_focus_start()
	ViewConfig.info("WorldView3D", "built (map=%s, houses=%d, people=%d, buildings=%d, ms=%d)" % [s.state.map_id, town.houses.size(),
		town.people.size(), s.state.buildings.size(), build_ms])
	town_built.emit(build_ms)


## Frees the town now and the nodes it kept out of the tree (the house pieces opt3d merged, prototypes): they are not
## its children, so freeing the town alone would leave them (and their meshes) alive.
func _drop_town() -> void:
	if town == null:
		return
	remove_child(town)
	town.free()
	town = null
	_free_detached()


func _free_detached() -> void:
	var n := 0
	for id: int in Node.get_orphan_node_ids():
		if _baseline.has(id):
			continue
		var o := instance_from_id(id)
		if o is Node3D and is_instance_valid(o):  # the town's only: the UI's own detached nodes are not touched
			(o as Node3D).free()
			n += 1
	ViewConfig.info("WorldView3D", "detached nodes freed (%d)" % n)


## The quit: the tree frees the town; what it kept out of the tree and the shared caches go here.
func _exit_tree() -> void:
	if town != null:  # the weather's particles let go of their process materials before the renderer stops
		for n: Node in town.find_children("*", "GPUParticles3D", true, false):
			(n as GPUParticles3D).emitting = false
			(n as GPUParticles3D).process_material = null
	_free_detached()
	Town3D.clear_caches()


## H6's rebuild (something stands or no longer stands in the town): built again keeping the camera and the selection.
func rebuild_town() -> void:
	if town == null or sim == null:
		return
	var keep := [town.target, town.yaw, town.pitch, town.cam.size]
	var who := selected_id
	build(sim)
	town.target = keep[0]
	town.yaw = keep[1]
	town.pitch = keep[2]
	town.cam.size = keep[3]
	town._update_camera()
	if who != "":
		select(who)


## Shown and taking input (the town), or hidden and frozen while a menu screen or an interior covers it.
func set_active(active: bool) -> void:
	_active = active
	visible = active
	if town != null:
		town.set_process(active)
		town.set_process_unhandled_input(active)
		town.cam.current = active


func _process(_delta: float) -> void:
	_feed_time()
	_update_ring()


## The clock the town plays: the fraction of the step and the real seconds per game minute (gaits), the pause.
func _feed_time() -> void:
	if town == null or _game == null:
		return
	town.frac = _game.step_fraction()
	town.keys_on = keys_on
	var sps: float = _game.steps_per_second()
	town.paused = sps <= 0.0
	if sps > 0.0:
		town.real_per_minute = 1.0 / sps


## The camera on the selected person of the player's family (or on the middle of the map).
func _focus_start() -> void:
	var id := first_selectable()
	var st: WorldState = sim.state if sim != null else null
	if st != null and id != "":
		var p: Array = st.characters[id].get("position", [0, 0])
		town.look_at_tile(Vector2(float(p[0]), float(p[1])))
	elif town.W > 0:
		town.look_at_tile(Vector2(town.W / 2.0, town.H / 2.0))


## The first person of the human family who is in the town (sorted by id, as WorldView).
func first_selectable() -> String:
	if sim == null:
		return ""
	var st: WorldState = sim.state
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: Variant in ids:
		var ch: Dictionary = st.characters[id]
		if str(ch.get("controlled_by", "")) == "human" and bool(ch.get("alive", true)) and ch.has("position"):
			return str(id)
	return ""


func select(id: String) -> void:
	if id == selected_id:
		return
	selected_id = id
	selection_changed.emit(id)


func pick_building_id(id: String) -> void:
	picked_building = id
	building_picked.emit(id)


## The camera over a tile of the map (a notice clicked, the title's plaza, back from an interior).
func center_on_tile(t: Vector2i) -> void:
	if town != null:
		town.look_at_tile(Vector2(t))


## Where a person stands on screen (Vector2.INF if not drawn).
func screen_of(id: String) -> Vector2:
	return town.screen_of(id) if town != null else Vector2.INF


# ---------------------------------------------------------------- clicks
const PICK_RADIUS: float = 26.0                     # screen units around a person's chest
const PICK_HEIGHTS: Array[float] = [7.0, 4.5, 2.0, 0.0]  # metres along the ray where a building is looked for
var _ring: MeshInstance3D = null


func _unhandled_input(event: InputEvent) -> void:
	if town == null or not _active or not keys_on or not event is InputEventMouseButton or not event.is_pressed():
		return
	if handle_click(event as InputEventMouseButton):
		get_viewport().set_input_as_handled()


func handle_click(mb: InputEventMouseButton) -> bool:
	var st: WorldState = sim.state
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var who := pick_person(mb.position, true)
		if who != "":
			select(who)
			return true
		var npc := pick_person(mb.position, false)
		if npc != "":
			npc_picked.emit(npc)
			return true
		var bld := building_under(mb.position)
		pick_building_id(bld)
		if bld == "":
			select("")
		elif mb.double_click:
			ViewConfig.info("WorldView3D", "manage %s (double click)" % bld)
			manage_requested.emit(bld)
		return true
	if mb.button_index == MOUSE_BUTTON_RIGHT and selected_id != "" and order_sink.is_valid():
		var tile := tile_under(mb.position)
		for svc: Dictionary in SimQuery.map_services(st, sim.catalog):
			if svc["tile"] == tile or (svc.get("tiles", []) as Array).has(tile):
				var service: Vector2i = svc["service"]
				if not SimQuery.stands_on(st, selected_id, service):
					order_sink.call({"type": "move_to", "actor": selected_id, "tile": [service.x, service.y]})
				ViewConfig.info("WorldView3D", "order to %s %s (actor=%s, tile=%s)" % [svc["kind"], svc["id"], selected_id, service])
				service_requested.emit(selected_id, str(svc["kind"]), str(svc["id"]), service)
				return true
		var bld := building_under(mb.position)
		if bld != "":
			order_sink.call({"type": "enter_building", "actor": selected_id, "building": bld})
			ViewConfig.info("WorldView3D", "order enter_building (actor=%s, building=%s)" % [selected_id, bld])
		else:
			order_sink.call({"type": "move_to", "actor": selected_id, "tile": [tile.x, tile.y]})
			ViewConfig.info("WorldView3D", "order move_to (actor=%s, tile=%s)" % [selected_id, tile])
		service_requested.emit(selected_id, "", "", Vector2i.ZERO)
		return true
	return false


## The tile the camera ray through `screen` meets at height `h` (metres; 1 tile = 2 m).
func tile_under(screen: Vector2, h: float = 0.0) -> Vector2i:
	var o := town.cam.project_ray_origin(screen)
	var d := town.cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector2i(-1, -1)
	var p := o + d * ((h - o.y) / d.y)
	return Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))


## The sim building under the pointer: the first one the ray meets from the roofs down ("" if none).
func building_under(screen: Vector2) -> String:
	for h: float in PICK_HEIGHTS:
		var b := SimQuery.building_at(sim.state, tile_under(screen, h))
		if b != "":
			return b
	return ""


## The person nearest the pointer within PICK_RADIUS: of the player's family (`own`) or anybody else.
func pick_person(screen: Vector2, own: bool) -> String:
	var st: WorldState = sim.state
	var best := ""
	var best_d := PICK_RADIUS
	for id: Variant in town.people:
		var ch: Dictionary = st.characters.get(str(id), {})
		if (str(ch.get("controlled_by", "")) == "human") != own:
			continue
		var at := town.screen_of(str(id))
		if at == Vector2.INF:
			continue
		var d := at.distance_to(screen)
		if d < best_d:
			best_d = d
			best = str(id)
	return best


## A ring under the selected person's feet.
func _update_ring() -> void:
	if town == null:
		return
	if _ring == null or not is_instance_valid(_ring) or _ring.get_parent() != town:
		_ring = MeshInstance3D.new()
		var m := TorusMesh.new()
		m.inner_radius = 0.42
		m.outer_radius = 0.55
		_ring.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.3)
		_ring.material_override = mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		town.add_child(_ring)
	var n: Node3D = town.people[selected_id].node if town.people.has(selected_id) else null
	_ring.visible = n != null and n.visible
	if _ring.visible:
		_ring.position = n.position + Vector3(0, 0.05, 0)
