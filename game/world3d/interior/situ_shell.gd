class_name SituShell
extends RefCounted
## What an interior in place asks of the house it lives in (docs/interior3d.md, «Interior en sitio»), for any building:
## the rules that were written inside pueblo.gd for the forge, by data and reusable.
##   var sd := SituShell.data_for("tavern_inn", 2)                 # data/interiors/<type>_sitio[_n<level>].json, {} if none
##   var why := SituShell.apply(def, sd, yard)                      # def = BuildingTypes.def_for(...) or pueblo's _style; "" = fits
##   var house := SituShell.build(def, sd)                          # HouseBuilder.build + edit + bake + door leaves + metas
##   var o := SituShell.open(house, town)                           # {view: interior3d (situ), cut: SituCut}, mounted, closed
## A town that builds its houses itself (pueblo.gd) calls apply() on the def, then, between HouseBuilder.build and
## HouseBuilder.bake, `var leaves := SituShell.edit(h, def, sd)`, and after the bake `SituShell.finish(h, def, sd, leaves)`.
##
## The data's "shell" says what the house must be (w, d, floors, door_cell) and may name modules the interior counts on
## (shop, sign, porch, chimneys) and wall cells (doorways, plain, floor_holes). What can be worked out is: the wall
## cells behind a tall or hung piece set against an outer wall and at the ends of a partition lose their window, the
## floor over a flight of stairs gets its hole, and a chimney stands on the roof over every hearth.

const INTERIORS := "res://data/view3d/interiors/%s.json"


static func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[SituShell] " + msg)


## The interior in place of a building type at a level: <type>_sitio_n<level>.json, else <type>_sitio.json when its
## "for_levels" lists that level (or it has no "for_levels"). `variant`: <type>_sitio_<variant>.json first. {} if there is none.
static func data_for(type: String, level := 0, variant := "") -> Dictionary:
	var names := []
	if variant != "":
		names.append("%s_sitio_%s" % [type, variant])
	if level > 0:
		names.append("%s_sitio_n%d" % [type, level])
	names.append("%s_sitio" % type)
	for nm: String in names:
		var path := INTERIORS % nm
		if not FileAccess.file_exists(path):
			continue
		var sd = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (sd is Dictionary) or not sd.has("shell"):
			push_warning("[SituShell] %s is not an interior in place" % path)
			continue
		if level > 0 and nm == "%s_sitio" % type and sd.has("for_levels") and not (sd.for_levels as Array).has(float(level)):
			continue
		sd["_path"] = path
		return sd
	for k in range(1, 4):  # a file written for one level that says it serves others too ("for_levels")
		var path := INTERIORS % ("%s_sitio_n%d" % [type, k])
		if level <= 0 or k == level or not FileAccess.file_exists(path):
			continue
		var sd = JSON.parse_string(FileAccess.get_file_as_string(path))
		if sd is Dictionary and sd.has("shell") and (sd.get("for_levels", []) as Array).has(float(level)):
			sd["_path"] = path
			return sd
	return {}


## every interior in place there is: [{type, level, path}] (a file without "for_levels" counts as level 0 = any)
static func all() -> Array:
	var out := []
	var dir := DirAccess.open("res://data/view3d/interiors")
	if dir == null:
		return out
	var files := Array(dir.get_files())
	files.sort()
	for fname: String in files:
		if not fname.ends_with(".json") or not fname.contains("_sitio"):
			continue
		var sd = JSON.parse_string(FileAccess.get_file_as_string("res://data/view3d/interiors/" + fname))
		if not (sd is Dictionary) or not sd.has("shell"):
			continue
		var type := fname.get_slice("_sitio", 0)
		var tail := fname.get_basename().get_slice("_sitio", 1)
		if tail.begins_with("_n") and tail.substr(2).is_valid_int():
			var lvs: Array = sd.get("for_levels", [int(tail.substr(2))])
			for lv in lvs:
				out.append({"type": type, "level": int(lv), "path": "res://data/view3d/interiors/" + fname})
		elif tail == "":
			for lv in sd.get("for_levels", [0]):
				out.append({"type": type, "level": int(lv), "path": "res://data/view3d/interiors/" + fname})
	return out


