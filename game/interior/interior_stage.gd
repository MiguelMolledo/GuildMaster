class_name InteriorStage
extends Node
## What an interior built from data does while it is open (docs/gdd/04g_interiores.md 4.6.5.3-4.6.5.5). A view only:
## it reads the state and gives the same orders as the clicks; the sim never knows where anybody stands inside.
##
## - Floors: the floor of the person selected is shown; the floors above are hidden and the ones below in shade. The
##   mouse wheel, PageUp / PageDown or the floor button show another floor without moving anybody (as in The Sims).
## - Walls: an inner wall or door turns almost transparent (InteriorWall.faded) while the mouse, or else the person
##   selected, is in the room behind it.
## - People: your people and the employees walk inside (doors and stairs) to their station's spot, the customer spots
##   or the idle spots of the data; the walk is only drawn (the sim already counts them there: inside there is no
##   walking time). Customers (the counter's, 4.5.4) appear at their spot with a short fade, with a bubble of what
##   they want and their patience; a click on one sends the person selected to the counter to serve them.
## - The display (a prop with "display" in the data) shows the products for sale in the storage, up to its slots.

const WALK_TILES_PER_SECOND: float = 4.0
const FADE_SECONDS: float = 0.3
const DIM: Color = Color(0.42, 0.4, 0.5, 1.0)

var view: InteriorView
var type: String = ""
var d: Dictionary = {}
var rooms: Dictionary = {}       # level -> {Vector2i: room id}
var levels: Array[int] = []
var active: int = 0
var manual: Variant = null       # a floor picked by hand (wheel, keys, button), or null = follow the person selected
var focus_room: String = ""
var _walls: Array = []
var _containers: Dictionary = {}  # level != 0 -> Node2D in the objects layer
var _walk: Dictionary = {}       # chr -> {level, at: Vector2 (tile), path: Array [[level, Vector2i]], goal: String}
var _born: Dictionary = {}       # chr -> seconds since it appeared (customers fade in)
var _bubbles: Dictionary = {}    # chr -> OrderBubble
var _blocked: Dictionary = {}    # level -> {Vector2i: true}
var _doors: Dictionary = {}      # "level,c,r,side" -> true
var _links: Dictionary = {}      # "level,c,r" -> [level, Vector2i] (stairs)
var _shown_level: Variant = null
var _display_sig: String = ""
var _button: Button = null


## Hooks a stage to `v` for its room `room` when the room was built from data (InteriorBuilder). Returns it or null.
static func attach(v: InteriorView, room: Node2D) -> InteriorStage:
	var old := v.get_node_or_null("InteriorStage")
	if old != null:
		v.remove_child(old)
		old.queue_free()
	if room == null or not room.has_meta("interior_def"):
		return null
	# a wide interior may move its centre (data "center_offset", px), so the room leaves room to the panels
	var co: Array = InteriorDefs.def_of(str(room.get_meta("interior_def"))).get("center_offset", [])
	if co.size() == 2:
		var cfg: Dictionary = (v.get("_cfg") as Dictionary).duplicate()
		var base: Array = cfg.get("center_offset", [0, 0])
		cfg["center_offset"] = [float(base[0]) - float(co[0]), float(base[1]) - float(co[1])]
		v.set("_cfg", cfg)
	var s := InteriorStage.new()
	s.name = "InteriorStage"
	s.view = v
	s.type = str(room.get_meta("interior_def"))
	s.d = InteriorDefs.def_of(s.type)
	s._walls = room.get_meta("walls", [])
	v.add_child(s)
	s._setup(room)
	return s


