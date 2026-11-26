class_name AppTutorialContext
extends TutorialContext
## The tutorial's view of the running game (docs/ui/05_tutorial.md §7): the app's HUD, interior and world, Game's
## pause and speed, the sim's state (read only). It turns what changes into UI events (poll), answers the conditions
## and the symbols, finds world targets on screen and moves the camera to them. Gives no orders.
## 3D (docs/3d/plan.md M3D-3): with the 3D town (app.world3d()) the targets are projected from the 3D world, the
## stations of a house open in place from InteriorView's projector, and the camera pans in 3D.

var app: Node = null
var _events: Array = []          # UI events waiting for the next poll (signals: orders, selection, picked building)
var _panels: Dictionary = {}     # panel name -> was visible
var _interior: String = ""
var _paused: bool = false
var _speed: int = 1
var _zoom: int = -1
var _cam: Vector2 = Vector2.INF
var _help: bool = false
var _zoom3: float = -1.0   # 3D: the camera size last counted as a zoom


func _init(a: Node) -> void:
	app = a
	Game.order_given.connect(func(o: Dictionary) -> void: _events.append(["order_given", o.duplicate(true)]))
	app.world().selection_changed.connect(func(id: String) -> void: _events.append(["selected", {"id": id}]))
	app.world().building_picked.connect(func(id: String) -> void: _events.append(["building_picked", {"id": id}]))
	var w3: WorldView3D = app.call("world3d")
	if w3 != null:
		w3.selection_changed.connect(func(id: String) -> void: _events.append(["selected", {"id": id}]))
		w3.building_picked.connect(func(id: String) -> void: _events.append(["building_picked", {"id": id}]))
	_paused = Game.paused
	_speed = Game.speed


func _sim() -> Sim:
	return Game.sim


func _fam() -> String:
	return SimQuery.player_family(Game.sim.state) if Game.sim != null else ""


func ui_roots() -> Array:
	var out: Array = [app.hud()]
	var ui: Node = (app.interior() as Node).get_node_or_null("%Ui")
	if ui != null:
		out.append(ui)
	var cards: Node = app.get_node_or_null("CardsLayer")
	if cards != null:
		out.append(cards)
	return out


func blocked() -> bool:
	return Game.sim == null or app.menu_open() or not (app.hud() as CanvasLayer).visible


func help_open() -> bool:
	return bool(app.hud().call("help_visible"))


func interior_open() -> bool:
	return str(app.interior_building) != ""


func place_of(node: Node) -> String:
	return "interior" if node != null and app.interior().is_ancestor_of(node) else ""


func set_paused(on: bool) -> void:
	Game.set_paused(on)


func camera_screen() -> Vector2:
	var t3 := _town3d()
	if t3 != null:   # what the camera looks at, in screen units at the current size
		var vh := maxf(1.0, app.get_viewport().get_visible_rect().size.y)
		return Vector2(t3.target.x, t3.target.z) / (t3.cam.size / vh)
	var cam: WorldCamera = app.world().camera()
	return cam.position * float(cam.current_zoom())


func _town3d() -> Town3D:
	var w3: WorldView3D = app.call("world3d")
	return w3.town if w3 != null else null


func passthrough() -> Array:
	var out: Array = []
	for n: String in ["PauseButton", "Speeds"]:
		var c := find_ui(n)
		if shown(c):
			out.append(node_rect(c))
	return out


# --- symbols and texts -------------------------------------------------------------------------------------------------

func symbol(v: Variant, ev: Dictionary = {}) -> Variant:
	if not v is String or not str(v).begins_with("$") or Game.sim == null:
		return v
	var st := Game.sim.state
	match str(v):
		"$head":
			return Kin.head(st, _fam())
		"$active":
			return app.hud().active_person()
		"$workshop":
			return workshop()
		"$first_station":
			return first_station()
		"$tavern":  # posada: the family's Taberna-Posada (the first by id)
			var ids: Array = st.buildings.keys()
			ids.sort()
			for b: Variant in ids:
				if Inn.is_inn(Game.sim, str(b)) and str(st.buildings[b].get("owner", "")) == _fam():
					return str(b)
			return ""
	return super.symbol(v, ev)


