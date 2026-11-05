class_name InteriorBuilder
extends RefCounted
## Builds an interior from its data (docs/gdd/04g_interiores.md 4.6.5.2, data/interiors/<type>.json) with the same
## structure as the hand-made scenes of game/visuals/interiors/, so InteriorView, the upgrade preview and the gallery
## use it unchanged:
##   Kit       GreyboxKit with the grid size, the street door and the wall height (hidden: the art is below)
##   Backdrops the painted room of each room and floor (assets/art/interiors/<type>/room_<floor>_<room>.png) or, until
##             it exists, the fallback floor tiles and back walls of the prop library
##   Lights    one layer per room (data/interiors/lights.json)
##   Stations  a Marker2D per station at its feet, with its look (a library prop, or the station's scene)
##   Props     the props, the walls between rooms (InteriorWall), the low front walls and the stairs: the view moves
##             them into its objects layer so they sort with the people
##   Upgrades  a node per upgrade visual (data/upgrades visual.interior_node) with its props
## Every node built carries meta "level" (its floor); InteriorStage hides, dims and fades them. Floors other than the
## ground one draw over it: z_index level × LEVEL_Z (backdrops one below, lights in between).

const LEVEL_Z: int = 10

static var _type: String = ""   # the interior being built: its props come with the palette of its rooms


## The interior of `type`: built from data when data/interiors/<type>.json exists, else its scene.
static func instantiate(type: String) -> Node2D:
	var d := InteriorDefs.def_of(type)
	if d.is_empty():
		return VisualPaths.instantiate("interiors", type)
	return build(type, d)


static func build(type: String, d: Dictionary) -> Node2D:
	_type = type
	var root := Node2D.new()
	root.name = type.to_pascal_case() + "Interior"
	root.set_meta("interior_def", type)
	var size: Array = d.get("size", [6, 6])
	var wh := float(d.get("wall_height", 64))
	var ent: Dictionary = d.get("entrance", {})
	var kit := GreyboxKit.new()
	kit.name = "Kit"
	kit.size = Vector2i(int(size[0]), int(size[1]))
	var et: Array = ent.get("tile", [0, 0])
	kit.door = Vector2i(int(et[0]), int(et[1]))
	kit.wall_height = wh
	kit.visible = false
	root.add_child(kit)
	var rooms := InteriorDefs.room_map(d)
	var backs := _node(root, "Backdrops")
	var lights := _node(root, "Lights")
	var stations := _node(root, "Stations")
	var props := _node(root, "Props")
	var ups := _node(root, "Upgrades")
	var walls: Array = []
	for room: Dictionary in d.get("rooms", []):
		_backdrop(backs, type, d, room, rooms, wh)
		_light(lights, d, room, wh)
	for level: Variant in rooms:
		for w: InteriorWall in _walls(type, d, int(level), rooms[level], wh):
			props.add_child(w)
			walls.append(w)
	var zones: Dictionary = d.get("stations", {})
	for z: String in zones:
		stations.add_child(_station(d, z, zones[z]))
	var i := 0
	for p: Dictionary in (d.get("props", []) as Array) + (d.get("resolved", []) as Array):
		var n := _prop(d, p, "p%03d_%s" % [i, str(p["id"])], rooms)
		if n != null:
			props.add_child(n)
		i += 1
	for s: Dictionary in d.get("stairs", []):
		var n := _prop(d, {"id": s["prop"], "floor": s["floor"], "tile": s["tile"], "flip": s.get("flip", false)},
			"stairs_" + str(s.get("id", "s")), rooms)
		if n != null:
			n.set_meta("stairs", true)
			props.add_child(n)
	var upg: Dictionary = d.get("upgrades", {})
	for node: String in upg:
		var u := Node2D.new()
		u.name = node
		u.visible = false
		u.editor_description = "Upgrade visual %s (data/interiors/%s.json upgrades)" % [node, type]
		var list: Array = upg[node]
		var level := 0
		if not list.is_empty():
			var first: Dictionary = list[0]
			level = int(first.get("floor", 0))
			u.position = _feet(d, first)
			for p: Dictionary in list:
				var n := _prop(d, p, str(p["id"]), rooms)
				if n != null:
					n.position -= u.position
					u.add_child(n)
		u.set_meta("level", level)
		u.z_index = level * LEVEL_Z
		ups.add_child(u)
	# the Taberna-Posada's seats and beds (InnLayer reads Seats/Seat00.. and Beds/Bed0..: 04f 4.27.4), on their floor
	for pair: Array in [["seats", "Seats", "Seat%02d"], ["beds", "Beds", "Bed%d"]]:
		var spots: Array = d.get(str(pair[0]), [])
		if spots.is_empty():
			continue
		var holder := _node(root, str(pair[1]))
		for si: int in spots.size():
			var sp: Dictionary = spots[si]
			var m := Marker2D.new()
			m.name = str(pair[2]) % si
			var lv := int(sp.get("floor", 0))
			m.position = InteriorDefs.spot_world(d, lv, Vector2(float(sp["tile"][0]), float(sp["tile"][1])))
			m.set_meta("level", lv)
			holder.add_child(m)
	root.set_meta("walls", walls)
	if OS.is_debug_build():
		print("[InteriorBuilder] %s: %d salas, %d paredes, %d puestos, %d piezas, %d mejoras" % [type,
			(d.get("rooms", []) as Array).size(), walls.size(), zones.size(), props.get_child_count() - walls.size(),
			upg.size()])
	return root