## why the house of `def` cannot hold the interior ("" = it can)
static func misfit(def: Dictionary, sh: Dictionary, yard := {}) -> String:
	var n: int = int(def.w) / 2
	if int(def.w) != int(sh.w) or int(def.d) != int(sh.d) or int(def.floors) != int(sh.floors):
		return "house %dx%d of %d floors, the interior is for %dx%d of %d" % [def.w, def.d, def.floors, sh.w, sh.d, sh.floors]
	if sh.has("door_cell") and HouseBuilder.door_cell(def, n) != int(sh.door_cell):
		return "door on cell %d, the interior has it on %d" % [HouseBuilder.door_cell(def, n), int(sh.door_cell)]
	for e: Dictionary in sh.get("porch", []):
		var cells: Array = yard.get(e.side, [])
		for i in range(int(e.from), int(e.to) + 1):
			if i >= cells.size() or not cells[i]:
				return "no yard for the shed on its %s wall" % e.side
	for side: String in sh.get("yard", []):  # the interior counts on what the type puts in the yard on that side (an oven, a shed)
		if not (yard.get(side, []) as Array).has(true):
			return "no yard on its %s side" % side
	return ""


static func _color(v) -> Variant:
	if v is String:
		var cols: Dictionary = BuildingTypes.data().get("colors", {})
		if cols.has((v as String).to_upper()):
			return Color(cols[(v as String).to_upper()])
		if (v as String).begins_with("#"):
			return Color(v)
	return v


## The house def as the interior needs it, when the house is of that size with the door there and yard for the shed.
## Returns "" (the def is ready: build it, edit it, bake it) or why not (the def is left as it was).
static func apply(def: Dictionary, sd: Dictionary, yard := {}) -> String:
	var sh: Dictionary = sd.shell
	var why := misfit(def, sh, yard)
	if why != "":
		# the same interior reflected (the yard on the other side, the door on the mirrored cell) may be the one that fits
		var m := mirrored(sd)
		var why_m := misfit(def, m.shell, yard)
		if why_m != "":
			dbg("interior in place: not here (%s; mirrored: %s)" % [why, why_m])
			return why
		sd.clear()
		sd.merge(m)
		sh = sd.shell
		# the shop front the type puts on the house goes with the interior: its counter is now on the mirrored cell
		if not sh.has("shop") and def.has("shop") and (def.shop as Dictionary).has("cells"):
			var n: int = int(def.w) / 2
			def.shop = (def.shop as Dictionary).duplicate()
			def.shop.cells = (def.shop.cells as Array).map(func(i): return n - 1 - int(i))
		dbg("interior in place: mounted mirrored (as written: %s)" % why)
	if sh.has("shop"):
		var shop: Dictionary = (sh.shop as Dictionary).duplicate()
		if shop.has("awning"):
			shop.awning = _color(shop.awning)
		shop.cells = (shop.get("cells", [0]) as Array).map(func(i): return int(i))  # JSON numbers are floats
		def.shop = shop
	for k in ["sign", "porch", "chimneys"]:
		if sh.has(k):
			def[k] = sh[k]
	if not sh.has("chimneys"):
		var over := hearths(sd)
		if not over.is_empty():
			var ch := []
			for p: Vector2 in over:
				ch.append(chimney_over(def, p.x, p.y))
			def.chimneys = ch
	def["_situ"] = true
	return ""


## a chimney entry of the def that stands over the house-local point (x, z) (Godot axes: the front is +z)
static func chimney_over(def: Dictionary, x: float, z: float, piece := "Prop_Chimney") -> Dictionary:
	var w := float(def.w)
	var d := float(def.d)
	if def.get("ridge", "y") == "x":  # the roof turned a quarter: span = d, run = w
		return {"x": -z / (d / 2.0), "y": -x / (w / 2.0), "piece": piece}
	return {"x": x / (w / 2.0), "y": -z / (d / 2.0), "piece": piece}


static func _props(sd: Dictionary) -> Array:
	## the pieces of the interior with their place worked out (pos, rot, wall), stations included
	var out := []
	for p in sd.get("props", []):
		out.append((p as Dictionary).duplicate())
	for z in sd.get("stations", {}):
		var s: Dictionary = sd.stations[z]
		if s.has("prop"):
			var e := {"id": s.prop, "floor": s.floor, "tile": s.tile}
			for k in ["pos", "rot", "snap", "gap"]:
				if s.has(k):
					e[k] = s[k]
			out.append(e)
	for p: Dictionary in out:
		Interior3DBuilder.resolve_prop(p, sd)
	return out