func _setup(room: Node2D) -> void:
	rooms = InteriorDefs.room_map(d)
	for l: Variant in rooms:
		levels.append(int(l))
	levels.sort()
	for x: Dictionary in d.get("doors", []):
		var t: Array = x["tile"]
		_doors["%d,%d,%d,%s" % [int(x.get("floor", 0)), int(t[0]), int(t[1]), str(x["side"])]] = true
	for s: Dictionary in d.get("stairs", []):
		var a := [int(s["floor"]), Vector2i(int(s["from"][0]), int(s["from"][1]))]
		var b := [int(s["to_floor"]), Vector2i(int(s["to"][0]), int(s["to"][1]))]
		_links["%d,%d,%d" % [a[0], a[1].x, a[1].y]] = b
		_links["%d,%d,%d" % [b[0], b[1].x, b[1].y]] = a
	_build_blocked()
	# the floors above the ground one get their own sorted layer, drawn over it, so they can be hidden as a whole
	var objs := view.objects()
	for n: Node in objs.get_children():
		var lv := int(n.get_meta("level", 0))
		if lv == 0 or not (n is Node2D):
			continue
		var c := _container(lv)
		objs.remove_child(n)
		(n as Node2D).z_index = 0
		c.add_child(n)
	if levels.size() > 1:
		_make_button()
	_apply_level(0)
	if OS.is_debug_build():
		print("[InteriorStage] %s: plantas %s, %d paredes, %d escaleras" % [type, str(levels), _walls.size(),
			(d.get("stairs", []) as Array).size()])


func _container(level: int) -> Node2D:
	if not _containers.has(level):
		var c := Node2D.new()
		c.name = "Level%d" % level
		c.y_sort_enabled = true
		c.z_index = level * InteriorBuilder.LEVEL_Z
		view.objects().add_child(c)
		_containers[level] = c
	return _containers[level]


## The tiles nobody walks through: what stands on the floor (like tools/interiors/interiores.py Layout.blocked).
func _build_blocked() -> void:
	for l: int in levels:
		_blocked[l] = {}
	var all: Array = []
	all.append_array(d.get("props", []))
	all.append_array(d.get("resolved", []))
	var upg: Dictionary = d.get("upgrades", {})
	for n: String in upg:
		all.append_array(upg[n])
	var zones: Dictionary = d.get("stations", {})
	for z: String in zones:
		var s: Dictionary = zones[z]
		all.append({"id": str(s.get("prop", "")), "floor": s.get("floor", 0), "tile": s["tile"], "flip": s.get("flip", false)})
	for s: Dictionary in d.get("stairs", []):
		all.append({"id": s["prop"], "floor": s["floor"], "tile": s["tile"], "flip": s.get("flip", false)})
	for p: Dictionary in all:
		var pr := InteriorDefs.prop(str(p.get("id", "")))
		if bool(pr.get("walkable", false)) or bool(pr.get("hangs", false)) or p.has("lift") \
				or str(pr.get("category", "")) == "small":
			continue
		var l := int(p.get("floor", 0))
		if not _blocked.has(l):
			continue
		if str(p.get("id", "")) == "":
			var t: Array = p["tile"]
			_blocked[l][Vector2i(int(t[0]), int(t[1]))] = true
			continue
		for t: Vector2i in InteriorDefs.tiles_of(p):
			_blocked[l][t] = true


func _passable(level: int, a: Vector2i, b: Vector2i) -> bool:
	var rof: Dictionary = rooms.get(level, {})
	if not rof.has(b) or (_blocked[level] as Dictionary).has(b):
		return false
	if absi(InteriorDefs.step_of(d, level, a) - InteriorDefs.step_of(d, level, b)) > 1:
		return false
	if str(rof[a]) == str(rof[b]):
		return true
	if b.x == a.x + 1:
		return _doors.has("%d,%d,%d,nw" % [level, b.x, b.y])
	if b.x == a.x - 1:
		return _doors.has("%d,%d,%d,nw" % [level, a.x, a.y])
	if b.y == a.y + 1:
		return _doors.has("%d,%d,%d,ne" % [level, b.x, b.y])
	return _doors.has("%d,%d,%d,ne" % [level, a.x, a.y])