static func _node(parent: Node, n: String) -> Node2D:
	var x := Node2D.new()
	x.name = n
	parent.add_child(x)
	return x


## Where a placed prop's node stands: its feet with the floor and the step offsets.
static func _feet(d: Dictionary, p: Dictionary) -> Vector2:
	var level := int(p.get("floor", 0))
	var t: Array = p.get("tile", [0, 0])
	var tile := Vector2i(int(t[0]), int(t[1]))
	return InteriorDefs.feet_world(p) + InteriorDefs.floor_offset(d, level) \
		+ Vector2(0, -float(InteriorDefs.step_of(d, level, tile)) * InteriorDefs.STEP_PX)


## A library prop as a node: its sprite with the feet on the node's position (flipped for the other diagonal),
## lifted onto the furniture it stands on, or hung on its wall.
static func _prop(d: Dictionary, p: Dictionary, n: String, _rooms: Dictionary) -> Node2D:
	var id := str(p.get("id", ""))
	var pr := InteriorDefs.prop(id)
	var tex := VisualPaths.interior_prop_in(_type, id)
	if pr.is_empty() or tex == null:
		if OS.is_debug_build():
			print("[InteriorBuilder] pieza sin catálogo o sin sprite: %s" % id)
		return null
	var level := int(p.get("floor", 0))
	var node := Node2D.new()
	node.name = n
	node.position = _feet(d, p)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var feet: Array = pr.get("feet", [0, 0])
	var fx := float(feet[0])
	var fy := float(feet[1])
	var flip := bool(p.get("flip", false))
	if flip:
		spr.flip_h = true
		fx = float(tex.get_width()) - fx
	var shift: Array = p.get("shift", [0, 0])
	var lift := float(p.get("lift", 0))
	spr.offset = Vector2(-fx + float(shift[0]), -fy - lift + float(shift[1]))
	if p.has("lift"):
		node.position.y += 1.0  # on a table: sorts just after it
	if p.has("hang"):
		# on the face of the wall segment of its tile: half way up, a little in front of the wall to sort after it
		var hs := str(p["hang"])
		var t: Array = p["tile"]
		node.position = Iso.tile_to_world(Vector2i(int(t[0]), int(t[1]))) + InteriorDefs.floor_offset(d, level) \
			+ Vector2(16.0 if hs == "ne" else -16.0, -7.0)
		spr.offset = Vector2(-float(tex.get_width()) / 2.0, -float(d.get("wall_height", 64)) / 2.0
			- float(tex.get_height()) / 2.0)
	node.add_child(spr)
	node.set_meta("level", level)
	node.set_meta("prop", id)
	if int(p.get("display", 0)) > 0:
		node.set_meta("display", int(p["display"]))
		node.set_meta("display_flip", flip)
	node.z_index = level * LEVEL_Z
	return node