static func _local(sd: Dictionary, pos: Array) -> Vector2:
	var om: Array = sd.get("origin_m", [0, 0])
	var tm := float(sd.get("tile_m", 1.0))
	return Vector2(float(om[0]) + (float(pos[0]) + 0.5) * tm, float(om[1]) + (float(pos[1]) + 0.5) * tm)


## where the hearths of the interior stand (house-local x, z), one per flue
static func hearths(sd: Dictionary) -> Array:
	var out := []
	for p: Dictionary in _props(sd):
		if not String(p.id).begins_with("hogar") or not p.has("pos"):
			continue
		var at := _local(sd, p.pos)
		# the flue is at the back of the hearth
		var rc := Interior3DBuilder.turned_box(String(p.id), float(p.get("rot", 0.0)))
		var back := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(float(p.get("rot", 0.0))))
		at += Vector2(back.x, back.z) * (minf(rc.size.x, rc.size.y) / 2.0 - 0.21)
		var dup := false
		for q: Vector2 in out:
			if q.distance_to(at) < 0.7:
				dup = true
		if not dup:
			out.append(at)
	return out


static func _cells_along(w: int, d: int, side: String, lo: float, hi: float, min_overlap := 0.25) -> Array:
	## the cells of that wall a stretch covers; lo..hi along the wall in house-local Godot axes (x for front and back, z
	## for the sides)
	var out := []
	var cells := HouseBuilder._wall_cells(w, d, side)
	for i in cells.size():
		var c: Vector2 = cells[i]
		var mid := c.x if side in ["front", "back"] else -c.y
		if minf(hi, mid + 1.0) - maxf(lo, mid - 1.0) > min_overlap:
			out.append(i)
	return out