## The walk from (level, a) to (level2, b), by doors and stairs: [[level, Vector2i]...] without the start; [] if
## there is no way (then the person is just placed there).
func path(level: int, a: Vector2i, level2: int, b: Vector2i) -> Array:
	var start := "%d,%d,%d" % [level, a.x, a.y]
	var goal := "%d,%d,%d" % [level2, b.x, b.y]
	if start == goal:
		return []
	var prev := {start: ""}
	var nodes := {start: [level, a]}
	var q: Array = [start]
	while not q.is_empty():
		var k: String = q.pop_front()
		if k == goal:
			break
		var cur: Array = nodes[k]
		var l: int = cur[0]
		var t: Vector2i = cur[1]
		var nexts: Array = []
		for nb: Vector2i in [t + Vector2i(1, 0), t + Vector2i(-1, 0), t + Vector2i(0, 1), t + Vector2i(0, -1)]:
			# the goal is reachable even when it is the edge of a blocked thing (a spot right at a station)
			if _passable(l, t, nb) or ("%d,%d,%d" % [l, nb.x, nb.y] == goal and (rooms.get(l, {}) as Dictionary).has(nb)):
				nexts.append([l, nb])
		if _links.has(k):
			nexts.append(_links[k])
		for n: Array in nexts:
			var nk := "%d,%d,%d" % [int(n[0]), (n[1] as Vector2i).x, (n[1] as Vector2i).y]
			if not prev.has(nk):
				prev[nk] = k
				nodes[nk] = n
				q.append(nk)
	if not prev.has(goal):
		return []
	var out: Array = []
	var k2 := goal
	while k2 != start:
		out.push_front(nodes[k2])
		k2 = prev[k2]
	return out


# --- every frame -------------------------------------------------------------------------------------------------

## Whether the stage places this person (then InteriorView.sync leaves its position and motion to it).
func owns(_v: CharacterView) -> bool:
	return true


func _process(delta: float) -> void:
	if view == null or view.sim == null or not view.visible:
		return
	tick(delta)


## One step of the stage (the tests call it without a window): people, floor, walls and display.
func tick(delta: float) -> void:
	if view == null or view.sim == null:
		return
	if not has_meta("center0"):
		set_meta("center0", view.get("_center"))   # InteriorView.setup has placed the room by now
	_place_people(delta)
	var want: int = active
	if manual != null:
		want = int(manual)
	elif _walk.has(view.selected_id):
		want = int(_walk[view.selected_id]["level"])
	if _shown_level == null or int(_shown_level) != want:
		_apply_level(want)
	_focus()
	_refresh_display()


