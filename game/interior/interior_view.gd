class_name InteriorView
extends Node2D
## The inside of a building (GDD 4.6.4, H2 greybox): an isometric room built from kit pieces (KitFloor, KitWall with
## the door) with the size, door and stations of the building's "interior" in data/buildings/<type>.json, the stations
## as StationViews and the people inside (location == building) at their station or by the door. A view only: the
## production runs in the sim whether this is open or not (L1). It sends orders, never writes the state.
##
## Controls: left click on someone of the family inside selects them; on a station = go_to_station (or master_touch
## while its window is open, GDD 4.4.5); on the door = leave. Right click on a station = its context menu
## (StationMenu). Toolbar (top right): Upgrades (H4) · Storage · Staff (H5) · Production · Exit. Management mode
## (no person, GDD 4.6.4): the same room opened from the map; leaving just closes it.

signal selection_changed(char_id: String)
signal close_requested   # leave without an order (management mode, or nobody of the family inside)

const STAND: Vector2 = Vector2(-0.75, 0.25)  # where a worker stands, in tiles from its station's tile

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var manage: bool = false
var selected_id: String = ""
var size_tiles: Vector2i = Vector2i(1, 1)
var door_tile: Vector2i = Vector2i.ZERO
var _stations: Dictionary = {}   # zone -> StationView
var _station_tiles: Dictionary = {}  # zone -> Vector2i
var _views: Dictionary = {}      # chr_id -> CharacterView
var _cfg: Dictionary = {}
var _center: Vector2 = Vector2.ZERO
var _zoom: int = 2
var _bound: bool = false


func floor_layer() -> Node2D:
	return get_node("%Floor")


func walls() -> Node2D:
	return get_node("%Walls")


func objects() -> Node2D:
	return get_node("%Objects")


func camera() -> Camera2D:
	return get_node("%Camera")


func station_menu() -> StationMenu:
	return get_node("%StationMenu")


func storage_panel() -> StoragePanel:
	return get_node("%StoragePanel")


func production_panel() -> ProductionPanel:
	return get_node("%ProductionPanel")


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%StorageButton as Button).toggled.connect(func(on: bool) -> void: show_storage(on))
	(%ProductionButton as Button).toggled.connect(func(on: bool) -> void: show_production(on))
	(%ExitButton as Button).pressed.connect(request_exit)
	storage_panel().closed.connect(func() -> void: (%StorageButton as Button).set_pressed_no_signal(false))
	production_panel().closed.connect(func() -> void: (%ProductionButton as Button).set_pressed_no_signal(false))


