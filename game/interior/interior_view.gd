class_name InteriorView
extends Node2D
## The inside of a building (GDD 4.6.4, H2 greybox): the interior scene of its type (game/visuals/interiors/<type>.tscn:
## the room's Kit with its size and door, a Marker2D per station under Stations, the upgrade visuals under Upgrades),
## the stations as StationViews (with the station's scene inside) and the people inside (location == building) at
## their station or by the door. A view only: the production runs in the sim whether this is open or not (L1). It
## sends orders, never writes the state.
##
## Controls: left click on someone of the family inside selects them; on a station = go_to_station (or master_touch
## while its window is open, GDD 4.4.5); on the door = leave. Right click on a station = its context menu
## (StationMenu). Toolbar (top right): Upgrades (H5) · Storage · Staff (H4: StaffPanel, staff and hiring) ·
## Production (stations and, from H4, the employees' queue) · Exit. Management mode (no person, GDD 4.6.4): the
## same room opened from the map; leaving just closes it. Employees inside stand at their station like anybody
## else (CharacterView shows their badge); the station shows the cycle's bar.

signal selection_changed(char_id: String)
signal close_requested   # leave without an order (management mode, or nobody of the family inside)
## H3: a click on the counter of a public shop (the Armory) with someone inside: open the market panel of `stall`.
signal shop_requested(actor: String, stall: String)

const STAND: Vector2 = Vector2(-0.75, 0.25)  # where a worker stands, in tiles from its station's tile

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var manage: bool = false
var shop_stall: String = ""   # the market stall this building serves ("" = not a shop): its counter opens the market
var selected_id: String = ""
var size_tiles: Vector2i = Vector2i(1, 1)
var door_tile: Vector2i = Vector2i.ZERO
var wall_height: float = 36.0
var _room: Node2D = null         # the interior scene of game/visuals/interiors
var _upgrades: Dictionary = {}   # node name -> upgrade visual (moved into the objects layer, Y-sorted)
var _upgrades_minute: int = -1
var _pending: Dictionary = {}    # zone -> Marker2D of a station the building does not have yet (new_zone)
var _stations: Dictionary = {}   # zone -> StationView
var _station_tiles: Dictionary = {}  # zone -> Vector2i
var _views: Dictionary = {}      # chr_id -> CharacterView
var _cfg: Dictionary = {}
var _center: Vector2 = Vector2.ZERO
var _zoom: int = 2
var _bound: bool = false
var _player_family: String = ""


## The layer that holds the interior scene (under the objects).
func room_layer() -> Node2D:
	return get_node("%Room")


## The interior scene of the building open now (null before setup).
func room() -> Node2D:
	return _room


## The room's kit (GreyboxKit: size, door, floor and walls), or null if the scene has none.
func kit() -> GreyboxKit:
	return _room.get_node_or_null("Kit") as GreyboxKit if _room != null else null


## The floor pieces of the kit (null without a kit).
func floor_layer() -> Node2D:
	var k := kit()
	return k.floor_layer() if k != null else null


## The wall pieces of the kit (null without a kit).
func walls() -> Node2D:
	var k := kit()
	return k.walls() if k != null else null


## An upgrade visual of the room by its node name (data/upgrades: visual.interior_node), or null.
func upgrade_visual(node_name: String) -> Node2D:
	return _upgrades.get(node_name, null)


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


func staff_panel() -> StaffPanel:
	return get_node("%StaffPanel")


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%StorageButton as Button).toggled.connect(func(on: bool) -> void: show_storage(on))
	(%ProductionButton as Button).toggled.connect(func(on: bool) -> void: show_production(on))
	(%StaffButton as Button).toggled.connect(func(on: bool) -> void: show_staff(on))
	(%ExitButton as Button).pressed.connect(request_exit)
	storage_panel().closed.connect(func() -> void: (%StorageButton as Button).set_pressed_no_signal(false))
	production_panel().closed.connect(func() -> void: (%ProductionButton as Button).set_pressed_no_signal(false))
	staff_panel().closed.connect(func() -> void: (%StaffButton as Button).set_pressed_no_signal(false))