func _place_people(delta: float) -> void:
	var st := view.sim.state
	var views: Dictionary = view.get("_views")
	for id: String in _walk.keys():
		if not views.has(id):
			_walk.erase(id)
			_born.erase(id)
			_bubbles.erase(id)
	var customers: Array = []
	var others: Array = []
	for id: String in views:
		if Counter.is_customer_of(st, id, view.building):
			customers.append(id)
		else:
			others.append(id)
	customers.sort_custom(func(a: String, b: String) -> bool:
		var ta: Dictionary = st.characters[a].get("town", {})
		var tb: Dictionary = st.characters[b].get("town", {})
		var sa := int(ta.get("customer_since", 1 << 30))
		var sb := int(tb.get("customer_since", 1 << 30))
		return sa < sb or (sa == sb and a < b))
	others.sort()
	var spots: Array = []
	var cust: Dictionary = d.get("customers", {})
	spots.append_array(cust.get("counter", []))
	spots.append_array(cust.get("queue", []))
	var counter_tile := _station_tile("counter")
	for i: int in customers.size():
		var id: String = customers[i]
		var v: CharacterView = views[id]
		var spot: Dictionary = spots[mini(i, spots.size() - 1)] if not spots.is_empty() else {"tile": [0, 0]}
		var t: Array = spot["tile"]
		var tile := Vector2i(int(t[0]), int(t[1]))
		var lv := int(spot.get("floor", 0))
		_walk[id] = {"level": lv, "at": Vector2(tile), "path": [], "goal": "c%d" % i}
		v.position = InteriorDefs.spot_world(d, lv, Vector2(tile)).round()
		v.play_motion("idle", CharacterView.dir_of(Vector2(counter_tile - tile)))
		if not _born.has(id):
			_born[id] = 0.0
			if OS.is_debug_build():
				print("[InteriorStage] cliente %s aparece en %s (%s)" % [id, tile, "mostrador" if i < (cust.get("counter", []) as Array).size() else "cola"])
		_born[id] = float(_born[id]) + delta
		v.modulate.a = clampf(float(_born[id]) / FADE_SECONDS, 0.0, 1.0)
		_customer_bubble(id, v, i < (cust.get("counter", []) as Array).size())
		_show(v, lv)
	var idle: Array = d.get("idle", [])
	var idle_i := 0
	var zones: Dictionary = d.get("stations", {})
	for id: String in others:
		var v: CharacterView = views[id]
		var ch: Dictionary = st.characters[id]
		var zone := str(ch.get("station", ""))
		var lv := 0
		var tile := Vector2i.ZERO
		var face := "se"
		var goal := ""
		if zones.has(zone):
			var s: Dictionary = zones[zone]
			lv = int(s.get("floor", 0))
			var stand: Array = s.get("stand", [int(s["tile"][0]) - 1, int(s["tile"][1])])
			tile = Vector2i(int(stand[0]), int(stand[1]))
			face = CharacterView.dir_of(Vector2(_station_tile(zone) - tile))
			goal = "s:" + zone
		elif not idle.is_empty():
			var sp: Dictionary = idle[idle_i % idle.size()]
			idle_i += 1
			lv = int(sp.get("floor", 0))
			tile = Vector2i(int(sp["tile"][0]), int(sp["tile"][1]))
			goal = "i%d" % idle_i
		else:
			var et: Array = d.get("entrance", {}).get("tile", [0, 0])
			tile = Vector2i(int(et[0]) + 1, int(et[1]))
			goal = "door"
		var w: Dictionary = _walk.get(id, {})
		if w.is_empty():
			# just came in: from the street door (or right at the spot if it is out of reach)
			var et2: Array = d.get("entrance", {}).get("tile", [0, 0])
			var door := Vector2i(int(et2[0]), int(et2[1]))
			var lv0 := int(d.get("entrance", {}).get("floor", 0))
			w = {"level": lv0, "at": Vector2(door), "path": path(lv0, door, lv, tile), "goal": goal}
			if (w["path"] as Array).is_empty():
				w = {"level": lv, "at": Vector2(tile), "path": [], "goal": goal}
			_walk[id] = w
		elif str(w["goal"]) != goal:
			var here := Vector2i(roundi((w["at"] as Vector2).x), roundi((w["at"] as Vector2).y))
			w["path"] = path(int(w["level"]), here, lv, tile)
			w["goal"] = goal
			if (w["path"] as Array).is_empty():
				w["level"] = lv
				w["at"] = Vector2(tile)
			if OS.is_debug_build():
				print("[InteriorStage] %s va a %s (%d pasos)" % [id, goal, (w["path"] as Array).size()])
		var moving := _advance(w, delta)
		v.position = InteriorDefs.spot_world(d, int(w["level"]), w["at"]).round()
		if moving != Vector2.ZERO:
			v.play_motion("walk", CharacterView.dir_of(moving))
		elif zones.has(zone):
			v.play_motion(view.station_motion(st, id, zone), face)
		else:
			v.play_motion("idle", face)
		_show(v, int(w["level"]))


