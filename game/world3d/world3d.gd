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
## M3D-2: signs, the hover frame and rings, the names (Marks3D); the middle button drags the camera; selecting
## somebody who is off screen (1-2-3, a portrait, a notice) brings the camera to them; the hand over what can be clicked.

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
var marks: Marks3D = null       # signs, hover frame and rings, names
var hovered_building: String = ""
var hovered_character: String = ""
var _revealed: String = ""      # the selection the camera last looked for
var _marks_us: int = 0          # debug: what the marks cost per frame (logged every 600 frames)
var _marks_n: int = 0
var bridge: InteriorBridge3D = InteriorBridge3D.new()  # the house open in place, as InteriorView asks for it
var in_place: String = ""        # the sim building open in place ("" = none): the town takes no clicks meanwhile
var build_mode: bool = false     # H6: the building mode (B): the plots over the town, a left click is a plot's
var build_layer: BuildLayer3D = null


func _ready() -> void:
	marks = Marks3D.new()
	marks.name = "Marks3D"
	marks.view = self
	add_child(marks)
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
	in_place = ""
	town = Town3D.new()
	town.name = "Town3D"
	town.setup(s)
	add_child(town)
	town.set_process(_active)
	town.set_process_unhandled_input(_active)
	bridge.town = town
	bridge.sim = s
	_feed_time()
	if marks != null:
		marks.build()
	_setup_build_layer(s)
	_revealed = ""
	var ws := _workshop(s.state)
	if ws != "":
		town.premount(ws)   # the player's workshop opens at once (its furniture loads with the town)
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


## The player's family's first own building (by id): the workshop the game starts in.
static func _workshop(st: WorldState) -> String:
	var fam := SimQuery.player_family(st)
	var ids: Array = st.buildings.keys()
	ids.sort()
	for id: Variant in ids:
		if str(st.buildings[id].get("owner", "")) == fam and fam != "":
			return str(id)
	return ""


## H6's rebuild (something stands or no longer stands in the town): built again keeping the camera and the selection.
func rebuild_town() -> void:
	if town == null or sim == null:
		return
	var keep := [town.target, town.yaw, town.pitch, town.cam.size]
	var who := selected_id
	var was_open := in_place
	build(sim)
	if was_open != "":
		open_house(was_open)
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
	if marks != null:
		marks.visible = active
	if town != null:
		town.set_process(active)
		town.set_process_unhandled_input(active)
		town.cam.current = active


func _process(_delta: float) -> void:
	_feed_time()
	_update_ring()
	if town == null or not _active:
		return
	var mouse := get_viewport().get_mouse_position()
	var in_town := keys_on and in_place == "" and get_viewport().gui_get_hovered_control() == null
	var t0 := Time.get_ticks_usec()
	marks.update(mouse, in_town)
	_marks_us += Time.get_ticks_usec() - t0
	_marks_n += 1
	if _marks_n == 600 and OS.is_debug_build():
		print("[WorldView3D] marks: %.3f ms per frame (600 frames)" % (float(_marks_us) / 600000.0))
		_marks_us = 0
		_marks_n = 0
	if in_place != "":
		marks.visible = false   # the town's signs and rings wait while a house is open
	if marks.hovered_building != hovered_building or marks.hovered_character != hovered_character:
		hovered_building = marks.hovered_building
		hovered_character = marks.hovered_character
		if in_town:
			UiFeel.set_hand(hovered_building != "" or hovered_character != "")  # docs/ui/00 §9
	_reveal()


## The camera goes to the selected person when they are off screen (picked by 1-2-3, a portrait or a notice); a
## person inside a building: its door.
func _reveal() -> void:
	if selected_id == _revealed:
		return
	_revealed = selected_id
	if selected_id == "" or sim == null or not sim.state.characters.has(selected_id):
		return
	var at := screen_of(selected_id)
	var rect := get_viewport().get_visible_rect().grow(-60.0)
	if at != Vector2.INF and rect.has_point(at):
		return
	var ch: Dictionary = sim.state.characters[selected_id]
	var loc := str(ch.get("location", ""))
	var p: Array = sim.state.buildings.get(loc, {}).get("door", []) if loc != "" else ch.get("position", [])
	if p.size() == 2:
		ViewConfig.info("WorldView3D", "camera to %s (tile %s)" % [selected_id, p])
		town.look_at_tile(Vector2(float(p[0]), float(p[1])))


## The clock the town plays: the fraction of the step and the real seconds per game minute (gaits), the pause.
func _feed_time() -> void:
	if town == null or _game == null:
		return
	town.frac = _game.step_fraction()
	town.keys_on = keys_on
	town.look_on = keys_on and in_place == ""   # zooming in to look inside: not while the game has a house open
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