## What the interior asks of the walls and floors of its house: {plain: [{side, floor, cell}], doorways: [...],
## floor_holes: [{floor, rect_m: [x0, z0, x1, z1]}]}: what the data's shell lists plus what follows from the pieces.
static func asks(sd: Dictionary) -> Dictionary:
	var sh: Dictionary = sd.shell
	var w := int(sh.w)
	var d := int(sh.d)
	var plain := {}
	var add := func(side: String, f: int, cell: int) -> void:
		plain["%s|%d|%d" % [side, f, cell]] = {"side": side, "floor": f, "cell": cell}
	for e: Dictionary in sh.get("plain", []):
		add.call(String(e.side), int(e.floor), int(e.cell))
	var mb := Interior3DBuilder.muebles()
	# tall and hung pieces set against an outer wall: no window behind them
	for p: Dictionary in _props(sd):
		var info: Dictionary = mb.get(String(p.id), {})
		if not p.has("wall") or not (info.get("tall", false) or info.get("hang", false) or p.get("plain", false)):
			continue
		var at := _local(sd, p.pos)
		var rc := Interior3DBuilder.turned_box(String(p.id), float(p.get("rot", 0.0)))
		var side := String(p.wall)
		var lo := at.x + rc.position.x if side in ["front", "back"] else at.y + rc.position.y
		var hi := at.x + rc.end.x if side in ["front", "back"] else at.y + rc.end.y
		for i in _cells_along(w, d, side, lo, hi):
			add.call(side, int(p.floor), i)
	# the ends of the partitions
	var om: Array = sd.get("origin_m", [0, 0])
	var room_at := {}
	var rooms := {}
	for room: Dictionary in sd.rooms:
		rooms[room.id] = room
		for rc in room.rects:
			for r in range(int(rc[1]), int(rc[3]) + 1):
				for c in range(int(rc[0]), int(rc[2]) + 1):
					room_at["%d|%d|%d" % [room.floor, c, r]] = room.id
	var open := {}
	for pair in sd.get("open", []):
		open["%s|%s" % [pair[0], pair[1]]] = true
		open["%s|%s" % [pair[1], pair[0]]] = true
	for key: String in room_at:
		var f := int(key.get_slice("|", 0))
		var c := int(key.get_slice("|", 1))
		var r := int(key.get_slice("|", 2))
		var room: String = room_at[key]
		var x := float(om[0]) + c + 0.5
		var z := float(om[1]) + r + 0.5
		for e in [[c - 1, r, true], [c, r - 1, false]]:
			var other: String = room_at.get("%d|%d|%d" % [f, e[0], e[1]], "")
			if other == "" or other == room or open.has("%s|%s" % [room, other]) or rooms[room].get("annex", false) or rooms[other].get("annex", false):
				continue
			if e[2]:  # a partition along z on the line x - 0.5: it ends on the back and front walls
				if z < -d / 2.0 + 1.01:
					for i in _cells_along(w, d, "back", x - 0.7, x - 0.3, 0.1):
						add.call("back", f, i)
				if z > d / 2.0 - 1.01:
					for i in _cells_along(w, d, "front", x - 0.7, x - 0.3, 0.1):
						add.call("front", f, i)
			else:
				if x < -w / 2.0 + 1.01:
					for i in _cells_along(w, d, "left", z - 0.7, z - 0.3, 0.1):
						add.call("left", f, i)
				if x > w / 2.0 - 1.01:
					for i in _cells_along(w, d, "right", z - 0.7, z - 0.3, 0.1):
						add.call("right", f, i)
	# stairs: the wall they climb along loses its windows on the floor they leave; the floor they reach gets its hole
	var holes: Array = (sh.get("floor_holes", []) as Array).duplicate()
	var listed := {}
	for e: Dictionary in holes:
		listed[int(e.floor)] = true
	for s: Dictionary in sd.get("stairs", []):
		if not s.has("foot"):
			continue
		var a := _local(sd, s.foot)
		var b := _local(sd, s.top)
		var hw := float(s.get("width", 1.0)) / 2.0
		var along_z := absf(b.y - a.y) > absf(b.x - a.x)
		var lo := Vector2(minf(a.x, b.x) - (hw if along_z else 0.0), minf(a.y, b.y) - (0.0 if along_z else hw))
		var hi := Vector2(maxf(a.x, b.x) + (hw if along_z else 0.0), maxf(a.y, b.y) + (0.0 if along_z else hw))
		var f := int(s.floor)
		if along_z:
			if hi.x > w / 2.0 - 0.6:
				for i in _cells_along(w, d, "right", lo.y, hi.y, 0.4):
					add.call("right", f, i)
			if lo.x < -w / 2.0 + 0.6:
				for i in _cells_along(w, d, "left", lo.y, hi.y, 0.4):
					add.call("left", f, i)
		else:
			if hi.y > d / 2.0 - 0.6:
				for i in _cells_along(w, d, "front", lo.x, hi.x, 0.4):
					add.call("front", f, i)
			if lo.y < -d / 2.0 + 0.6:
				for i in _cells_along(w, d, "back", lo.x, hi.x, 0.4):
					add.call("back", f, i)
		if listed.has(int(s.to_floor)):
			continue
		# the hole: the width of the flight, from where a head would meet the floor above (a third of the way up) to
		# its top; out to the wall when the wall is that near
		var from := a.lerp(b, 0.3)
		var h0 := Vector2(minf(from.x, b.x), minf(from.y, b.y)) - (Vector2(hw + 0.06, 0.15) if along_z else Vector2(0.15, hw + 0.06))
		var h1 := Vector2(maxf(from.x, b.x), maxf(from.y, b.y)) + (Vector2(hw + 0.06, 0.15) if along_z else Vector2(0.15, hw + 0.06))
		if h0.x < -w / 2.0 + 0.75:
			h0.x = -w / 2.0
		if h1.x > w / 2.0 - 0.75:
			h1.x = w / 2.0
		if h0.y < -d / 2.0 + 0.75:
			h0.y = -d / 2.0
		if h1.y > d / 2.0 - 0.75:
			h1.y = d / 2.0
		holes.append({"floor": int(s.to_floor), "rect_m": [h0.x, h0.y, h1.x, h1.y]})
	return {"plain": plain.values(), "doorways": sh.get("doorways", []), "floor_holes": holes}


static func _wall_node(level: Node3D, w: int, d: int, side: String, cell: int) -> Node3D:
	## the wall holder (HouseBuilder.build: one per cell) of that cell of a level
	var cells := HouseBuilder._wall_cells(w, d, side)
	if cell < 0 or cell >= cells.size():
		return null
	var c: Vector2 = cells[cell]
	for wn in level.get_children():
		if not wn.is_in_group("wall") or wn.get_meta("outward") != HouseBuilder.OUTWARD[side] or wn.get_child_count() == 0:
			continue
		var p: Vector3 = (wn.get_child(0) as Node3D).position
		if absf(p.x - c.x) < 0.05 and absf(p.z + c.y) < 0.05:
			return wn
	return null