## Moves a walk on; returns the direction of the step being walked (ZERO when it stands).
func _advance(w: Dictionary, delta: float) -> Vector2:
	var p: Array = w["path"]
	var left := WALK_TILES_PER_SECOND * delta
	var dir := Vector2.ZERO
	while left > 0.0 and not p.is_empty():
		var nxt: Array = p[0]
		if int(nxt[0]) != int(w["level"]):
			w["level"] = int(nxt[0])   # the stairs: up (or down) in one step
			w["at"] = Vector2(nxt[1])
			p.pop_front()
			continue
		var to := Vector2(nxt[1])
		var at: Vector2 = w["at"]
		var dist := at.distance_to(to)
		dir = to - at
		if dist <= left:
			w["at"] = to
			left -= dist
			p.pop_front()
		else:
			w["at"] = at + (to - at) / dist * left
			left = 0.0
	return dir


func _station_tile(zone: String) -> Vector2i:
	var s: Dictionary = d.get("stations", {}).get(zone, {})
	var t: Array = s.get("tile", [0, 0])
	return Vector2i(int(t[0]), int(t[1]))


## Shows a person on its floor: hidden above the floor shown, in shade below it, drawn with its floor.
func _show(v: CharacterView, level: int) -> void:
	v.visible = level <= active
	v.z_index = level * InteriorBuilder.LEVEL_Z
	var base := DIM if level < active else Color.WHITE
	v.modulate = Color(base.r, base.g, base.b, v.modulate.a)


func _customer_bubble(id: String, v: CharacterView, at_counter: bool) -> void:
	var b: OrderBubble = _bubbles.get(id, null)
	if b == null or not is_instance_valid(b):
		b = OrderBubble.new()
		b.name = "OrderBubble"
		b.position = Vector2(0, -v.fig_height - 6)
		b.z_index = CharacterView.MARKS_Z
		v.add_child(b)
		_bubbles[id] = b
	var old := v.get_node_or_null("Bubble") as Node2D
	if old != null:
		old.visible = false   # the shop bubble of the street: this one says more
	var st := view.sim.state
	var t: Dictionary = st.characters[id].get("town", {})
	var cfg: Dictionary = view.sim.catalog.town.get("counter", {})
	var now := int(st.clock["minute"])
	var want := Counter.best_product(view.sim, view.building)
	b.item = str(want.get("item", ""))
	b.waiting = not at_counter
	var patience := float(cfg.get("patience_minutes", 60))
	if t.has("served_at"):
		var serve := float(cfg.get("serve_minutes", 10))
		b.served = clampf(1.0 - (float(int(t["served_at"]) - now) / maxf(1.0, serve)), 0.0, 1.0)
		b.patience = 1.0
	else:
		b.served = -1.0
		b.patience = clampf(1.0 - float(now - int(t.get("customer_since", now))) / maxf(1.0, patience), 0.0, 1.0)
	b.queue_redraw()


# --- floors and walls ----------------------------------------------------------------------------------------------

func _apply_level(level: int) -> void:
	level = clampi(level, levels[0] if not levels.is_empty() else 0, levels[-1] if not levels.is_empty() else 0)
	active = level
	_shown_level = level
	for l: int in _containers:
		var c: Node2D = _containers[l]
		c.visible = l <= level
		c.modulate = DIM if l < level else Color.WHITE
	var room := view.room()
	for layer: String in ["Backdrops", "Lights"]:
		var n := room.get_node_or_null(layer)
		if n == null:
			continue
		for h: Node in n.get_children():
			var l := int(h.get_meta("level", 0))
			(h as CanvasItem).visible = l <= level
			if layer == "Backdrops":
				(h as CanvasItem).modulate = DIM if l < level else Color.WHITE
			else:
				(h as CanvasItem).visible = l == level   # only the floor shown keeps its room light
	for n: Node in view.objects().get_children():
		if n is CanvasItem and not _containers.values().has(n) and not (n is CharacterView):
			var l := int(n.get_meta("level", 0))
			(n as CanvasItem).modulate = DIM if l < level else Color.WHITE
	# the camera looks at the floor shown (the room's centre, raised with it); the centre is known after setup
	if has_meta("center0"):
		var c0: Vector2 = get_meta("center0")
		view.set("_center", c0 + InteriorDefs.floor_offset(d, level) * 0.5)
		view.camera().position = view.call("_camera_position")
	if _button != null:
		_button.text = SimQuery.t_("ui.interior.floor_down" if level > 0 else "ui.interior.floor_up")
	if OS.is_debug_build():
		print("[InteriorStage] %s: se ve la planta %d" % [type, level])