## The player's own building with work stations (the forge, the carpentry...): the first one by id.
func workshop() -> String:
	if Game.sim == null:
		return ""
	var st := Game.sim.state
	var ids: Array = st.buildings.keys()
	ids.sort()
	for id: Variant in ids:
		var b: Dictionary = st.buildings[id]
		if str(b.get("owner", "")) != _fam():
			continue
		for z: Dictionary in Game.sim.catalog.buildings().get(str(b.get("type", "")), {}).get("zones", []):
			if str(z.get("kind", "")) == "craft":
				return str(id)
	return ""


## The first work station of the building open inside (or of the workshop).
func first_station() -> String:
	var bld := str(app.interior_building) if interior_open() else workshop()
	if Game.sim == null or not Game.sim.state.buildings.has(bld):
		return ""
	var type := str(Game.sim.state.buildings[bld].get("type", ""))
	for z: Dictionary in Game.sim.catalog.buildings().get(type, {}).get("zones", []):
		if str(z.get("kind", "")) == "craft":
			return str(z.get("id", ""))
	return ""


func text_args() -> Dictionary:
	if Game.sim == null:
		return {}
	var st := Game.sim.state
	var fam := _fam()
	var ws := workshop()
	var type := str(st.buildings.get(ws, {}).get("type", ""))
	var wname := tr(str(Game.sim.catalog.buildings().get(type, {}).get("name_key", "")))
	return {"head": str(st.characters.get(Kin.head(st, fam), {}).get("name", "")),
		"active": str(st.characters.get(app.hud().active_person(), {}).get("name", "")),
		"workshop": wname.to_lower(),
		"town": town_name(st.map_id), "family": str(st.families.get(fam, {}).get("name", ""))}


func mine(e: Dictionary) -> bool:
	if Game.sim == null:
		return false
	var st := Game.sim.state
	var fam := str(e.get("family", ""))
	if fam == "":
		fam = Money.family_of(st, str(e.get("actor", "")))
	if fam == "":
		fam = Money.family_of(st, str(e.get("building", "")))
	return fam != "" and fam == _fam()


# --- conditions --------------------------------------------------------------------------------------------------------

func state_value(name: String, t: Dictionary) -> bool:
	if Game.sim == null:
		return false
	var st := Game.sim.state
	var want: Variant = symbol(t.get("is"))
	match name:
		"unlocked":   # an unlock of 03b open for the player's family (a chapter waits for its mechanic: jugador J4)
			return Unlocks.is_open(st, SimQuery.player_family(st), str(want))
		"paused":
			return Game.paused == bool(want)
		"speed":
			return not Game.paused and Game.speed == int(want)
		"selected":
			return str(app.call("_selected")) == str(want)
		"picked_building":
			var w3: WorldView3D = app.call("world3d")
			return str(w3.picked_building if w3 != null else app.world().picked_building) == str(want)
		"interior":
			return str(app.interior_building) == str(want)
		"interior_type":
			return interior_open() and str(st.buildings.get(str(app.interior_building), {}).get("type", "")) == str(want)
		"storage_has":
			var b := str(symbol(t.get("building", "$workshop")))
			var inv: Variant = st.buildings.get(b, {}).get("inventory")
			return inv is Dictionary and Inventory.count(inv, str(t.get("item", ""))) >= int(t.get("qty", 1))
		"carries":
			var who := str(app.hud().active_person())
			var inv: Variant = st.characters.get(who, {}).get("inventory")
			return inv is Dictionary and Inventory.count(inv, str(t.get("item", ""))) >= int(t.get("qty", 1))
		"gold_gte":
			return Money.gold(st, _fam()) >= int(want)
		"objective":
			return str(Objectives.view(Game.sim, _fam()).get("current", "")) == str(want)
		"objective_done":
			return str(want) in (Objectives.view(Game.sim, _fam()).get("done", []) as Array)
		"has_trial":
			return (not Tribunal.of_family(Game.sim, _fam(), true).is_empty()) == bool(want)
		"event_active":
			return (SimQuery.events_line(Game.sim) != "") == bool(want)
		"profession":
			var type := str(st.buildings.get(workshop(), {}).get("type", ""))
			for p: Dictionary in Game.sim.catalog.professions().values():
				if str(p.get("building", "")) == type:
					return str(p.get("id", "")) == str(want)
			return false
	return false