## A station: a Marker2D at its feet; its look is a library prop (Feet, Top and Sprite, like the station scenes) or,
## without one, the scene of its station (game/visuals/stations/<zone or the zone it is like>.tscn).
static func _station(d: Dictionary, z: String, s: Dictionary) -> Marker2D:
	var m := Marker2D.new()
	m.name = z
	var level := int(s.get("floor", 0))
	m.set_meta("level", level)
	var p := {"id": str(s.get("prop", "")), "floor": level, "tile": s.get("tile", [0, 0]), "flip": s.get("flip", false)}
	if str(s.get("prop", "")) != "":
		m.position = _feet(d, p)
		var look := Node2D.new()
		look.name = "Look"
		var feet := Marker2D.new()
		feet.name = "Feet"
		look.add_child(feet)
		var pr := InteriorDefs.prop(str(s["prop"]))
		var top := Marker2D.new()
		top.name = "Top"
		top.position = Vector2(0, -float(pr.get("height", 20)))
		look.add_child(top)
		var n := _prop(d, p, "Prop", {})
		if n != null:
			n.position = Vector2.ZERO
			n.z_index = 0
			look.add_child(n)
		m.add_child(look)
	else:
		var t: Array = s.get("tile", [0, 0])
		var tile := Vector2i(int(t[0]), int(t[1]))
		m.position = Iso.tile_to_world(tile) + InteriorDefs.floor_offset(d, level) \
			+ Vector2(0, -float(InteriorDefs.step_of(d, level, tile)) * InteriorDefs.STEP_PX)
		var base := z
		if not VisualPaths.has_scene("stations", z) and z.rfind("_") > 0 and z.substr(z.rfind("_") + 1).is_valid_int():
			base = z.substr(0, z.rfind("_"))   # furnace_2 looks like furnace
		if base != z:
			m.add_child(VisualPaths.instantiate("stations", base))
	return m


## The walls of one floor: between rooms (inner, or door when data/doors has one there) and low walls on the front
## edges. The back walls of the building are in the painted backdrop.
static func _walls(type: String, d: Dictionary, level: int, rof: Dictionary, wh: float) -> Array[InteriorWall]:
	var doors := {}
	for x: Dictionary in d.get("doors", []):
		if int(x.get("floor", 0)) == level:
			var t: Array = x["tile"]
			doors["%d,%d,%s" % [int(t[0]), int(t[1]), str(x["side"])]] = true
	var styles := {}
	for room: Dictionary in d.get("rooms", []):
		styles[str(room["id"])] = str(room.get("wall_style", "timber"))
	var out: Array[InteriorWall] = []
	var tiles: Array = rof.keys()
	tiles.sort()
	for t: Vector2i in tiles:
		var room := str(rof[t])
		for pair: Array in [["nw", Vector2i(t.x - 1, t.y)], ["ne", Vector2i(t.x, t.y - 1)]]:
			var nb: Vector2i = pair[1]
			if not rof.has(nb) or str(rof[nb]) == room:
				continue
			var side := str(pair[0])
			var door := doors.has("%d,%d,%s" % [t.x, t.y, side])
			var w := InteriorWall.new()
			w.side = side
			w.kind = "door" if door else "inner"
			w.height = wh
			w.behind = str(rof[nb])
			w.front = room
			var style := str(styles.get(room, "timber"))
			# the wall seen from the room in front, cut from that room's painted wall (tools/art/fal_salas.py walls);
			# until it is painted, the library's
			w.texture = VisualPaths.interior_wall(type, level, room, side, "door" if door else "wall")
			if w.texture == null:
				var id := "wall_%s%s_%s%s" % [style, "_door" if door else "", side, "_b" if not door and (t.x + t.y) % 3 == 0 else ""]
				w.texture = VisualPaths.interior_prop(id)
			_place_wall(d, w, level, t, Vector2(0, -8))
			w.name = "wall_%d_%d_%s" % [t.x, t.y, side]
			out.append(w)
		for pair: Array in [["sw", Vector2i(t.x, t.y + 1)], ["se", Vector2i(t.x + 1, t.y)]]:
			if rof.has(pair[1]):
				continue
			var w := InteriorWall.new()
			w.side = str(pair[0])
			w.kind = "low"
			w.height = 12.0
			w.front = room
			var lside := "ne" if w.side == "sw" else "nw"
			w.texture = VisualPaths.interior_wall(type, level, room, lside, "low")
			if w.texture == null:
				w.texture = VisualPaths.interior_prop("wall_low_" + lside)
			_place_wall(d, w, level, t, Vector2(0, 16))
			w.name = "low_%d_%d_%s" % [t.x, t.y, w.side]
			out.append(w)
	return out


static func _place_wall(d: Dictionary, w: InteriorWall, level: int, t: Vector2i, sort: Vector2) -> void:
	w.level = level
	w.position = Iso.tile_to_world(t) + InteriorDefs.floor_offset(d, level) + sort
	w.tile_origin = -sort
	w.set_meta("level", level)
	w.z_index = level * LEVEL_Z