## Builds the room of `bld`. `who` = the person selected on the map (may be outside: then nobody acts until someone
## of the family inside is selected). `manage_mode` = opened with "Manage" (no person).
func setup(s: Sim, bld: String, who: String, manage_mode: bool) -> void:
	_bind()
	sim = s
	building = bld
	manage = manage_mode
	selected_id = who
	_cfg = ViewConfig.value("interior", {})
	for layer: Node in [floor_layer(), walls(), objects()]:
		for n: Node in layer.get_children():
			layer.remove_child(n)
			n.queue_free()
	_stations.clear()
	_station_tiles.clear()
	_views.clear()
	var b: Dictionary = s.state.buildings.get(bld, {})
	var def: Dictionary = s.catalog.buildings().get(str(b.get("type", "")), {})
	var inside: Dictionary = def.get("interior", {})
	var sz: Array = inside.get("size", [6, 6])
	size_tiles = Vector2i(int(sz[0]), int(sz[1]))
	var d: Array = inside.get("door", [0, 0])
	door_tile = Vector2i(int(d[0]), int(d[1]))
	_build_kit()
	var st: Dictionary = inside.get("stations", {})
	var zones: Array = st.keys()
	zones.sort()
	for z: String in zones:
		var t := Vector2i(int(st[z][0]), int(st[z][1]))
		var sv := StationView.new()
		sv.setup(z, SimQuery.zone_name(z), _cfg)
		sv.position = Iso.tile_to_world(t)
		objects().add_child(sv)
		_stations[z] = sv
		_station_tiles[z] = t
	_zoom = maxi(1, int(_cfg.get("zoom", 2)))
	var wall_h := float(_cfg.get("wall_height", 36))
	var left := Iso.tile_to_world(Vector2i(0, size_tiles.y - 1)).x - Iso.TILE_W / 2.0
	var right := Iso.tile_to_world(Vector2i(size_tiles.x - 1, 0)).x + Iso.TILE_W / 2.0
	var top := Iso.tile_to_world(Vector2i.ZERO).y - Iso.TILE_H / 2.0 - wall_h
	var bottom := Iso.tile_to_world(size_tiles - Vector2i.ONE).y + Iso.TILE_H / 2.0
	var off: Array = _cfg.get("center_offset", [0, 0])
	_center = (Vector2((left + right) / 2.0, (top + bottom) / 2.0) + Vector2(float(off[0]), float(off[1]))).round()
	camera().position = _center
	camera().zoom = Vector2.ONE * _zoom
	var bname := SimQuery.building_name(s.state, s.catalog, bld)
	(%TitleLabel as Label).text = SimQuery.t_("ui.interior.title_manage" if manage_mode else "ui.interior.title") % bname
	(%StorageButton as Button).text = SimQuery.t_("ui.interior.storage")
	(%ProductionButton as Button).text = SimQuery.t_("ui.interior.production")
	(%UpgradesButton as Button).text = SimQuery.t_("ui.interior.upgrades")
	(%UpgradesButton as Button).tooltip_text = SimQuery.t_("ui.interior.upgrades_later")
	(%StaffButton as Button).text = SimQuery.t_("ui.interior.staff")
	(%StaffButton as Button).tooltip_text = SimQuery.t_("ui.interior.staff_later")
	(%ExitButton as Button).text = SimQuery.t_("ui.interior.exit")
	(%ExitButton as Button).tooltip_text = SimQuery.t_("ui.interior.exit_tip")
	station_menu().order_sink = _give
	station_menu().close()
	storage_panel().order_sink = _give
	storage_panel().setup(s, bld, actor())
	production_panel().order_sink = _give
	production_panel().setup(s, bld)
	sync()
	ViewConfig.info("Interior", "setup (building=%s, manage=%s, size=%s, door=%s, stations=%d, selected=%s)" % [bld,
		manage_mode, size_tiles, door_tile, _stations.size(), who])


## The kit: a floor piece per tile, wall pieces on the two back edges, the door piece where the door is.
func _build_kit() -> void:
	var floor_c := ViewConfig.color(str(_cfg.get("floor", "#8a7660")))
	var wall_c := ViewConfig.color(str(_cfg.get("wall", "#5a4a3c")))
	var door_c := ViewConfig.color(str(_cfg.get("door", "#c8a050")))
	var wall_h := float(_cfg.get("wall_height", 36))
	for r: int in size_tiles.y:
		for c: int in size_tiles.x:
			var f := KitFloor.new()
			f.color = floor_c if (c + r) % 2 == 0 else floor_c.darkened(0.06)
			f.position = Iso.tile_to_world(Vector2i(c, r))
			floor_layer().add_child(f)
	for c: int in size_tiles.x:
		walls().add_child(_wall(Vector2i(c, 0), "ne", wall_h, wall_c, door_c))
	for r: int in size_tiles.y:
		walls().add_child(_wall(Vector2i(0, r), "nw", wall_h, wall_c, door_c))


func _wall(t: Vector2i, side: String, h: float, c: Color, door_c: Color) -> KitWall:
	var w := KitWall.new()
	w.side = side
	w.height = h
	w.color = c
	w.door_color = door_c
	w.door = t == door_tile and ((side == "nw" and t.x == 0) or (side == "ne" and t.y == 0))
	w.position = Iso.tile_to_world(t)
	if w.door:
		w.name = "Door"
	return w


func station_view(zone: String) -> StationView:
	return _stations.get(zone, null)


func view_of(id: String) -> CharacterView:
	return _views.get(id, null)