# --- the world ---------------------------------------------------------------------------------------------------------

func world_rect(t: Dictionary, ev: Dictionary = {}) -> Dictionary:
	if Game.sim == null:
		return {"rect": Rect2(), "need": "none"}
	var st := Game.sim.state
	var kind := str(t.get("world", ""))
	var id := str(symbol(t.get("id", ""), ev))
	if kind == "station":
		if not interior_open():
			return {"rect": Rect2(), "need": "@interior"}
		var sv: StationView = app.interior().station_view(id)
		if sv == null:
			return {"rect": Rect2(), "need": "@town"}
		if app.interior().get("projector") != null:   # 3D: around the station's middle on screen
			var c3: Vector2 = app.interior().station_screen(id)
			if c3 == Vector2.INF:
				return {"rect": Rect2(), "need": "none"}
			return {"rect": Rect2(c3 - Vector2(30, 40), Vector2(60, 64)), "need": ""}
		return {"rect": _poly_rect(sv.pick_polygon(), sv.position, func(p: Vector2) -> Vector2:
			return app.interior().world_to_screen(p)), "need": ""}
	if interior_open():
		return {"rect": Rect2(), "need": "@town"}
	if _town3d() != null:
		return _world_rect3d(t, kind, id)
	var world: WorldView = app.world()
	var cam: WorldCamera = world.camera()
	var to_screen := func(p: Vector2) -> Vector2: return cam.world_to_screen(p)
	match kind:
		"building", "door":
			var bld := id if t.has("id") else _building_of_type(str(t.get("type", "")))
			var b: Dictionary = st.buildings.get(bld, {})
			if b.is_empty():
				return {"rect": Rect2(), "need": "none"}
			if kind == "door":
				var d: Array = b.get("door", [])
				return {"rect": _tile_rect(Vector2i(int(d[0]), int(d[1])), 24.0, to_screen), "need": ""} if d.size() == 2 \
					else {"rect": Rect2(), "need": "none"}
			return {"rect": _building_rect(world, bld, b, to_screen), "need": ""}
		"character":
			var v: CharacterView = world.view_of(id)
			if v == null or not v.visible:
				return {"rect": Rect2(), "need": "none"}
			var r: Rect2 = v.pick_rect()
			var a: Vector2 = to_screen.call(r.position)
			var e: Vector2 = to_screen.call(r.end)
			return {"rect": Rect2(a, e - a), "need": ""}
		"service":
			var c := world.service_screen(id)
			if c.x < 0.0:
				return {"rect": Rect2(), "need": "none"}
			var z := float(cam.current_zoom())
			return {"rect": Rect2(c - Vector2(18, 16) * z, Vector2(36, 32) * z), "need": ""}
		"tile":
			var at: Array = t.get("at", [0, 0])
			return {"rect": _tile_rect(Vector2i(int(at[0]), int(at[1])), 0.0, to_screen), "need": ""}
	return {"rect": Rect2(), "need": "none"}


