class_name AppTutorialContext
extends TutorialContext
## The tutorial's view of the running game (docs/ui/05_tutorial.md §7): the app's HUD, interior and world, Game's
## pause and speed, the sim's state (read only). It turns what changes into UI events (poll), answers the conditions
## and the symbols, finds world targets on screen and moves the camera to them. Gives no orders.

var app: Node = null
var _events: Array = []          # UI events waiting for the next poll (signals: orders, selection, picked building)
var _panels: Dictionary = {}     # panel name -> was visible
var _interior: String = ""
var _paused: bool = false
var _speed: int = 1
var _zoom: int = -1
var _cam: Vector2 = Vector2.INF
var _help: bool = false


func _init(a: Node) -> void:
	app = a
	Game.order_given.connect(func(o: Dictionary) -> void: _events.append(["order_given", o.duplicate(true)]))
	app.world().selection_changed.connect(func(id: String) -> void: _events.append(["selected", {"id": id}]))
	app.world().building_picked.connect(func(id: String) -> void: _events.append(["building_picked", {"id": id}]))
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


func interior_open() -> bool:
	return str(app.interior_building) != ""


func place_of(node: Node) -> String:
	return "interior" if node != null and app.interior().is_ancestor_of(node) else ""


func set_paused(on: bool) -> void:
	Game.set_paused(on)


func camera_screen() -> Vector2:
	var cam: WorldCamera = app.world().camera()
	return cam.position * float(cam.current_zoom())


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
		"town": tr("map." + st.map_id), "family": str(st.families.get(fam, {}).get("name", ""))}


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
		"paused":
			return Game.paused == bool(want)
		"speed":
			return not Game.paused and Game.speed == int(want)
		"selected":
			return str(app.world().selected_id) == str(want)
		"picked_building":
			return str(app.world().picked_building) == str(want)
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
		return {"rect": _poly_rect(sv.pick_polygon(), sv.position, func(p: Vector2) -> Vector2:
			return app.interior().world_to_screen(p)), "need": ""}
	if interior_open():
		return {"rect": Rect2(), "need": "@town"}
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
	var cam: WorldCamera = app.world().camera()
	var delta := r.get_center() - view.get_center()
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