## Shown with its camera and toolbar, or hidden.
func set_active(active: bool) -> void:
	visible = active
	(%Ui as CanvasLayer).visible = active
	camera().enabled = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if active and camera().is_inside_tree():
		camera().make_current()
	if not active:
		station_menu().close()


## The selected person, if they are inside this building (who the orders are for); "" otherwise.
func actor() -> String:
	var ch: Dictionary = sim.state.characters.get(selected_id, {}) if sim != null else {}
	if ch.is_empty() or str(ch.get("location", "")) != building or not bool(ch.get("alive", true)):
		return ""
	return selected_id


func select(id: String) -> void:
	if id == selected_id:
		return
	selected_id = id
	for cid: String in _views:
		(_views[cid] as CharacterView).selected = cid == id
	storage_panel().set_actor(actor())
	ViewConfig.info("Interior", "selected %s" % (id if id != "" else "nobody"))
	selection_changed.emit(id)


func _process(_delta: float) -> void:
	if sim != null and visible:
		sync()


## Follows the state: who is inside and where, and each station's job.
func sync() -> void:
	if sim == null:
		return
	var st := sim.state
	var by_door: Array = []
	for id: String in st.characters:
		var ch: Dictionary = st.characters[id]
		var inside := str(ch.get("location", "")) == building and bool(ch.get("alive", true))
		if not inside:
			if _views.has(id):
				(_views[id] as CharacterView).queue_free()
				_views.erase(id)
			continue
		if not _views.has(id):
			var v := CharacterView.new()
			v.setup(ch, st.families.get(str(ch.get("family", "")), {}))
			v.selected = id == selected_id
			objects().add_child(v)
			_views[id] = v
		var zone := str(ch.get("station", ""))
		if _station_tiles.has(zone):
			# beside the station (to its left on screen), so the block and its bar stay visible
			(_views[id] as CharacterView).position = Iso.tilef_to_world(Vector2(_station_tiles[zone]) + STAND).round()
		else:
			by_door.append(id)
	by_door.sort()
	var spots: Array[Vector2] = [Vector2(1, 0), Vector2(1, -1), Vector2(1, 1), Vector2(2, 0), Vector2(2, -1), Vector2(2, 1)]
	for i: int in by_door.size():
		var spot: Vector2 = Vector2(door_tile) + spots[i % spots.size()]
		(_views[by_door[i]] as CharacterView).position = Iso.tilef_to_world(spot).round()
	var zones: Dictionary = st.buildings.get(building, {}).get("zones", {})
	for z: String in _stations:
		(_stations[z] as StationView).show_job(SimQuery.job_view(sim, building, z),
			str(zones.get(z, {}).get("occupant", "")) != "")


# --- picking ---------------------------------------------------------------------------------------------------------

func viewport_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(960, 540)


func screen_to_world(screen: Vector2) -> Vector2:
	return _center + (screen - viewport_size() / 2.0) / float(_zoom)


func world_to_screen(world: Vector2) -> Vector2:
	return (world - _center) * float(_zoom) + viewport_size() / 2.0


func station_screen(zone: String) -> Vector2:
	var sv := station_view(zone)
	return world_to_screen(sv.position + Vector2(0, -sv.height / 2.0))


func door_screen() -> Vector2:
	return world_to_screen(Iso.tile_to_world(door_tile))


func pick_character(screen: Vector2) -> String:
	var world := screen_to_world(screen)
	var best := ""
	var best_y := -INF
	for id: String in _views:
		var v: CharacterView = _views[id]
		if v.selectable and v.pick_rect().has_point(world) and v.position.y > best_y:
			best = id
			best_y = v.position.y
	return best


func pick_station(screen: Vector2) -> String:
	var world := screen_to_world(screen)
	for z: String in _stations:
		var sv: StationView = _stations[z]
		if Geometry2D.is_point_in_polygon(world - sv.position, sv.pick_polygon()):
			return z
	var t := Iso.world_to_tile(world)
	for z: String in _station_tiles:
		if _station_tiles[z] == t:
			return z
	return ""