static func _piece_name(n: Node) -> String:
	## the kit piece a node was instanced from (node names are renumbered among siblings, the scene file is not)
	return String(n.scene_file_path).get_file().get_basename()


static func _rewall(level: Node3D, def: Dictionary, side: String, cell: int, kind: String) -> bool:
	## that wall cell becomes a plain wall ("Straight") or an open doorway ("Door_Flat"); what else hangs on it stays.
	## A cell with a door, a portal or a shop front is left alone.
	var w := int(def.w)
	var d := int(def.d)
	var f := int(level.get_meta("level"))
	var wn := _wall_node(level, w, d, side, cell)
	if wn == null:
		return false
	var has_window := false
	for ch in wn.get_children():
		var nm := _piece_name(ch)
		if nm.contains("_Door") or nm.contains("Portal") or nm.begins_with("Door") or nm.contains("Shop") or nm.contains("Counter") or nm.contains("Display"):
			if kind == "Straight":
				return false
		if nm.begins_with("Window") or nm.contains("_Window"):
			has_window = true
	if kind == "Straight" and not has_window:
		return false  # already a wall without a window (whatever its make: boards, a barn door, the grid)
	for ch in wn.get_children():
		var nm := _piece_name(ch)
		if nm.begins_with("Wall_") or nm.begins_with("Window") or nm.begins_with("Door_") or nm.begins_with("Shutter") or nm.begins_with("Grille") or nm.contains("Grille"):
			wn.remove_child(ch)
			ch.free()
	var mat: String = def.walls[mini(f, def.walls.size() - 1)]
	var wname := "Wall_%s_%s" % [mat, kind]
	if f > 0 and kind == "Straight" and mat == "Plaster" and def.get("grid", false):
		wname = "Wall_Plaster_WoodGrid"
	if not HouseBuilder._exists(wname):
		wname = "Wall_Plaster_%s" % kind
	var c: Vector2 = HouseBuilder._wall_cells(w, d, side)[cell]
	var piece := HouseBuilder._piece(wname, wn, Vector3(c.x, c.y, 3.0 * f), HouseBuilder.SIDES[side])
	if piece:
		wn.move_child(piece, 0)
	return true