## The room under the mouse on the floor shown, or else the one of the person selected: the walls in front of it
## turn transparent.
func _focus() -> void:
	var f := ""
	var vp := view.get_viewport()
	if vp != null:
		var world := view.screen_to_world(vp.get_mouse_position())
		var t := Iso.world_to_tile(world - InteriorDefs.floor_offset(d, active))
		f = str((rooms.get(active, {}) as Dictionary).get(t, ""))
	if f == "" and _walk.has(view.selected_id):
		var w: Dictionary = _walk[view.selected_id]
		if int(w["level"]) == active:
			var at: Vector2 = w["at"]
			f = str((rooms.get(active, {}) as Dictionary).get(Vector2i(roundi(at.x), roundi(at.y)), ""))
	if f == "":
		f = _main_room()  # nobody to follow: the workshop (or the first room) of the floor shown stays open
	set_focus(f)


## Opens the walls in front of room `f` of the floor shown (and closes the others).
func set_focus(f: String) -> void:
	if f == focus_room:
		return
	focus_room = f
	for w: InteriorWall in _walls:
		if is_instance_valid(w):
			w.faded = w.kind != "low" and w.level == active and w.behind == f and f != ""
	if OS.is_debug_build() and f != "":
		print("[InteriorStage] foco en la sala %s" % f)


## The room of the floor shown that stays open when nothing else is focused: the first workshop, shop or hall.
func _main_room() -> String:
	for t: String in ["workshop", "hall", "shop"]:
		for room: Dictionary in d.get("rooms", []):
			if int(room.get("floor", 0)) == active and str(room.get("type", "")) == t:
				return str(room["id"])
	for room: Dictionary in d.get("rooms", []):
		if int(room.get("floor", 0)) == active:
			return str(room["id"])
	return ""


# --- the display ---------------------------------------------------------------------------------------------------

## The products for sale (the storage's products, the dearest first), shown on each display up to its slots.
func _refresh_display() -> void:
	var inv: Dictionary = view.sim.state.buildings.get(view.building, {}).get("inventory", {})
	var wares: Array = []
	for s: Dictionary in inv.get("stacks", []):
		var item := str(s["item"])
		if int(s["qty"]) > 0 and str(view.sim.catalog.item(item).get("category", "")) == "product":
			for i: int in mini(int(s["qty"]), 6):
				wares.append(item)
	wares.sort_custom(func(a: String, b: String) -> bool:
		var pa := int(view.sim.catalog.item(a).get("base_price", 0))
		var pb := int(view.sim.catalog.item(b).get("base_price", 0))
		return pa > pb or (pa == pb and a < b))
	var sig := ",".join(PackedStringArray(wares))
	if sig == _display_sig:
		return
	_display_sig = sig
	var k := 0
	for n: Node in _all_objects():
		var props: Array = [n]
		if n is CanvasItem and not (n as CanvasItem).visible:
			continue   # an upgrade not built yet: its display shows nothing
		if n.get_child_count() > 0 and not n.has_meta("prop"):
			props = n.get_children()   # an upgrade node: its props
		for p: Node in props:
			if not p.has_meta("display"):
				continue
			for c: Node in p.get_children():
				if str(c.name).begins_with("Ware"):
					c.queue_free()
			var slots := int(p.get_meta("display"))
			var pr := InteriorDefs.prop(str(p.get_meta("prop")))
			var h := float(pr.get("height", 30))
			var fp: Array = pr.get("footprint", [1, 1])
			var flip := bool(p.get_meta("display_flip", false))
			var axis := Vector2(-32, -16) if flip else Vector2(32, -16)
			for i: int in slots:
				if k >= wares.size():
					break
				var tex := VisualPaths.icon_small(str(wares[k]))
				k += 1
				if tex == null:
					continue
				var s := Sprite2D.new()
				s.name = "Ware%d" % i
				s.texture = tex
				s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var along := 0.0
				if int(fp[0]) > 1:
					along = (float(i) + 0.5) / float(slots) - 0.5
					s.position = axis * along * float(fp[0]) * 0.8 + Vector2(0, -h * 0.55)
				else:
					s.position = Vector2(0, -h * 0.3 - float(i) * 10.0)
				s.position = s.position.round()
				(p as Node).add_child(s)
	if OS.is_debug_build():
		print("[InteriorStage] expositor: %d piezas a la vista de %d a la venta" % [mini(k, wares.size()), wares.size()])