## The 3D town's targets: the screen box of a few 3D points (a building's footprint up to its roof, a tile, a door, a
## stall), a person's body.
func _world_rect3d(t: Dictionary, kind: String, id: String) -> Dictionary:
	var st := Game.sim.state
	var w3: WorldView3D = app.call("world3d")
	var town := w3.town
	match kind:
		"building", "door":
			var bld := id if t.has("id") else _building_of_type(str(t.get("type", "")))
			var b: Dictionary = st.buildings.get(bld, {})
			if b.is_empty():
				return {"rect": Rect2(), "need": "none"}
			if kind == "door":
				var d: Array = b.get("door", [])
				return {"rect": _box3d(town, Vector2i(int(d[0]), int(d[1])), Vector2i.ONE, 2.4), "need": ""} if d.size() == 2 \
					else {"rect": Rect2(), "need": "none"}
			var top := 7.0
			if town.bld_anchor.has(bld):
				top = float((town.bld_anchor[bld].house as Node3D).get_meta("top", 7.0))
			var o: Array = b.get("origin", [0, 0])
			var f: Array = b.get("footprint", [1, 1])
			return {"rect": _box3d(town, Vector2i(int(o[0]), int(o[1])), Vector2i(int(f[0]), int(f[1])), top), "need": ""}
		"character":
			var at := w3.screen_of(id)
			if at == Vector2.INF:
				return {"rect": Rect2(), "need": "none"}
			return {"rect": Rect2(at - Vector2(16, 36), Vector2(32, 64)), "need": ""}
		"service":
			for svc: Dictionary in SimQuery.map_services(st, Game.sim.catalog):
				if str(svc["id"]) == id or str(svc.get("kind", "")) == id:
					return {"rect": _box3d(town, svc["tile"], Vector2i.ONE, 2.6), "need": ""}
			return {"rect": Rect2(), "need": "none"}
		"tile":
			var at2: Array = t.get("at", [0, 0])
			return {"rect": _box3d(town, Vector2i(int(at2[0]), int(at2[1])), Vector2i.ONE, 0.0), "need": ""}
	return {"rect": Rect2(), "need": "none"}


## The screen box of the tiles from `o` of size `f` (2 m each) from the ground up to `h` metres.
static func _box3d(town: Town3D, o: Vector2i, f: Vector2i, h: float) -> Rect2:
	var r := Rect2()
	var first := true
	for x: float in [o.x * 2.0, (o.x + f.x) * 2.0]:
		for z: float in [o.y * 2.0, (o.y + f.y) * 2.0]:
			for y: float in [0.0, h]:
				var p := town.cam.unproject_position(Vector3(x, y, z))
				r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
				first = false
	return r


func _building_of_type(type: String) -> String:
	var ids: Array = Game.sim.state.buildings.keys()
	ids.sort()
	for id: Variant in ids:
		if str(Game.sim.state.buildings[id].get("type", "")) == type:
			return str(id)
	return ""


## The building on screen: its sprite as drawn (game/visuals/buildings/<type>.tscn, node Sprite), else the volume of
## its footprint's tiles raised by its block height.
func _building_rect(world: WorldView, id: String, b: Dictionary, to_screen: Callable) -> Rect2:
	var vis := world.building_visual(id)
	var spr := vis.get_node_or_null("Sprite") as Sprite2D if vis != null else null
	if spr != null and spr.is_visible_in_tree() and spr.texture != null:
		var lr := spr.get_rect()
		var xf := spr.global_transform
		var r := Rect2(to_screen.call(xf * lr.position), Vector2.ZERO)
		for c: Vector2 in [Vector2(lr.end.x, lr.position.y), lr.end, Vector2(lr.position.x, lr.end.y)]:
			r = r.expand(to_screen.call(xf * c))
		return r
	var heights: Variant = world.get("_building_heights")
	var h := float((heights as Dictionary).get(id, 48.0)) if heights is Dictionary else 48.0
	var o: Array = b.get("origin", [0, 0])
	var f: Array = b.get("footprint", [1, 1])
	var pts: Array[Vector2] = []
	for dr: int in [0, int(f[1]) - 1]:
		for dc: int in [0, int(f[0]) - 1]:
			var p := Iso.tile_to_world(Vector2i(int(o[0]) + dc, int(o[1]) + dr))
			for off: Vector2 in [Vector2(-Iso.TILE_W / 2.0, 0), Vector2(Iso.TILE_W / 2.0, 0), Vector2(0, -Iso.TILE_H / 2.0),
					Vector2(0, Iso.TILE_H / 2.0)]:
				pts.append(to_screen.call(p + off))
				pts.append(to_screen.call(p + off + Vector2(0, -h)))
	var r := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	return r


func _tile_rect(tile: Vector2i, up: float, to_screen: Callable) -> Rect2:
	var p := Iso.tile_to_world(tile)
	var a: Vector2 = to_screen.call(p + Vector2(-Iso.TILE_W / 2.0, -Iso.TILE_H / 2.0 - up))
	var e: Vector2 = to_screen.call(p + Vector2(Iso.TILE_W / 2.0, Iso.TILE_H / 2.0))
	return Rect2(a, e - a)