## Before the bake: what the interior asks of the walls and floors of its house. The corner posts become wall pieces
## of their own (a post between two lowered walls goes down with them) and the leaves of the front door are taken
## out: returned, to be added again after the bake (finish()).
static func edit(h: Node3D, def: Dictionary, sd: Dictionary) -> Array:
	var w := int(def.w)
	var d := int(def.d)
	var want := asks(sd)
	var leaves := []
	var done := [0, 0, 0]
	HouseBuilder._palette = def.get("palette", {})
	for level in h.get_children():
		if not level.has_meta("level"):
			continue
		var f := int(level.get_meta("level"))
		for ch in level.get_children():
			if ch.is_in_group("wall") or not ch is Node3D:
				continue
			var p: Vector3 = ch.position
			if absf(absf(p.x) - w / 2.0) < 0.05 and absf(absf(p.z) - d / 2.0) < 0.05:
				var post := Node3D.new()
				post.add_to_group("wall")
				post.set_meta("outward", Vector2(signf(p.x), signf(-p.z)))
				level.add_child(post)
				level.remove_child(ch)
				post.add_child(ch)
		for e: Dictionary in want.plain:
			if int(e.floor) == f and _rewall(level, def, e.side, int(e.cell), "Straight"):
				done[0] += 1
		for e: Dictionary in want.doorways:
			if int(e.floor) == f and _rewall(level, def, e.side, int(e.cell), "Door_Flat"):
				done[1] += 1
		for e: Dictionary in want.floor_holes:
			if int(e.floor) != f:
				continue
			done[2] += 1
			var hole := Rect2(float(e.rect_m[0]), float(e.rect_m[1]), float(e.rect_m[2]) - float(e.rect_m[0]), float(e.rect_m[3]) - float(e.rect_m[1]))
			var floor_piece: String = def.floors_mat[mini(f, def.floors_mat.size() - 1)]
			for ch in level.get_children():
				if ch.is_in_group("wall") or not _piece_name(ch).begins_with("Floor"):
					continue
				var cell := Rect2(ch.position.x - 1.0, ch.position.z - 1.0, 2.0, 2.0)
				if not cell.intersects(hole):
					continue
				level.remove_child(ch)
				ch.free()
				# what is left of that 2 x 2 m of floor round the hole, in up to four boards of the same piece
				var x0 := maxf(cell.position.x, hole.position.x)
				var x1 := minf(cell.end.x, hole.end.x)
				for rc: Rect2 in [Rect2(cell.position.x, cell.position.y, hole.position.x - cell.position.x, 2.0),
						Rect2(hole.end.x, cell.position.y, cell.end.x - hole.end.x, 2.0),
						Rect2(x0, cell.position.y, x1 - x0, hole.position.y - cell.position.y),
						Rect2(x0, hole.end.y, x1 - x0, cell.end.y - hole.end.y)]:
					if rc.size.x < 0.05 or rc.size.y < 0.05:
						continue
					var mid := rc.get_center()
					var n := HouseBuilder._piece(floor_piece, level, Vector3(mid.x, -mid.y, 3.0 * f))
					if n:
						n.scale = Vector3(rc.size.x / 2.0, 1.0, rc.size.y / 2.0)
		if f == 0:
			var side: String = def.get("door_side", "front")
			var wn := _wall_node(level, w, d, side, HouseBuilder.door_cell(def, HouseBuilder._wall_cells(w, d, side).size()))
			if wn:
				for ch in wn.get_children():
					var nm := _piece_name(ch)
					var leaf := nm.begins_with("Door_") and nm.length() > 5 and nm.substr(5, 1).is_valid_int()
					var portal := nm.begins_with("Door_Portal")
					if leaf or portal:
						wn.remove_child(ch)
						ch.set_meta("door_leaf", true)
						ch.set_meta("outward", HouseBuilder.OUTWARD[side])
						ch.set_meta("leaf_level", 0)
						if portal:
							ch.set_meta("leaf_hide", true)  # the two leaves of a portal: gone while the house is open
						leaves.append(ch)
	HouseBuilder._palette = {}
	dbg("shell of %s edited: %d of %d cells made plain, %d doorways, %d floor holes, %d door leaves kept apart" % [
		def.get("name", h.name), done[0], want.plain.size(), done[1], done[2], leaves.size()])
	return leaves


## After the bake: the door leaves back as pieces of their own (SituCut opens them) and what the house knows of its inside
static func finish(h: Node3D, def: Dictionary, sd: Dictionary, leaves: Array) -> void:
	for leaf: Node3D in leaves:
		h.add_child(leaf)
	h.set_meta("interior", String(sd.get("_path", "")))
	h.set_meta("interior_mirror", bool(sd.get("_mirror", false)))
	h.set_meta("wd", Vector2(int(def.w), int(def.d)))
	if def.has("shop") or def.has("display"):
		# the wall of the shop window goes down with the cut whatever the camera: who buys from the street stays in sight
		h.set_meta("situ_low", [HouseBuilder.OUTWARD.front])


## A house with its interior in place, baked and ready to be opened: for a scene that places its houses itself
static func build(def: Dictionary, sd: Dictionary) -> Node3D:
	var h := HouseBuilder.build(def)
	var leaves := edit(h, def, sd)
	HouseBuilder.bake(h)
	finish(h, def, sd, leaves)
	return h