## Builds the room of `bld`. `who` = the person selected on the map (may be outside: then nobody acts until someone
## of the family inside is selected). `manage_mode` = opened with "Manage" (no person).
func setup(s: Sim, bld: String, who: String, manage_mode: bool) -> void:
	_bind()
	sim = s
	building = bld
	manage = manage_mode
	selected_id = who
	_cfg = ViewConfig.value("interior", {})
	for layer: Node in [room_layer(), objects()]:
		for n: Node in layer.get_children():
			layer.remove_child(n)
			n.queue_free()
	_upgrades.clear()
	_pending.clear()
	_stations.clear()
	_station_tiles.clear()
	_views.clear()
	var b: Dictionary = s.state.buildings.get(bld, {})
	shop_stall = SimQuery.shop_stall(s.state, s.catalog, bld)
	_player_family = SimQuery.player_family(s.state)
	_build_room(str(b.get("type", "")), b.get("zones", {}))
	_zoom = maxi(1, int(_cfg.get("zoom", 2)))
	var wall_h := wall_height
	var left := Iso.tile_to_world(Vector2i(0, size_tiles.y - 1)).x - Iso.TILE_W / 2.0
	var right := Iso.tile_to_world(Vector2i(size_tiles.x - 1, 0)).x + Iso.TILE_W / 2.0
	var top := Iso.tile_to_world(Vector2i.ZERO).y - Iso.TILE_H / 2.0 - wall_h
	var bottom := Iso.tile_to_world(size_tiles - Vector2i.ONE).y + Iso.TILE_H / 2.0
	var off: Array = _cfg.get("center_offset", [0, 0])
	_center = (Vector2((left + right) / 2.0, (top + bottom) / 2.0) + Vector2(float(off[0]), float(off[1]))).round()
	camera().position = _center
	camera().zoom = Vector2.ONE * _zoom
	var bname := SimQuery.building_label(s.state, s.catalog, bld)
	(%TitleLabel as Label).text = SimQuery.t_("ui.interior.title_manage" if manage_mode else "ui.interior.title") % bname
	(%StorageButton as Button).text = SimQuery.t_("ui.interior.storage")
	(%ProductionButton as Button).text = SimQuery.t_("ui.interior.production")
	(%UpgradesButton as Button).text = SimQuery.t_("ui.interior.upgrades")
	(%UpgradesButton as Button).tooltip_text = SimQuery.t_("ui.interior.upgrades_h5")
	(%StaffButton as Button).text = SimQuery.t_("ui.interior.staff")
	(%StaffButton as Button).tooltip_text = SimQuery.t_("ui.interior.staff_tip")
	(%ExitButton as Button).text = SimQuery.t_("ui.interior.exit")
	(%ExitButton as Button).tooltip_text = SimQuery.t_("ui.interior.exit_tip")
	# a shop is not managed: only the way out (and its counter opens the market panel)
	for n: String in ["StorageButton", "ProductionButton", "UpgradesButton", "StaffButton"]:
		(get_node("%" + n) as Button).visible = shop_stall == ""
	station_menu().order_sink = _give
	station_menu().close()
	storage_panel().order_sink = _give
	storage_panel().setup(s, bld, actor())
	production_panel().order_sink = _give
	production_panel().setup(s, bld, who)
	production_panel().close()
	storage_panel().close()
	staff_panel().order_sink = _give
	staff_panel().setup(s, bld, who)
	staff_panel().close()
	for n: String in ["StorageButton", "ProductionButton", "StaffButton"]:
		(get_node("%" + n) as Button).set_pressed_no_signal(false)
	sync()
	ViewConfig.info("Interior", "setup (building=%s, manage=%s, size=%s, door=%s, stations=%d, selected=%s)" % [bld,
		manage_mode, size_tiles, door_tile, _stations.size(), who])


## The interior scene of `type`: its Kit gives the size and the door; each Marker2D under Stations becomes a
## StationView at the marker (the marker's child is the station's look, else game/visuals/stations/<zone>.tscn); the
## upgrade visuals under Upgrades move into the objects layer so they sort with the people.
func _build_room(type: String, zones: Dictionary) -> void:
	_room = VisualPaths.instantiate("interiors", type)
	_room.name = "Room"
	room_layer().add_child(_room)
	var k := kit()
	if k != null:
		k.ensure_built()
	size_tiles = k.size if k != null else Vector2i(6, 6)
	door_tile = k.door if k != null else Vector2i.ZERO
	wall_height = k.wall_height if k != null else 36.0
	var markers: Array = []
	var holder := _room.get_node_or_null("Stations")
	if holder != null:
		for m: Node in holder.get_children():
			if m is Marker2D:
				markers.append(m)
	markers.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	for m: Marker2D in markers:
		if zones.has(str(m.name)):
			_add_station(m)
		else:
			m.visible = false  # a station that an upgrade adds (new_zone): it waits until the building has it
			_pending[str(m.name)] = m
	var ups := _room.get_node_or_null("Upgrades") as Node2D
	if ups != null:
		for u: Node in ups.get_children():
			if u is Node2D:
				ups.remove_child(u)
				u.owner = null
				(u as Node2D).position += ups.position
				objects().add_child(u)
				_upgrades[str(u.name)] = u
	for z: String in zones:
		if not _stations.has(z):
			ViewConfig.info("Interior", "no Marker2D Stations/%s in interiors/%s.tscn: station not drawn" % [z, type])
	_upgrades_minute = -1
	refresh_upgrades()