func _all_objects() -> Array:
	var out: Array = []
	for n: Node in view.objects().get_children():
		if _containers.values().has(n):
			out.append_array(n.get_children())
		else:
			out.append(n)
	return out


# --- input ---------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if view == null or not view.visible or view.sim == null:
		return
	if event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if levels.size() > 1 and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			show_level(active + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and attend_at(mb.position):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and levels.size() > 1:
		var k := (event as InputEventKey).keycode
		if k == KEY_PAGEUP or k == KEY_PAGEDOWN:
			show_level(active + (1 if k == KEY_PAGEUP else -1))
			get_viewport().set_input_as_handled()


## Shows floor `level` by hand (nobody moves). Back to following the person selected when they change floor.
func show_level(level: int) -> void:
	if levels.is_empty():
		return
	manual = clampi(level, levels[0], levels[-1])
	_apply_level(int(manual))


## A click on a customer: the person selected inside goes to the counter to serve them (go_to_station counter, the
## same order as a click on the counter). True if it was a customer.
func attend_at(screen: Vector2) -> bool:
	var who := view.pick_character(screen)
	var world := view.screen_to_world(screen)
	if who == "":
		var views: Dictionary = view.get("_views")
		for id: String in views:
			var v: CharacterView = views[id]
			if v.visible and Counter.is_customer_of(view.sim.state, id, view.building) and v.pick_rect().has_point(world):
				who = id
				break
	if who == "" or not Counter.is_customer_of(view.sim.state, who, view.building):
		return false
	var actor := view.actor()
	if actor == "":
		return true
	var zones: Dictionary = view.sim.state.buildings.get(view.building, {}).get("zones", {})
	var occ := str(zones.get("counter", {}).get("occupant", ""))
	if occ == actor:
		return true
	if occ != "":
		var sv := view.station_view("counter")
		if sv != null:
			sv.flash(SimQuery.t_("ui.interior.counter_busy"))
		return true
	if OS.is_debug_build():
		print("[InteriorStage] %s va al mostrador a atender a %s" % [actor, who])
	view.call("_give", {"type": "go_to_station", "actor": actor, "zone": "counter"})
	return true


func _make_button() -> void:
	var ui := view.get_node_or_null("%Ui") as CanvasLayer
	if ui == null:
		return
	_button = Button.new()
	_button.name = "FloorButton"
	_button.text = SimQuery.t_("ui.interior.floor_up")
	_button.tooltip_text = SimQuery.t_("ui.interior.floor_tip")
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func() -> void: show_level(0 if active > 0 else 1))
	ui.add_child(_button)
	_button.position = Vector2(view.viewport_size().x - 104, view.viewport_size().y - 72)
	_button.size = Vector2(96, 18)