## The door: its floor tile or the opening in the wall above it.
func is_door(screen: Vector2) -> bool:
	var world := screen_to_world(screen)
	if Iso.world_to_tile(world) == door_tile:
		return true
	var p := Iso.tile_to_world(door_tile)
	var h := float(_cfg.get("wall_height", 36))
	return Rect2(p + Vector2(-Iso.TILE_W / 2.0, -Iso.TILE_H / 2.0 - h), Vector2(Iso.TILE_W / 2.0 + 4, h + Iso.TILE_H / 2.0)).has_point(world)


# --- input -----------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if visible and handle_input(event):
		get_viewport().set_input_as_handled()


## Clicks in the room. True if used.
func handle_input(event: InputEvent) -> bool:
	if sim == null or not event is InputEventMouseButton or not event.is_pressed():
		return false
	var mb := event as InputEventMouseButton
	if event.is_action_pressed("select"):
		station_menu().close()
		var who := pick_character(mb.position)
		if who != "":
			select(who)
			return true
		var zone := pick_station(mb.position)
		if zone != "":
			click_station(zone)
			return true
		if is_door(mb.position):
			request_exit()
			return true
		return false
	if event.is_action_pressed("command"):
		var zone := pick_station(mb.position)
		if zone != "":
			open_station_menu(zone, mb.position)
			return true
		if is_door(mb.position):
			request_exit()
			return true
		station_menu().close()
	return false


## Left click on a station: the master touch while its window is open (for whoever works there), else go there.
func click_station(zone: String) -> void:
	var job := SimQuery.job_view(sim, building, zone)
	if bool(job.get("window_open", false)) and not bool(job.get("touched", false)):
		var worker := str(job.get("actor", ""))
		if str(sim.state.characters.get(worker, {}).get("controlled_by", "")) == "human":
			_give({"type": "master_touch", "actor": worker, "building": building, "zone": zone})
			return
	if actor() != "":
		_give({"type": "go_to_station", "actor": actor(), "zone": zone})


func open_station_menu(zone: String, screen: Vector2) -> void:
	var vp := viewport_size()
	var at := Vector2(minf(screen.x + 6.0, vp.x - 180.0), minf(screen.y + 6.0, vp.y - 160.0))
	station_menu().open_for(sim, actor(), building, zone, at)


func show_storage(on: bool) -> void:
	(%StorageButton as Button).set_pressed_no_signal(on)
	if on:
		show_production(false)
		storage_panel().set_actor(actor())
		storage_panel().open()
	else:
		storage_panel().close()


func show_production(on: bool) -> void:
	(%ProductionButton as Button).set_pressed_no_signal(on)
	if on:
		show_storage(false)
		production_panel().open()
	else:
		production_panel().close()


## ESC: closes the top thing open here (menu, then panel). False if there was nothing to close.
func close_top() -> bool:
	if station_menu().visible:
		station_menu().close()
		return true
	if storage_panel().visible:
		show_storage(false)
		return true
	if production_panel().visible:
		show_production(false)
		return true
	return false


## Door, Exit or ESC: the person inside walks out (exit_building; the view closes on building_left), or, in
## management mode or with nobody of the family inside selected, the view just closes.
func request_exit() -> void:
	var who := actor()
	if manage or who == "":
		ViewConfig.info("Interior", "close (building=%s, manage=%s)" % [building, manage])
		close_requested.emit()
		return
	_give({"type": "exit_building", "actor": who})


## Events of the sim that the room shows: the master touch landed, an item came out, a station is blocked.
func on_sim_event(e: Dictionary) -> void:
	if str(e.get("building", "")) != building:
		return
	var sv := station_view(str(e.get("zone", "")))
	match str(e.get("type", "")):
		"master_touch_done":
			if sv != null:
				sv.flash(SimQuery.t_("ui.interior.touch_done"))
		"work_done":
			if sv != null:
				sv.flash("+%d %s" % [int(e.get("qty", 1)), SimQuery.item_label(sim.catalog, str(e.get("item", "")),
					int(e.get("quality", 0)))])
		"station_blocked":
			if sv != null:
				sv.flash(SimQuery.t_("reason." + str(e.get("reason", ""))))


func _give(o: Dictionary) -> void:
	ViewConfig.info("Interior", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