## The painted room (one image the size of the whole floor, transparent outside the room) or, until it exists, the
## library's fallback floor tiles and back walls.
static func _backdrop(parent: Node2D, type: String, d: Dictionary, room: Dictionary, rooms: Dictionary, wh: float) -> void:
	var level := int(room.get("floor", 0))
	var rid := str(room["id"])
	var size: Array = d.get("size", [6, 6])
	var W := int(size[0])
	var H := int(size[1])
	var holder := Node2D.new()
	holder.name = "%d_%s" % [level, rid]
	holder.position = InteriorDefs.floor_offset(d, level)
	holder.z_index = level * LEVEL_Z - (1 if level != 0 else 0)
	holder.set_meta("level", level)
	holder.set_meta("room", rid)
	parent.add_child(holder)
	var tex := VisualPaths.interior_backdrop(type, level, rid)
	if tex != null:
		var s := Sprite2D.new()
		s.name = "Painted"
		s.texture = tex
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = Vector2(-float(H) * 32.0, -16.0 - wh)
		holder.add_child(s)
		return
	var kind := str(room.get("floor_kind", "planks"))
	var tile_id: String = "floor_" + str({"stone": "flagstone", "rug": "planks"}.get(kind, kind))
	var ftex := VisualPaths.interior_prop(str(tile_id))
	var rof: Dictionary = rooms.get(level, {})
	var style := str(room.get("wall_style", "timber"))
	for t: Vector2i in rof:
		if str(rof[t]) != rid:
			continue
		var f := KitFloor.new()
		f.texture = ftex
		f.color = Color(0.45, 0.38, 0.3)
		f.position = Iso.tile_to_world(t) + Vector2(0, -float(InteriorDefs.step_of(d, level, t)) * InteriorDefs.STEP_PX)
		holder.add_child(f)
		for pair: Array in [["nw", Vector2i(t.x - 1, t.y)], ["ne", Vector2i(t.x, t.y - 1)]]:
			if rof.has(pair[1]):
				continue
			var w := KitWall.new()
			w.side = str(pair[0])
			w.height = wh
			var ent: Dictionary = d.get("entrance", {})
			var et: Array = ent.get("tile", [-1, -1])
			w.door = int(ent.get("floor", 0)) == level and Vector2i(int(et[0]), int(et[1])) == t and str(ent.get("side", "")) == w.side
			w.texture = VisualPaths.interior_prop("wall_%s%s_%s" % [style, "_door" if w.door else "", w.side])
			w.position = Iso.tile_to_world(t)
			holder.add_child(w)


## The light layer of a room: the room's tiles raised by the wall height, as one polygon (no double light at the
## seams), added (a glow) or multiplied (shade) over what is in the room.
static func _light(parent: Node2D, d: Dictionary, room: Dictionary, wh: float) -> void:
	var l := InteriorDefs.light(str(room.get("light", "")))
	if l.is_empty():
		return
	var level := int(room.get("floor", 0))
	var polys: Array[PackedVector2Array] = []
	for rc: Array in room.get("rects", []):
		var c0 := int(rc[0])
		var r0 := int(rc[1])
		var c1 := int(rc[2])
		var r1 := int(rc[3])
		var top := Iso.tile_to_world(Vector2i(c0, r0)) + Vector2(0, -16)
		var right := Iso.tile_to_world(Vector2i(c1, r0)) + Vector2(32, 0)
		var bottom := Iso.tile_to_world(Vector2i(c1, r1)) + Vector2(0, 16)
		var left := Iso.tile_to_world(Vector2i(c0, r1)) + Vector2(-32, 0)
		var up := Vector2(0, -wh)
		polys.append(PackedVector2Array([left + up, top + up, right + up, right, bottom, left]))
	var merged: Array[PackedVector2Array] = [polys[0]]
	for i: int in range(1, polys.size()):
		var m := Geometry2D.merge_polygons(merged[0], polys[i])
		if m.size() >= 1:
			merged = [m[0]]
	var mode := str(l.get("mode", "add"))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if mode == "add" else CanvasItemMaterial.BLEND_MODE_MUL
	var c := Color.html(str(l.get("color", "#ffffff")))
	var a := float(l.get("alpha", 0.1))
	var p := Polygon2D.new()
	p.name = "%d_%s" % [level, str(room["id"])]
	p.polygon = merged[0]
	p.position = InteriorDefs.floor_offset(d, level)
	p.material = mat
	# add: the colour scaled by its strength; mul: white darkened towards the colour by its strength
	p.color = Color(c.r * a, c.g * a, c.b * a, 1.0) if mode == "add" else Color.WHITE.lerp(c, a)
	p.z_index = level * LEVEL_Z + 5
	p.set_meta("level", level)
	p.set_meta("room", str(room["id"]))
	parent.add_child(p)