## A StationView at the marker `m` (its name is the zone): the marker's child is its look, else the station's scene.
func _add_station(m: Marker2D) -> void:
	var z := str(m.name)
	var look: Node2D = null
	for c: Node in m.get_children():
		if c is Node2D:
			look = c
			break
	if look != null:
		m.remove_child(look)
		look.owner = null
	else:
		look = VisualPaths.instantiate("stations", z)
	var sv := StationView.new()
	sv.setup(z, SimQuery.zone_name(z), _cfg, look)
	sv.position = (m.get_parent() as Node2D).position + m.position
	objects().add_child(sv)
	_stations[z] = sv
	_station_tiles[z] = Iso.world_to_tile(sv.position)
	_pending.erase(z)


## The upgrade visuals of the room: the nodes of Upgrades named by the building's finished upgrades
## (Upgrades.visuals "interior") are shown, the rest hidden.
func refresh_upgrades() -> void:
	if sim == null:
		return
	var zones: Dictionary = sim.state.buildings.get(building, {}).get("zones", {})
	for z: String in _pending.keys():
		if zones.has(z):
			ViewConfig.info("Interior", "new station %s (building=%s)" % [z, building])
			_add_station(_pending[z])
	var on := {}
	for v: Dictionary in Upgrades.visuals(sim, building).get("interior", []):
		on[str(v["node"])] = true
	for n: String in _upgrades:
		var u: Node2D = _upgrades[n]
		if u.visible != on.has(n):
			u.visible = on.has(n)
			ViewConfig.info("Interior", "upgrade visual %s %s (building=%s)" % [n, "on" if u.visible else "off", building])


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
	staff_panel().set_actor(id)
	production_panel().set_actor(id)
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
		(_views[id] as CharacterView).follow_badge(st, _player_family)
		(_views[id] as CharacterView).hovered = Staff.works_at(st, id, building)  # employees inside: name always shown
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
	if int(st.clock["minute"]) != _upgrades_minute:
		_upgrades_minute = int(st.clock["minute"])
		refresh_upgrades()
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
	var h := wall_height
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
	if shop_stall != "":
		open_shop()
		return
	var job := SimQuery.job_view(sim, building, zone)
	if bool(job.get("window_open", false)) and not bool(job.get("touched", false)):
		var worker := str(job.get("actor", ""))
		if str(sim.state.characters.get(worker, {}).get("controlled_by", "")) == "human":
			_give({"type": "master_touch", "actor": worker, "building": building, "zone": zone})
			return
	if actor() != "":
		_give({"type": "go_to_station", "actor": actor(), "zone": zone})


func open_station_menu(zone: String, screen: Vector2) -> void:
	if shop_stall != "":
		open_shop()
		return
	var vp := viewport_size()
	var at := Vector2(minf(screen.x + 6.0, vp.x - 180.0), minf(screen.y + 6.0, vp.y - 160.0))
	station_menu().open_for(sim, actor(), building, zone, at)


## The shop's counter: the market panel for the person inside (nobody of the family inside: nothing to do).
func open_shop() -> void:
	if actor() == "":
		ViewConfig.info("Interior", "shop counter without anybody inside (building=%s)" % building)
		return
	ViewConfig.info("Interior", "shop counter (building=%s, stall=%s, actor=%s)" % [building, shop_stall, actor()])
	shop_requested.emit(actor(), shop_stall)


func show_storage(on: bool) -> void:
	(%StorageButton as Button).set_pressed_no_signal(on)
	if on:
		show_production(false)
		show_staff(false)
		storage_panel().set_actor(actor())
		storage_panel().open()
	else:
		storage_panel().close()


func show_production(on: bool) -> void:
	(%ProductionButton as Button).set_pressed_no_signal(on)
	if on:
		show_storage(false)
		show_staff(false)
		production_panel().open()
	else:
		production_panel().close()


## The staff panel (H4): `tab` "staff" or "hire" ("" = the last one shown).
func show_staff(on: bool, tab: String = "") -> void:
	(%StaffButton as Button).set_pressed_no_signal(on)
	if on:
		show_storage(false)
		show_production(false)
		staff_panel().open(tab)
	else:
		staff_panel().close()


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
	if staff_panel().visible:
		show_staff(false)
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