static func _poly_rect(poly: PackedVector2Array, at: Vector2, to_screen: Callable) -> Rect2:
	if poly.is_empty():
		var c: Vector2 = to_screen.call(at)
		return Rect2(c - Vector2(16, 24), Vector2(32, 32))
	var r := Rect2(to_screen.call(at + poly[0]), Vector2.ZERO)
	for p: Vector2 in poly:
		r = r.expand(to_screen.call(at + p))
	return r


func focus_camera(t: Dictionary, ev: Dictionary = {}) -> void:
	if not t.has("world") or str(t["world"]) == "station" or interior_open():
		return
	var w := world_rect(t, ev)
	if str(w.get("need", "none")) != "":
		return
	var r: Rect2 = w["rect"]
	var view := HudLayout.view_rect(app.get_viewport().get_visible_rect().size)
	var m := float((app.tutorial().config.get("look", {}) as Dictionary).get("camera_margin", 24.0))
	if view.grow(-m).has_point(r.get_center()) and view.encloses(r):
		return
	var delta := r.get_center() - view.get_center()
	var t3 := _town3d()
	if t3 != null:
		t3.pan_screen(-delta)   # the target comes to the middle of the free view
		if OS.is_debug_build():
			print("[Tutorial] camera 3D to %s (delta=%s)" % [t, delta])
		return
	var cam: WorldCamera = app.world().camera()
	cam.pan(delta)
	if OS.is_debug_build():
		print("[Tutorial] camera to %s (delta=%s)" % [t, delta])


# --- UI events ---------------------------------------------------------------------------------------------------------

func poll() -> Array:
	var out := _events
	_events = []
	if Game.sim == null:
		return out
	var cfg: Array = app.tutorial().config.get("panels", []) if app.has_method("tutorial") else []
	for name: Variant in cfg:
		var p := find_ui(str(name))
		var on := shown(p)
		if on != bool(_panels.get(str(name), false)):
			_panels[str(name)] = on
			out.append(["panel_opened" if on else "panel_closed", TutorialContext.panel_data(p) if p != null
				else {"panel": str(name)}])
	var inside := str(app.interior_building)
	if inside != _interior:
		if _interior != "":
			out.append(["interior_closed", {"building": _interior}])
		if inside != "":
			out.append(["interior_opened", {"building": inside,
				"type": str(Game.sim.state.buildings.get(inside, {}).get("type", ""))}])
		_interior = inside
	if Game.paused != _paused:
		_paused = Game.paused
		out.append(["paused" if _paused else "resumed", {}])
	if Game.speed != _speed:
		_speed = Game.speed
		out.append(["speed_changed", {"speed": _speed}])
	var t3 := _town3d()
	if t3 != null:   # 3D: the zoom changed when the camera's size moved a step of 10 % from the last one counted
		var size := t3.cam.size
		if _zoom3 < 0.0:
			_zoom3 = size
		elif absf(size - _zoom3) > _zoom3 * 0.1:
			out.append(["zoom_changed", {"zoom": int(size)}])
			_zoom3 = size
	else:
		var cam: WorldCamera = app.world().camera()
		if cam.current_zoom() != _zoom:
			if _zoom >= 0:
				out.append(["zoom_changed", {"zoom": cam.current_zoom()}])
			_zoom = cam.current_zoom()
	var at := camera_screen()
	if _cam != Vector2.INF and at.distance_to(_cam) >= 1.0:
		out.append(["camera_moved", {"px": at.distance_to(_cam)}])
	_cam = at
	var help: bool = app.hud().help_visible()
	if help != _help:
		_help = help
		if help:
			out.append(["help_opened", {}])
	return out


## The town's name as the region map says it (Vilarrasa, Bellcaire…); the map's working name only without a region
## (jugador J1: the tutorial said «Esto es Pueblo-calle»).
static func town_name(map_id: String) -> String:
	var home := RegionView.home_of(map_id)
	var key := str(RegionView.settlement(home).get("name_key", "")) if home != "" else ""
	return TranslationServer.translate(key) if key != "" else TranslationServer.translate("map." + map_id)