## M3D-3: opens sim building `b` in place (the game's InteriorView then uses `bridge`); false if its house has no
## interior in place (the game shows its 2D interior instead).
func open_house(b: String) -> bool:
	if town == null or not town.open_building(b):
		return false
	in_place = b
	bridge.building = b
	ViewConfig.info("WorldView3D", "open %s in place" % b)
	return true


## The camera or a house's cut is still moving (opening, closing): a click now would land somewhere else.
func settling() -> bool:
	return town != null and (town._busy or (town.situ_cut != null and is_instance_valid(town.situ_cut)
		and not town.situ_cut.settled))


func close_house() -> void:
	if town != null and in_place != "":
		town.close_building()
		ViewConfig.info("WorldView3D", "close %s" % in_place)
	in_place = ""


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
const SERVICE_HEIGHTS: Array[float] = [2.2, 1.2, 0.0]      # the same for a stall (awning, counter, ground)
var _ring: MeshInstance3D = null


func _unhandled_input(event: InputEvent) -> void:
	if town == null or not _active or not keys_on or in_place != "" or not event is InputEventMouseButton \
			or not event.is_pressed():
		return
	if handle_click(event as InputEventMouseButton):
		get_viewport().set_input_as_handled()


func handle_click(mb: InputEventMouseButton) -> bool:
	var st: WorldState = sim.state
	if build_mode and build_layer != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var plot := build_layer.plot_at(tile_under(mb.position))  # H6: in the building mode a click is a plot's
		if plot != "":
			ViewConfig.info("WorldView3D", "plot picked %s" % plot)
			plot_picked.emit(plot)
			return true
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
		var svc := service_under(mb.position)
		if not svc.is_empty():
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


## H6: the building mode (04 §4.9): the plots over the town (BuildLayer3D) and a click on one is the plot's.
func set_build_mode(on: bool) -> void:
	build_mode = on
	if build_layer != null:
		build_layer.set_on(on)


func _setup_build_layer(s: Sim) -> void:
	if build_layer == null:
		var layer := CanvasLayer.new()
		layer.name = "BuildCanvas"
		layer.layer = 0   # under the marks (1) and the HUD
		add_child(layer)
		build_layer = BuildLayer3D.new()
		build_layer.view = self
		layer.add_child(build_layer)
	build_layer.setup(self, s, SimQuery.player_family(s.state))
	build_layer.set_on(build_mode)


## The tile the camera ray through `screen` meets at height `h` (metres; 1 tile = 2 m).
func tile_under(screen: Vector2, h: float = 0.0) -> Vector2i:
	var o := town.cam.project_ray_origin(screen)
	var d := town.cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector2i(-1, -1)
	var p := o + d * ((h - o.y) / d.y)
	return Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))


## The map service (a stall, the board, the town hall: SimQuery.map_services) under the pointer, looked for along the
## ray from the awning down to the ground ({} if none).
func service_under(screen: Vector2) -> Dictionary:
	var svcs := SimQuery.map_services(sim.state, sim.catalog)
	for h: float in SERVICE_HEIGHTS:
		var tile := tile_under(screen, h)
		for svc: Dictionary in svcs:
			if svc["tile"] == tile or (svc.get("tiles", []) as Array).has(tile):
				return svc
	return {}


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


var _ring_name: Label3D = null   # the selected one's name inside the house open in place


## A ring under the selected person's feet (inside the house open in place, with the name over it).
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
	var inside := false
	if (n == null or not n.visible) and in_place != "" and bridge.ready() and bridge.view().live_actors.has(selected_id):
		n = bridge.view().live_actors[selected_id].node   # inside the house open in place: its body there
		inside = true
	_ring.visible = n != null and n.is_visible_in_tree()
	if _ring.visible:
		_ring.position = town.to_local(n.global_position) + Vector3(0, 0.05, 0)
	# inside, the town's own name label stays with the hidden street body: the selected one's name over the ring
	if _ring_name == null or not is_instance_valid(_ring_name) or _ring_name.get_parent() != town:
		_ring_name = town._label3d("", 40, Color(1, 1, 1))
		_ring_name.name = "RingName"
		town.add_child(_ring_name)
	_ring_name.visible = inside and _ring.visible and sim != null
	if _ring_name.visible:
		_ring_name.text = str(sim.state.characters.get(selected_id, {}).get("name", ""))
		_ring_name.position = _ring.position + Vector3(0, 2.0, 0)