## Mounts the interior of a house built for it (meta "interior") and the cut that opens it. `town` has what
## interior3d.gd and SituCut read of the town: cam, yaw, style and _variant(material, style). opts: live (people from
## the sim, live_sync) or the data's cast; keep_visible; upgrades (the ids of the building's finished upgrades, as the
## trace of the sim brings them: only those are shown). Returns {view, cut, ms}; the house stays closed (cut.set_on(true),
## view.activate(true) open it).
static func open(house: Node3D, town: Node, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var view: Node3D = (load("res://game/world3d/interior/interior3d.gd") as Script).new()
	view.embedded = true
	view.situ = true
	view.town = town
	view.live = bool(opts.get("live", false))
	view.data_path = String(house.get_meta("interior"))
	view.data_opts = {"mirror": bool(house.get_meta("interior_mirror", false)), "upgrades": opts.get("upgrades", null)}
	view.keep_visible = bool(opts.get("keep_visible", false))
	view.set_meta("situ_view", true)
	house.add_child(view)
	view.setup()
	var cut := SituCut.new()
	house.add_child(cut)
	cut.setup(town, house)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	dbg("interior in place of %s mounted in %.0f ms" % [house.name, ms])
	return {"view": view, "cut": cut, "ms": ms}


# ------------------------------------------------------------------ mirrored interiors
static func _swap_side(side: String) -> String:
	return {"left": "right", "right": "left"}.get(side, side)


static func _swap_snap(snap: String) -> String:
	var out := []
	for t in snap.split(",", false):
		out.append(_swap_side(t.strip_edges()))
	return ",".join(out)


static func _mirror_piece(p: Dictionary, id: String, W: int, tm: float) -> void:
	## a piece (prop, station, upgrade entry) reflected: its place, its turn and the wall it stands against. A piece of
	## the catalogue is not itself reflected: its box is kept where the mirror image of the old one falls.
	if p.has("snap"):
		p.snap = _swap_snap(String(p.snap))
	if not p.has("pos") and not p.has("tile"):
		if p.has("rot"):
			p.rot = -float(p.rot)
		return
	var had_tile: bool = not p.has("pos")
	var at := Vector2(float(p.pos[0]), float(p.pos[1])) if p.has("pos") else Vector2(float(p.tile[0]), float(p.tile[1]))
	var old_snap := _swap_snap(String(p.get("snap", "")))  # the snap before the swap above
	var rot0 := float(p.rot) if p.has("rot") else float(Interior3DBuilder.SNAP_ROT.get(old_snap.get_slice(",", 0), 0.0))
	var rot1 := -rot0
	if p.has("rot"):
		p.rot = rot1
	else:
		rot1 = float(Interior3DBuilder.SNAP_ROT.get(String(p.get("snap", "")).get_slice(",", 0), 0.0))
	var b0 := Vector2.ZERO
	var b1 := Vector2.ZERO
	if Interior3DBuilder.muebles().has(id):
		b0 = Interior3DBuilder.turned_box(id, rot0).get_center() / tm
		b1 = Interior3DBuilder.turned_box(id, rot1).get_center() / tm
	else:
		# a piece of the kits (the furnace, a pile of crates): its box is not in the catalogue, so it is drawn reflected
		p["flip_x"] = not bool(p.get("flip_x", false))
	var c := Vector2(W - 1 - (at.x + b0.x), at.y + b0.y) - b1
	if had_tile and absf(c.x - roundf(c.x)) < 0.02 and absf(c.y - roundf(c.y)) < 0.02:
		p.tile = [int(roundf(c.x)), int(roundf(c.y))]
	else:
		if not p.has("stand"):  # a station keeps its tile: it is the tile of its zone
			p.erase("tile")
		p["pos"] = [snappedf(c.x, 0.001), snappedf(c.y, 0.001)]


static func _mt(t: Array, W: int) -> Array:
	return [W - 1 - t[0], t[1]]


## The interior reflected left to right (x -> -x), for a house whose yard, shed or door falls on the other side: every
## tile, piece, wall cell, stair, door, zone and step of the cast. "_mirror" says which of the two it is.
static func mirrored(sd: Dictionary) -> Dictionary:
	var m: Dictionary = sd.duplicate(true)
	var W := int(sd.size[0])
	var tm := float(sd.get("tile_m", 1.0))
	var om: Array = sd.get("origin_m", [0, 0])
	m["origin_m"] = [-(float(om[0]) + W * tm), om[1]]
	m["_mirror"] = not bool(sd.get("_mirror", false))
	var sh: Dictionary = m.shell
	var cells := {"front": int(sh.w) / 2, "back": int(sh.w) / 2, "left": int(sh.d) / 2, "right": int(sh.d) / 2}
	if sh.has("door_cell"):
		sh.door_cell = cells.front - 1 - int(sh.door_cell)
	if sh.has("shop") and (sh.shop as Dictionary).has("cells"):
		sh.shop.cells = (sh.shop.cells as Array).map(func(i): return cells.front - 1 - int(i))
	for key in ["plain", "doorways"]:
		for e: Dictionary in sh.get(key, []):
			e.cell = cells[String(e.side)] - 1 - int(e.cell)
			e.side = _swap_side(String(e.side))
	for e: Dictionary in sh.get("porch", []):
		var n: int = cells[String(e.side)]
		var from := int(e.from)
		e.from = n - 1 - int(e.to)
		e.to = n - 1 - from
		e.side = _swap_side(String(e.side))
	if sh.has("chimneys"):
		var ch := []
		for c in sh.chimneys:
			if c is Dictionary:
				var e2: Dictionary = (c as Dictionary).duplicate()
				e2.x = -float(e2.get("x", 0.5))
				ch.append(e2)
			else:
				ch.append(-float(c))
		sh.chimneys = ch
	for e: Dictionary in sh.get("floor_holes", []):
		e.rect_m = [-float(e.rect_m[2]), e.rect_m[1], -float(e.rect_m[0]), e.rect_m[3]]
	if sh.has("yard"):
		sh.yard = (sh.yard as Array).map(func(sd_): return _swap_side(String(sd_)))
	if m.has("entrance"):
		m.entrance.tile = _mt(m.entrance.tile, W)
		m.entrance.side = {"nw": "se", "se": "nw"}.get(String(m.entrance.side), String(m.entrance.side))
	for room: Dictionary in m.get("rooms", []):
		var rects := []
		for rc in room.rects:
			rects.append([W - 1 - rc[2], rc[1], W - 1 - rc[0], rc[3]])
		room.rects = rects
	for dr: Dictionary in m.get("doors", []):
		# a door on the nw edge of a tile (between it and the one to its left) is, reflected, on the nw edge of the tile after
		dr.tile = [W - dr.tile[0], dr.tile[1]] if String(dr.side) == "nw" else _mt(dr.tile, W)
	for s: Dictionary in m.get("stairs", []):
		for k in ["from", "to", "foot", "top", "tile"]:
			if s.has(k):
				s[k] = _mt(s[k], W)
		if s.has("tiles"):
			s.tiles = (s.tiles as Array).map(func(t): return _mt(t, W))
		if s.has("foot"):
			s["mirror"] = not bool(s.get("mirror", false))
	for z in m.get("stations", {}):
		var st: Dictionary = m.stations[z]
		var zone_tile := _mt(st.tile, W)
		if st.has("pos") or st.has("snap") or st.has("rot"):
			_mirror_piece(st, String(st.get("prop", Interior3DBuilder.STATION_PIECE.get(z, ""))), W, tm)
		st.tile = zone_tile
		if st.has("stand"):
			st.stand = _mt(st.stand, W)
	var cu: Dictionary = m.get("customers", {})
	for k in ["counter", "queue"]:
		for e: Dictionary in cu.get(k, []):
			e.tile = _mt(e.tile, W)
	if cu.has("street"):
		cu.street = (cu.street as Array).map(func(q): return _mt(q, W))
	var sp: Dictionary = m.get("spots", {})
	for k in sp:
		var v: Array = sp[k]
		sp[k] = [v[0], _mt(v[1], W)] if v[1] is Array else _mt(v, W)
	for e: Dictionary in m.get("idle", []):
		e.tile = _mt(e.tile, W)
	for p: Dictionary in m.get("props", []):
		_mirror_piece(p, String(p.id), W, tm)
	var ups: Dictionary = m.get("upgrades", {})
	for node in ups:
		if not ups[node] is Array:
			continue
		for p in ups[node]:
			if not p is Dictionary:
				continue
			if p.has("stand"):
				p.stand = _mt(p.stand, W)
			if p.has("id") or p.has("prop"):
				_mirror_piece(p, String(p.get("id", p.get("prop", ""))), W, tm)
			if p.has("near") and p.near is Array:
				p.near = _mt(p.near, W)
	for c: Dictionary in m.get("cast", []):
		if c.has("start"):
			c.start = [c.start[0], _mt(c.start[1], W)]
		for stp: Dictionary in c.get("steps", []):
			if stp.has("tile"):
				stp.tile = [stp.tile[0], _mt(stp.tile[1], W)]
			if stp.has("look"):
				stp.look = _mt(stp.look, W)
			if stp.has("off"):
				stp.off = [-float(stp.off[0]), stp.off[1]]
			if stp.has("face"):
				stp.face = -float(stp.face)
	return m

