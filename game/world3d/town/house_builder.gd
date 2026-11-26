class_name HouseBuilder
extends RefCounted
## Assembles a house from Medieval Village MegaKit pieces by rules.
## Plan coordinates: x to the right, y toward the back (front facade at -y), z up.
## Grid: walls 2 m wide, 3 m per floor, exterior face toward the outside of the footprint.

const KIT := "res://kit/village/%s.gltf"
const MODULES := "res://kit/modules/%s.gltf"  # our own modules, same grid and pivots (tools/make_modules.py, docs/construccion.md)
const SIDES := {"front": 0.0, "right": 90.0, "back": 180.0, "left": 270.0}
const OUTWARD := {"front": Vector2(0, -1), "right": Vector2(1, 0), "back": Vector2(0, 1), "left": Vector2(-1, 0)}

static var _scenes := {}
static var _palette := {}  # slot -> variant texture name ("" keeps the kit colour)
static var _mat_cache := {}  # "variant|material id" -> Material
const SLOTS := {"T_RoundTiles_BaseColor": "roof", "T_Plaster_BaseColor": "plaster",
	"T_WoodTrim_BaseColor": "wood", "T_UnevenBrick_BaseColor": "stone"}


static func _apply_palette(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var m := n.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null or m.albedo_texture == null:
				continue
			var src := m.albedo_texture.resource_path.get_file().get_basename()
			var variant: String = _palette.get(SLOTS.get(src, ""), "")
			if variant == "":
				continue
			var key := "%s|%d" % [variant, m.get_instance_id()]
			if not _mat_cache.has(key):
				var v: StandardMaterial3D = m.duplicate()
				v.albedo_texture = load("res://kit/variants/%s.png" % variant)
				_mat_cache[key] = v
			n.set_surface_override_material(i, _mat_cache[key])
	for c in n.get_children():
		_apply_palette(c)


static func plan_to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


static var _prop_mats := {}


## Props (names starting with "@") come from res://kit/props and get kit textures by material name.
static func _prop_material(src: Material) -> Material:
	var nm: String = src.resource_name if src else ""
	if _prop_mats.has(nm):
		return _prop_mats[nm]
	var m: Material = src
	const COLS := {"hay": Color(0.93, 0.78, 0.4), "soil": Color(0.42, 0.29, 0.18), "plant": Color(0.32, 0.58, 0.2),
		"cabbage": Color(0.52, 0.74, 0.32), "herb": Color(0.5, 0.6, 0.3), "coal": Color(0.12, 0.11, 0.11),
		"water": Color(0.32, 0.52, 0.62), "rope": Color(0.8, 0.7, 0.5), "sack": Color(0.86, 0.76, 0.58),
		"metal": Color(0.24, 0.24, 0.27), "sign": Color(0.62, 0.4, 0.22), "flower": Color(0.92, 0.5, 0.72),
		"cloth_red": Color(0.78, 0.2, 0.16), "cloth_blue": Color(0.22, 0.36, 0.68), "cloth_yellow": Color(0.92, 0.76, 0.24),
		"cloth_green": Color(0.24, 0.5, 0.28), "cloth_white": Color(0.94, 0.92, 0.86), "coal_glow": Color(1.0, 0.5, 0.1)}
	if COLS.has(nm):
		var cm := StandardMaterial3D.new()
		cm.albedo_color = COLS[nm]
		cm.roughness = 0.15 if nm == "water" else 0.85
		if nm == "metal":
			cm.metallic = 0.5
			cm.roughness = 0.45
		if nm == "coal_glow":
			cm.emission_enabled = true
			cm.emission = COLS[nm]
			cm.emission_energy_multiplier = 3.0
		m = cm
	elif nm.begins_with("wood") or nm == "stone":
		var sm := StandardMaterial3D.new()
		var tex := "T_UnevenBrick_BaseColor" if nm == "stone" else "T_WoodTrim_BaseColor"
		sm.albedo_texture = load("res://kit/village/%s.png" % tex)
		sm.uv1_triplanar = true
		sm.uv1_scale = Vector3.ONE * (0.6 if nm == "stone" else 1.4)
		sm.albedo_color = Color(0.62, 0.55, 0.5) if nm == "wood_dark" else Color.WHITE
		sm.roughness = 0.9
		m = sm
	_prop_mats[nm] = m
	return m


static func skin_prop(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			n.set_surface_override_material(i, _prop_material(n.mesh.surface_get_material(i)))
	for c in n.get_children():
		skin_prop(c)


static func _piece(name: String, parent: Node3D, p: Vector3, rot_deg := 0.0, group := "") -> Node3D:
	if not _scenes.has(name):
		_scenes[name] = load("res://kit/props/%s.glb" % name.substr(1)) if name.begins_with("@") else load(piece_path(name))
	var scene: PackedScene = _scenes[name]
	if scene == null:
		push_warning("[HouseBuilder] missing piece %s" % name)
		return null
	var n: Node3D = scene.instantiate()
	if name.begins_with("@"):
		skin_prop(n)
	if not _palette.is_empty():
		_apply_palette(n)
	n.position = plan_to_godot(p)
	n.rotation.y = deg_to_rad(rot_deg)
	if group != "":
		n.add_to_group(group)
	parent.add_child(n)
	return n


static func _wall_cells(w: int, d: int, side: String) -> Array:
	var out := []
	if side == "front" or side == "back":
		var y := -d / 2.0 if side == "front" else d / 2.0
		for i in w / 2:
			out.append(Vector2(-w / 2.0 + 1 + 2 * i, y))
		if side == "back":
			out.reverse()
	else:
		var x := w / 2.0 if side == "right" else -w / 2.0
		for i in d / 2:
			out.append(Vector2(x, -d / 2.0 + 1 + 2 * i))
		if side == "left":
			out.reverse()
	return out


## A piece by name: the kit's (kit/village) or, if the kit has none, ours (kit/modules).
static func piece_path(name: String) -> String:
	if ResourceLoader.exists(KIT % name):
		return KIT % name
	return MODULES % name


static func _exists(name: String) -> bool:
	return ResourceLoader.exists(piece_path(name))


## def keys: w, d, floors, walls[], floors_mat[], corner, window, shutters, grid,
## side_windows, round_door, chimneys[], props[[name, Vector3, rot]], interior[[...]], seed
## Keys for our own modules (kit/modules, docs/construccion.md); none of them changes a def that does not use them:
##   ridge "y" | "x"                 the ridge runs front to back (gables on front and back, as always) or side to side
##   plinth "UnevenBrick" | "Brick"  stone plinth over the foot of the ground floor walls
##   shop {side, cells[], awning, sign}   shop windows with fold-down counter (awning: false, true or a Color)
##   sign "Forge" | "Blank" | ...    hanging sign beside the door (sign_scale: a bigger board, 1.0 by default)
##   porch [{side, from, to, posts "wood" | "stone", ends "open" | "boards"}]   lean-to roof on posts along a wall
##   balcony [{side, floor, from, to, rail "Cross" | "Simple", door}]            wooden balcony with its door
##   chimneys [0.5, {x, y, piece}]   a number is the kit chimney as before; a dictionary names the piece
##   dovecote <-1..1 along the ridge>, oven {side, cell}, tower {corner, floors, proud}, portal true, shield true | Color
##   window "Window_Twin"            the twin window with its mullion, as any other window kind
##   door_cell <index>               the cell of the door on its side (left to right from outside); default: the middle
##   banner {emblem, color, side}    the guild's banner on a hoist beam through a gable (emblem: "Forge"... or "Blank";
##                                   color: a Color or none for plain canvas; side: which gable, default the door's or,
##                                   with the ridge along the front, the right one)
## Keys for the trades and the building site (docs/construccion.md, data/building_types.json):
##   walls ["Boards"]                barn walls of upright boards; barn {side, cell} (cart doorway), loft {side, floor, cell}
##   door_leaf "Door_8"              the kit door leaf (Door_1, Door_2, Door_4, Door_8: the iron-bound one)
##   windows [per storey]            window kind of every storey (instead of one `window` for all)
##   shutters "closed"               every window shuttered
##   grille true | {floors[]}        iron grilles over the round wide windows (ground floor by default)
##   portal_door "Door_Portal_Iron"  the leaves of the portal;  shield_flank true: a window on each side of the shield
##   lantern true                    hanging lantern on the other side of the door from the sign
##   herbs [cells]                   herbalist's wall on the door side: a planter under windows, drying herbs on plain wall
##   hatch {side, cell}              cellar hatch against that cell
##   display {cells[], awning}       tailor's display windows on the door side; cloth [{side, floor, cell}] cloth hung to dry
##   porch [{..., stalls true}]      stable stalls under the lean-to;  balcony [{..., roof true}]  covered gallery
##   court {side, depth, gate}       walled court on one side (fence of Prop_StoneWall_Single with the stone gate)
##   annex [{at Vector2, rot, ...def}]   more buildings of the same lot (barn, shed), each a def of its own
##   yard [{piece, side, cell, out, rot}]   things standing by a wall: `out` metres from it, in front of that cell
##   stage "stakes" | "foundation" | "frame"   the building site instead of the house (stage_floor: storeys already
##                                   built under the one in progress; scaffold [sides])
static func build(def: Dictionary) -> Node3D:
	if def.get("stage", "") != "":
		return _site(def)
	var rng := RandomNumberGenerator.new()
	rng.seed = def.get("seed", 1)
	_palette = def.get("palette", {})
	var root := Node3D.new()
	root.name = def.get("name", "House")
	var w: int = def.w
	var d: int = def.d
	var floors: int = def.floors
	var door_side: String = def.get("door_side", "front")
	var over := _overrides(def, w, d, floors)
	for f in range(int(def.get("_from", 0)), floors):
		var z := 3.0 * f
		var level := Node3D.new()
		level.name = "Floor%d" % f
		level.set_meta("level", f)
		root.add_child(level)
		var mat: String = def.walls[min(f, def.walls.size() - 1)]
		var floor_piece: String = def.floors_mat[min(f, def.floors_mat.size() - 1)]
		for ix in w / 2:
			for iy in d / 2:
				_piece(floor_piece, level, Vector3(-w / 2.0 + 1 + 2 * ix, -d / 2.0 + 1 + 2 * iy, z))
		for side in SIDES:
			var rot: float = SIDES[side]
			var cells := _wall_cells(w, d, side)
			if f == 0 and side in def.get("open", []):
				for i in range(1, cells.size()):
					var mid: Vector2 = (cells[i - 1] + cells[i]) / 2.0
					_piece(def.corner, level, Vector3(mid.x, mid.y, z))
				continue
			for i in cells.size():
				var c: Vector2 = cells[i]
				var wall := Node3D.new()
				wall.set_meta("outward", OUTWARD[side])
				wall.add_to_group("wall")
				level.add_child(wall)
				var kind := "Straight"
				var facade: bool = side == "front" or side == "back"
				var is_door: bool = f == 0 and side == door_side and i == door_cell(def, cells.size())
				if is_door:
					kind = def.get("door_kind", "Door_Round" if def.get("round_door", true) else "Door_Flat")
				elif facade and (i + f) % 2 == 0 and rng.randf() < 0.8:
					kind = _window(def, f)
				elif not facade and rng.randf() < def.get("side_windows", 0.5) * 0.4:
					kind = _window(def, f)
				var o: Dictionary = over.get("%s|%d|%d" % [side, f, i], {})
				if o.has("kind") and not (is_door and not o.get("force", false)):
					kind = o.kind
				var wname := "Wall_%s_%s" % [mat, kind]
				if f > 0 and kind == "Straight" and mat == "Plaster" and def.get("grid", false):
					wname = "Wall_Plaster_WoodGrid"
				if not _exists(wname):
					wname = "Wall_%s_Straight" % mat
					kind = "Straight"
				var p := Vector3(c.x, c.y, z)
				_piece(wname, wall, p, rot)
				if kind == "Portal":
					_piece(def.get("portal_door", "Door_Portal"), wall, p, rot)
				elif kind.begins_with("Window"):
					if o.has("insert") and kind == o.get("kind", ""):
						_piece(o.insert, wall, p, rot)
					else:
						_piece(kind + "1", wall, p, rot)
						var shut = def.get("shutters", false)
						if shut is String:
							if shut == "closed" and _exists("WindowShutters_%s_Closed" % kind.trim_prefix("Window_")):
								_piece("WindowShutters_%s_Closed" % kind.trim_prefix("Window_"), wall, p, rot)
						elif shut and rng.randf() < 0.7:
							var state := "Open" if rng.randf() < 0.6 else "Closed"
							var sh := "WindowShutters_%s_%s" % [kind.trim_prefix("Window_"), state]
							if _exists(sh):
								_piece(sh, wall, p, rot)
				elif kind.begins_with("Door"):
					var hinge := Vector2(-0.53, 0).rotated(deg_to_rad(rot))  # along the wall, whatever its side
					_piece("%s_%s" % [def.get("door_leaf", "Door_1"), "Round" if kind == "Door_Round" else "Flat"], wall, p + Vector3(hinge.x, hinge.y, 0), rot)
				if f == 0 and def.has("plinth") and kind != "Portal":
					var pl := "Wall_Plinth_%s%s" % [def.plinth, "_Door" if kind.begins_with("Door") else ""]
					if _exists(pl):
						_piece(pl, wall, p, rot)
				for e in o.get("extras", []):
					if e.has("only") and not kind.begins_with(e.only):
						continue
					if e.has("unless") and kind.begins_with(e.unless):
						continue
					var off := Vector2(e.at.x, e.at.y).rotated(deg_to_rad(rot))
					var n := _piece(e.piece, wall, p + Vector3(off.x, off.y, e.at.z), rot + e.get("rot", 0.0))
					if n and e.has("tint"):
						_tint(n, e.tint[0], e.tint[1])
					if n and e.has("scale"):
						n.scale = Vector3.ONE * float(e.scale)
						n.position.y -= (float(e.scale) - 1.0) * float(e.get("keep_z", 0.0))
		for cxy in [Vector2(-w / 2.0, -d / 2.0), Vector2(w / 2.0, -d / 2.0), Vector2(w / 2.0, d / 2.0), Vector2(-w / 2.0, d / 2.0)]:
			_piece(def.corner, level, Vector3(cxy.x, cxy.y, z))
	var top := 3.0 * floors
	var roof := Node3D.new()
	roof.name = "Roof"
	roof.add_to_group("roof")
	root.add_child(roof)
	var along_x: bool = def.get("ridge", "y") == "x"
	var span := d if along_x else w   # across the ridge
	var run := w if along_x else d    # along the ridge
	var rrot := 90.0 if along_x else 0.0
	var roof_piece: Node3D
	if def.get("roof", "gable") == "none":
		pass
	elif def.get("roof", "gable") == "tower":
		roof_piece = _piece("Roof_Tower_RoundTiles", roof, Vector3(0, 0, top))
	else:
		var rname := "Roof_RoundTiles_%dx%d" % [span, run]
		if _exists(rname + "c"):
			rname += "c"  # a kit roof with its pivot off centre, centred (kit/modules: 6x4)
		roof_piece = _piece(rname, roof, Vector3(0, 0, top), rrot)
		var g := Vector2(0, -run / 2.0).rotated(deg_to_rad(rrot))
		var gable := _piece("Roof_Front_Brick%d" % span, roof, Vector3(g.x, g.y, top), rrot)
		_piece("Roof_Front_Brick%d" % span, roof, Vector3(-g.x, -g.y, top), rrot + 180)
		if def.has("banner") and gable:
			_banner(def, roof, w, d, top + _top_of(gable), along_x)
	# a flush corner tower takes its corner of the roof: a chimney that would stand there goes to the other end of
	# the ridge (or to the other slope, or is left out)
	var keep_off := Rect2()
	if def.has("tower") and float(def.tower.get("proud", 0.0)) <= 0.0:
		keep_off = _tower_rect(def.tower, w, d).grow(0.7)
	for cx in def.get("chimneys", []):
		var cp := "Prop_Chimney"
		var at := Vector2(0, run / 4.0)
		if cx is Dictionary:
			cp = cx.get("piece", cp)
			at = Vector2(float(cx.get("x", 0.5)) * span / 2.0, float(cx.get("y", 0.5)) * run / 2.0)
		else:
			at.x = float(cx) * span / 2.0
		var placed := false
		for flip in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			var p2: Vector2 = (at * flip).rotated(deg_to_rad(rrot))
			if keep_off.has_area() and keep_off.has_point(p2):
				continue
			_piece(cp, roof, Vector3(p2.x, p2.y, top), rrot)
			placed = true
			break
		if not placed and OS.is_debug_build():
			print("[HouseBuilder] chimney %s left out: the tower stands there" % [cx])
	if def.has("dovecote") and roof_piece:
		var ridge := _top_of(roof_piece) - 0.34  # under the ridge tiles
		var dv := Vector2(0, float(def.dovecote) * (run / 2.0 - 1.0)).rotated(deg_to_rad(rrot))
		_piece("Prop_Dovecote", roof, Vector3(dv.x, dv.y, top + ridge), rrot)
	if def.has("tower"):
		_tower(def, root, w, d, floors)
	for e in def.get("props", []):
		_piece(e[0], root, e[1], e[2])
	_outside(def, root, w, d)
	var inside := Node3D.new()
	inside.name = "Interior"
	root.add_child(inside)
	for e in def.get("interior", []):
		_piece(e[0], inside, e[1], e[2])
	_palette = {}
	if OS.is_debug_build():
		print("[HouseBuilder] built %s (%dx%d, %d floors, seed %d%s)" % [root.name, w, d, floors, rng.seed,
			"" if over.is_empty() else ", %d cells with modules" % over.size()])
	return root


# ---------------------------------------------------------------- our modules (kit/modules)
static var _tints := {}  # "material id|colour" -> Material


## Surfaces whose material is called `mat_name` get a copy with that albedo colour (awning cloth, shield field).
static func _tint(n: Node, mat_name: String, col: Color) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var m := n.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null or m.resource_name != mat_name:
				continue
			var key := "%d|%s" % [m.get_instance_id(), col.to_html()]
			if not _tints.has(key):
				var v: StandardMaterial3D = m.duplicate()
				v.albedo_color = col
				_tints[key] = v
			n.set_surface_override_material(i, _tints[key])
	for c in n.get_children():
		_tint(c, mat_name, col)


## The guild banner (def.banner: {emblem, color, side}): a hoist beam through a gable, a metre under its apex, and the
## trade's cloth hanging from it clear of the roof's verge. `apex`: height of the gable's top. The gable of the door's
## side when the ridge runs front to back; with the ridge along the front the gables are the side walls (banner.side).
static func _banner(def: Dictionary, roof: Node3D, w: int, d: int, apex: float, along_x: bool) -> void:
	var b: Dictionary = def.banner
	var gables := ["right", "left"] if along_x else ["front", "back"]
	var side: String = b.get("side", def.get("door_side", "front"))
	if side not in gables:
		side = gables[0]
	var at: Vector2 = (OUTWARD[side] as Vector2) * ((w if along_x else d) / 2.0)
	var piece := "Prop_Banner_%s" % b.get("emblem", "Blank")
	if not _exists(piece):
		push_warning("[HouseBuilder] no banner piece %s" % piece)
		return
	var n := _piece(piece, roof, Vector3(at.x, at.y, apex - 1.05), SIDES[side])
	if n and b.get("color") is Color:
		_tint(n, "MI_Awning", b.color)
	if OS.is_debug_build():
		print("[HouseBuilder] banner %s on the %s gable at %.1f m (%s)" % [piece, side, apex - 1.05, b.get("color", "canvas")])


## The plan square (4 x 4 m) a corner tower stands on.
static func _tower_rect(t: Dictionary, w: int, d: int) -> Rect2:
	var corner: String = t.get("corner", "front_left")
	var sx := -1.0 if corner.ends_with("left") else 1.0
	var sy := -1.0 if corner.begins_with("front") else 1.0
	var proud: float = float(t.get("proud", 0.0))
	var c := Vector2(sx * (w / 2.0 - 2.0 + proud), sy * (d / 2.0 - 2.0 + proud))
	return Rect2(c - Vector2(2, 2), Vector2(4, 4))


## The window kind of storey f: def.windows[f] (one per storey, the last one repeats) or def.window.
static func _window(def: Dictionary, f: int) -> String:
	if def.has("windows") and not (def.windows as Array).is_empty():
		return def.windows[min(f, def.windows.size() - 1)]
	return def.get("window", "Window_Wide_Round")


## The cell of the door on a wall of n cells: def.door_cell (negative counts from the end) or the middle one.
static func door_cell(def: Dictionary, n: int) -> int:
	if not def.has("door_cell"):
		return n / 2
	var i := int(def.door_cell)
	return clampi(i if i >= 0 else n + i, 0, n - 1)


static func _top_of(n: Node) -> float:
	var best := 0.0
	if n is MeshInstance3D and n.mesh:
		best = n.mesh.get_aabb().end.y
	for c in n.get_children():
		best = maxf(best, _top_of(c))
	return best


static func _range(e: Dictionary, n: int) -> Array:
	var a: int = int(e.get("from", 0))
	var b: int = int(e.get("to", -1))
	if a < 0:
		a += n
	if b < 0:
		b += n
	return [clampi(a, 0, n - 1), clampi(b, 0, n - 1)]


static func _add(over: Dictionary, key: String, extra: Dictionary) -> void:
	if not over.has(key):
		over[key] = {}
	if not over[key].has("extras"):
		over[key]["extras"] = []
	over[key].extras.append(extra)


## What the def asks of each wall cell: "side|floor|cell" -> {kind, insert, extras[{piece, at, rot, tint, only}]}.
## Cells run left to right as seen from outside, on every side. `at` is in the cell's own frame (x along the wall,
## y inwards, z up from the floor of the storey).
static func _overrides(def: Dictionary, w: int, d: int, floors: int) -> Dictionary:
	var over := {}
	var door_side: String = def.get("door_side", "front")
	var eaves := ["front", "back"] if def.get("ridge", "y") == "x" else ["left", "right"]
	if def.has("shop"):
		var sh: Dictionary = def.shop
		var side: String = sh.get("side", door_side)
		var n := _wall_cells(w, d, side).size()
		for i in sh.get("cells", [0]):
			var idx: int = int(i) if int(i) >= 0 else n + int(i)
			var key := "%s|0|%d" % [side, idx]
			over[key] = {kind = "Window_Wide_Flat", insert = "Shop_Front1"}
			var aw = sh.get("awning", true)
			if not (aw is bool and aw == false):
				var e := {piece = "Shop_Awning", at = Vector3.ZERO, only = "Window_Wide_Flat"}
				if aw is Color:
					e.tint = ["MI_Awning", aw]
				_add(over, key, e)
	var sign: String = def.get("sign", "")
	if def.has("shop") and sign == "":
		sign = def.shop.get("sign", "")
	if sign != "":
		var n := _wall_cells(w, d, door_side).size()
		var se := {piece = "Prop_Sign_%s" % sign, at = Vector3(1.0, 0, 0)}
		if float(def.get("sign_scale", 1.0)) != 1.0:
			se.scale = float(def.sign_scale)  # a bigger board, its lower edge where it was (2.11 m: heads pass under it)
			se.keep_z = 2.11
		_add(over, "%s|0|%d" % [door_side, door_cell(def, n)], se)
	for e: Dictionary in def.get("balcony", []):
		var side: String = e.get("side", door_side)
		var f: int = int(e.get("floor", 1))
		if f < 1 or f >= floors:
			push_warning("[HouseBuilder] balcony on floor %d of a house of %d floors: skipped" % [f, floors])
			continue
		var n := _wall_cells(w, d, side).size()
		var r := _range(e, n)
		var rail := "Balcony_%s_Straight" % e.get("rail", "Cross")
		var door: int = int(e.get("door", (r[0] + r[1] + 1) / 2))
		for i in range(r[0], r[1] + 1):
			var key := "%s|%d|%d" % [side, f, i]
			if i == door:
				over[key] = {kind = "Door_Flat"}
			_add(over, key, {piece = "Balcony_Floor_Straight", at = Vector3.ZERO})
			_add(over, key, {piece = rail, at = Vector3.ZERO})
			if i == r[0]:
				_add(over, key, {piece = "Balcony_Cross_End_L", at = Vector3.ZERO})
			if i == r[1]:
				_add(over, key, {piece = "Balcony_Cross_End_R", at = Vector3.ZERO})
			if e.get("roof", false):  # a covered gallery: posts on the railing line, a plate and the kit's wooden roof
				_add(over, key, {piece = "Gallery_Post", at = Vector3.ZERO})
				_add(over, key, {piece = "Gallery_Beam", at = Vector3.ZERO})
				_add(over, key, {piece = "Roof_Wooden_2x1", at = Vector3(0, 0, 2.2)})
				if i == r[1]:
					_add(over, key, {piece = "Gallery_Post", at = Vector3(2.0, 0, 0)})
	for e: Dictionary in def.get("porch", []):
		var side: String = e.get("side", door_side)
		var n := _wall_cells(w, d, side).size()
		var r := _range(e, n)
		if floors == 1:
			# the lean-to reaches 3.7 m: under the eaves of a one-storey house it does not fit, and on its gable
			# walls only away from the corners (the main roof comes down there)
			if side in eaves:
				push_warning("[HouseBuilder] porch on the eave side of a one-storey house: skipped")
				continue
			r = [maxi(r[0], 1), mini(r[1], n - 2)]
			if r[0] > r[1]:
				continue
		var post := "Porch_Stone_Post" if e.get("posts", "wood") == "stone" else "Porch_Wood_Post"
		for i in range(r[0], r[1] + 1):
			var key := "%s|0|%d" % [side, i]
			_add(over, key, {piece = "Roof_LeanTo_RoundTiles", at = Vector3.ZERO})
			_add(over, key, {piece = "Porch_Wood_Beam", at = Vector3.ZERO})
			_add(over, key, {piece = post, at = Vector3(-1, 0, 0)})
			if e.get("stalls", false):
				_add(over, key, {piece = "Stable_Stall", at = Vector3.ZERO})
			if i == r[0]:
				_add(over, key, {piece = "Roof_LeanTo_RoundTiles_End_L", at = Vector3.ZERO})
				if e.get("ends", "open") == "boards":
					_add(over, key, {piece = "Shed_Side_L", at = Vector3(-1, 0, 0)})
			if i == r[1]:
				_add(over, key, {piece = post, at = Vector3(1, 0, 0)})
				_add(over, key, {piece = "Roof_LeanTo_RoundTiles_End_R", at = Vector3.ZERO})
				if e.get("ends", "open") == "boards":
					_add(over, key, {piece = "Shed_Side_R", at = Vector3(1, 0, 0)})
	if def.has("oven"):
		var ov: Dictionary = def.oven
		var side: String = ov.get("side", "back")
		var key := "%s|0|%d" % [side, int(ov.get("cell", 0))]
		over[key] = {kind = "Straight", force = true}
		_add(over, key, {piece = "Prop_Chimney_Oven", at = Vector3.ZERO})
	if def.has("hatch"):
		var hk := "%s|0|%d" % [def.hatch.get("side", "back"), int(def.hatch.get("cell", 0))]
		over[hk] = {kind = "Straight", force = true}
		_add(over, hk, {piece = "Prop_CellarHatch", at = Vector3.ZERO})
	if def.has("barn"):
		over["%s|0|%d" % [def.barn.get("side", "back"), int(def.barn.get("cell", 0))]] = {kind = "Barn", force = true}
	if def.has("loft"):
		var lk := "%s|%d|%d" % [def.loft.get("side", door_side), int(def.loft.get("floor", floors - 1)), int(def.loft.get("cell", 0))]
		over[lk] = {kind = "Loft", force = true}
	if def.has("grille"):
		var gf: Array = def.grille.get("floors", [0]) if def.grille is Dictionary else [0]
		for side: String in SIDES:
			for f: int in gf:
				for i in _wall_cells(w, d, side).size():
					_add(over, "%s|%d|%d" % [side, f, i], {piece = "Window_Grille_Wide_Round", at = Vector3.ZERO, only = "Window_Wide_Round"})
	if def.get("lantern", false):
		var ln := _wall_cells(w, d, door_side).size()
		_add(over, "%s|0|%d" % [door_side, door_cell(def, ln)], {piece = "Prop_Lantern", at = Vector3(-1.0, 0, 0)})
	var dn := _wall_cells(w, d, door_side).size()
	for i in def.get("herbs", []):
		var hi: int = int(i) if int(i) >= 0 else dn + int(i)
		_add(over, "%s|0|%d" % [door_side, hi], {piece = "Prop_Planter", at = Vector3.ZERO, only = "Window"})
		_add(over, "%s|0|%d" % [door_side, hi], {piece = "Prop_HerbRail", at = Vector3.ZERO, unless = "Window"})
	if def.has("display"):
		var dsp: Dictionary = def.display
		for i in dsp.get("cells", [0]):
			var di: int = int(i) if int(i) >= 0 else dn + int(i)
			var dkey := "%s|0|%d" % [door_side, di]
			var keep: Array = over.get(dkey, {}).get("extras", [])
			over[dkey] = {kind = "Window_Wide_Flat", insert = "Shop_Display1", extras = keep}
			var daw = dsp.get("awning", false)
			if not (daw is bool and daw == false):
				var de := {piece = "Shop_Awning", at = Vector3.ZERO, only = "Window_Wide_Flat"}
				if daw is Color:
					de.tint = ["MI_Awning", daw]
				_add(over, dkey, de)
	for e: Dictionary in def.get("cloth", []):
		_add(over, "%s|%d|%d" % [e.get("side", door_side), int(e.get("floor", 1)), int(e.get("cell", 0))], {piece = "Prop_ClothLine", at = Vector3.ZERO})
	if def.get("portal", false):
		var n := _wall_cells(w, d, door_side).size()
		var dk := "%s|0|%d" % [door_side, door_cell(def, n)]
		over[dk] = over.get(dk, {})
		over[dk].merge({kind = "Portal", force = true})
		if def.has("shield") and not (def.shield is bool and def.shield == false):
			var e := {piece = "Prop_Shield", at = Vector3(0, 0, 3.0)}
			if def.shield is Color:
				e.tint = ["MI_ShieldField", def.shield]
			_add(over, dk, e)
			if floors > 1:  # the shield hangs on the wall above the portal: no window there
				var up := "%s|1|%d" % [door_side, door_cell(def, n)]
				if not over.has(up):
					over[up] = {}
				if not over[up].has("kind"):
					over[up]["kind"] = "Straight"
				if def.get("shield_flank", false):  # windows on both sides of the shield, whatever the dice say
					for j in [door_cell(def, n) - 1, door_cell(def, n) + 1]:
						var fk := "%s|1|%d" % [door_side, j]
						if j >= 0 and j < n and not over.get(fk, {}).has("kind"):
							over[fk] = over.get(fk, {})
							over[fk]["kind"] = _window(def, 1)
	return over


## What stands around the house inside its lot: things by a wall (yard), a walled court, more buildings (annex).
static func _outside(def: Dictionary, root: Node3D, w: int, d: int) -> void:
	for e: Dictionary in def.get("yard", []):
		var side: String = e.get("side", "back")
		var cells := _wall_cells(w, d, side)
		var i: int = clampi(int(e.get("cell", 0)) if int(e.get("cell", 0)) >= 0 else cells.size() + int(e.get("cell", 0)), 0, cells.size() - 1)
		var c: Vector2 = cells[i] + (OUTWARD[side] as Vector2) * float(e.get("out", 1.0)) \
			+ Vector2(float(e.get("along", 0.0)), 0).rotated(deg_to_rad(SIDES[side]))
		_piece(e.piece, root, Vector3(c.x, c.y, 0), SIDES[side] + float(e.get("rot", 0.0)))
	if def.has("court"):
		var ct: Dictionary = def.court
		var side: String = ct.get("side", "back")
		var rot: float = deg_to_rad(SIDES[side])
		var along: float = (w if side in ["front", "back"] else d) / 2.0
		var off: float = (d if side in ["front", "back"] else w) / 2.0
		var dep: float = float(ct.get("depth", 4))
		var q := Node3D.new()
		q.name = "Court"
		root.add_child(q)
		# in the frame of the front wall (outwards is -y), turned to the side
		var pts := [Vector2(-along, -off), Vector2(-along, -off - dep), Vector2(along, -off - dep), Vector2(along, -off)]
		for k in pts.size():
			pts[k] = (pts[k] as Vector2).rotated(rot)
		# the gate: true or "far" (the run opposite the house), "first" / "last" (the runs that leave the wall at its
		# first and last cell), false (none)
		var gate = ct.get("gate", true)
		var where: String = gate if gate is String else ("far" if gate else "")
		var n_side := int(round(dep / 2.0))
		var n_far := int(round(along))
		fence(q, pts[0], pts[1], n_side / 2 if where == "first" else -1, "Prop_StoneGate", "Prop_StoneWall_Single")
		fence(q, pts[1], pts[2], n_far / 2 if where == "far" else -1, "Prop_StoneGate", "Prop_StoneWall_Single")
		fence(q, pts[2], pts[3], (n_side - 1) / 2 if where == "last" else -1, "Prop_StoneGate", "Prop_StoneWall_Single")
		for k in [1, 2]:
			_piece("Prop_StoneWall_Pier", q, Vector3(pts[k].x, pts[k].y, 0))
	for e: Dictionary in def.get("annex", []):
		var sub: Dictionary = e.duplicate(true)
		sub.erase("at")
		sub.erase("rot")
		if not sub.has("palette"):
			sub.palette = def.get("palette", {})
		var pal: Dictionary = _palette
		var a := build(sub)
		_palette = pal
		a.name = "Annex"
		var at: Vector2 = e.get("at", Vector2.ZERO)
		a.position = plan_to_godot(Vector3(at.x, at.y, 0))
		a.rotation.y = deg_to_rad(float(e.get("rot", 0.0)))
		root.add_child(a)


## The building site of a def (def.stage): "stakes" (the lot pegged out with cord, timber and stone waiting),
## "foundation" (the footing of every wall) or "frame" (the storey def.stage_floor half built over the finished ones
## below: stone walls half way up, timber walls still laths, scaffold on def.scaffold sides, no roof).
static func _site(def: Dictionary) -> Node3D:
	var stage: String = def.stage
	var w: int = def.w
	var d: int = def.d
	var root: Node3D
	var sf: int = clampi(int(def.get("stage_floor", 0)), 0, int(def.floors) - 1)
	if stage == "frame" and sf > 0:
		var below: Dictionary = def.duplicate(true)
		for k in ["stage", "tower", "dovecote", "chimneys", "annex", "court", "loft", "cloth"]:
			below.erase(k)
		if sf < 2:
			below.erase("porch")  # the lean-to hangs from the wall of the storey above
		below.floors = sf
		below.roof = "none"
		below.balcony = []
		root = build(below)
	else:
		root = Node3D.new()
	root.name = def.get("name", "House")
	_palette = def.get("palette", {})
	var hw := w / 2.0
	var hd := d / 2.0
	var corners := [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	if stage == "stakes" or stage == "foundation":
		var q := Node3D.new()
		q.name = "Site"
		root.add_child(q)
		for k in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			if stage == "stakes":
				fence(q, a, b, -1, "", "Site_Rope")
			var n := int(round((b - a).length() / 2.0))
			for i in n:
				if stage == "stakes" or i == 0:
					var sp := a + (b - a).normalized() * 2.0 * i
					_piece("Site_Stake", q, Vector3(sp.x, sp.y, 0), 90.0 * k + 37.0 * i)
		if stage == "foundation":
			for side in SIDES:
				for c: Vector2 in _wall_cells(w, d, side):
					_piece("Site_Footing", q, Vector3(c.x, c.y, 0), SIDES[side])
		_piece("Prop_PlankStack", q, Vector3(-hw + 1.4, hd - 1.2, 0), 0.0)
		_piece("Prop_StoneBlocks", q, Vector3(hw - 1.4, hd - 1.4, 0), 180.0)
	else:
		var z := 3.0 * sf
		var level := Node3D.new()
		level.name = "Floor%d" % sf
		level.set_meta("level", sf)
		root.add_child(level)
		var mat: String = def.walls[min(sf, def.walls.size() - 1)]
		var piece: String = "Wall_UnevenBrick_Half" if mat == "UnevenBrick" else ("Wall_Boards_Straight" if mat == "Boards" else "Wall_Plaster_WoodGrid")
		var fl: String = def.floors_mat[min(sf, def.floors_mat.size() - 1)]
		for ix in w / 2:
			for iy in d / 2:
				_piece(fl, level, Vector3(-hw + 1 + 2 * ix, -hd + 1 + 2 * iy, z))
		var door_side: String = def.get("door_side", "front")
		for side in SIDES:
			var cells := _wall_cells(w, d, side)
			for i in cells.size():
				var c: Vector2 = cells[i]
				var wall := Node3D.new()
				wall.set_meta("outward", OUTWARD[side])
				wall.add_to_group("wall")
				level.add_child(wall)
				if sf == 0 and side == door_side and i == door_cell(def, cells.size()):
					var dw := "Wall_%s_Door_%s" % [mat, "Round" if def.get("round_door", true) else "Flat"]
					_piece(dw if _exists(dw) else piece, wall, Vector3(c.x, c.y, z), SIDES[side])
				else:
					_piece(piece, wall, Vector3(c.x, c.y, z), SIDES[side])
		for cxy: Vector2 in corners:
			_piece(def.corner, level, Vector3(cxy.x, cxy.y, z))
		var q := Node3D.new()
		q.name = "Site"
		root.add_child(q)
		for side: String in def.get("scaffold", [door_side]):
			var cells := _wall_cells(w, d, side)
			for i in cells.size():
				for k in sf + 1:
					_piece("Scaffold_Bay", q, Vector3(cells[i].x, cells[i].y, 3.0 * k), SIDES[side])
			if not cells.is_empty():
				var c0: Vector2 = cells[cells.size() - 1]
				for k in sf + 1:
					_piece("Scaffold_Ladder", q, Vector3(c0.x, c0.y, 3.0 * k), SIDES[side])
	var inside := Node3D.new()
	inside.name = "Interior"
	root.add_child(inside)
	_palette = {}
	if OS.is_debug_build():
		print("[HouseBuilder] built site %s (%dx%d, stage %s, floor %d)" % [root.name, w, d, stage, sf])
	return root


## A run of yard fence from a to b (plan metres, a multiple of 2 m apart), with a gate in place of segment `gate`
## (Prop_WoodenFence_Gate, Prop_WoodenFence_Gate_Open, Prop_StoneGate, Prop_StoneGate_Open: same pivot and 2 m span as a
## fence segment). Gates open towards the left of the direction a -> b: run the fence with the yard on its left.
static func fence(parent: Node3D, a: Vector2, b: Vector2, gate := -1, gate_piece := "Prop_WoodenFence_Gate", piece := "Prop_WoodenFence_Single") -> void:
	var dir := b - a
	var n := int(round(dir.length() / 2.0))
	for i in n:
		var c := a + dir.normalized() * (2.0 * i + 1.0)
		_piece(gate_piece if i == gate and gate_piece != "" else piece, parent, Vector3(c.x, c.y, 0), rad_to_deg(dir.angle()))
	if OS.is_debug_build():
		print("[HouseBuilder] fence %s -> %s: %d segments%s" % [a, b, n, "" if gate < 0 else ", %s at %d" % [gate_piece, gate]])


## A corner tower: a 4x4 m house of its own (same walls and palette, the kit's tower roof) on a corner of the house.
## By default it is flush with the footprint (it does not leave the lot): the house's own walls are its lower storeys,
## it rises from the top of the walls past the ridge (tower.floors: storeys in all) and the house roof is cut away
## where the tower stands. tower.proud = 1.0 is the old tower, a whole 4x4 house 1 m out on both sides.
static func _tower(def: Dictionary, root: Node3D, w: int, d: int, floors: int) -> void:
	var t: Dictionary = def.tower
	var corner: String = t.get("corner", "front_left")
	var sx := -1.0 if corner.ends_with("left") else 1.0
	var sy := -1.0 if corner.begins_with("front") else 1.0
	var proud: float = float(t.get("proud", 0.0))
	var flush := proud <= 0.0
	var span: int = d if def.get("ridge", "y") == "x" else w
	# the kit's roofs rise 0.75 m per metre of span: the tower's walls go at least as high as the ridge
	var tf: int = int(t.get("floors", floors + (ceili(span * 0.75 / 3.0) if flush else 1)))
	var walls := []
	for f in tf:
		walls.append(def.walls[min(f, def.walls.size() - 1)])
	var tdef := {name = "Tower", w = 4, d = 4, floors = tf, walls = walls, roof = "tower",
		floors_mat = def.floors_mat, corner = def.corner, window = t.get("window", "Window_Thin_Round"),
		grid = def.get("grid", false), shutters = false, side_windows = 1.6, seed = int(def.get("seed", 1)) + 77,
		palette = def.get("palette", {}), door_side = "none"}
	if def.has("plinth"):
		tdef.plinth = def.plinth
	var c := Vector2(sx * (w / 2.0 - 2.0 + proud), sy * (d / 2.0 - 2.0 + proud))
	if flush:
		tdef["_from"] = floors
		# the roof and its gables lose what falls on the tower (and beyond it, outwards)
		var rc := Rect2(c - Vector2(1.88, 1.88), Vector2(3.76, 3.76))
		rc = rc.expand(c + Vector2(sx, sy) * 60.0)
		for ch in root.get_children():
			if ch.is_in_group("roof"):
				_clip_out(ch, root, rc)
	var pal: Dictionary = _palette
	var tower := build(tdef)
	_palette = pal
	tower.name = "Tower"
	tower.position = plan_to_godot(Vector3(c.x, c.y, 0))
	# its storeys join the house's storeys (cutaway and baking go by level); the roof stays a roof
	for ch in tower.get_children():
		if ch.name == "Interior":
			continue
		tower.remove_child(ch)
		ch.position += tower.position
		root.add_child(ch)
	tower.free()


## Cuts out of every mesh under `n` what stands over the plan rectangle `rc` (plan metres in the frame of `ref`), at
## any height. Triangles that cross its edge are clipped (positions, normals and UVs interpolated).
static func _clip_out(n: Node, ref: Node3D, rc: Rect2) -> void:
	if n is MeshInstance3D and n.mesh:
		var mi := n as MeshInstance3D
		var xf := _rel(mi, ref) if mi != ref else Transform3D.IDENTITY
		var out := ArrayMesh.new()
		var over := []
		var cut := 0
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var plan := PackedVector2Array()
			plan.resize(vs.size())
			for i in vs.size():
				var p := xf * vs[i]
				plan[i] = Vector2(p.x, -p.z)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var count := idx.size() if not idx.is_empty() else vs.size()
			var any := false
			for ti in range(0, count, 3):
				var poly := []  # [plan, position, normal, uv]
				var inside := 0
				for k in 3:
					var vi: int = idx[ti + k] if not idx.is_empty() else ti + k
					poly.append([plan[vi], vs[vi], ns[vi] if not ns.is_empty() else Vector3.UP, uvs[vi] if not uvs.is_empty() else Vector2.ZERO])
				var pieces := []
				var lo := rc.position
				var hi := rc.end
				if (poly[0][0].x <= lo.x and poly[1][0].x <= lo.x and poly[2][0].x <= lo.x) or (poly[0][0].x >= hi.x and poly[1][0].x >= hi.x and poly[2][0].x >= hi.x) \
						or (poly[0][0].y <= lo.y and poly[1][0].y <= lo.y and poly[2][0].y <= lo.y) or (poly[0][0].y >= hi.y and poly[1][0].y >= hi.y and poly[2][0].y >= hi.y):
					pieces.append(poly)
				else:
					cut += 1
					var rest := poly
					for cutp in [[0, lo.x, -1.0], [0, hi.x, 1.0], [1, lo.y, -1.0], [1, hi.y, 1.0]]:
						var halves := _split(rest, cutp[0], cutp[1], cutp[2])
						if halves[0].size() >= 3:
							pieces.append(halves[0])
						rest = halves[1]
						if rest.size() < 3:
							break
				for pc: Array in pieces:
					for k in range(1, pc.size() - 1):
						for v in [pc[0], pc[k], pc[k + 1]]:
							st.set_normal((v[2] as Vector3).normalized())
							st.set_uv(v[3])
							st.add_vertex(v[1])
							any = true
			if any:
				if not uvs.is_empty() and not ns.is_empty():
					st.generate_tangents()
				# indexed, as every kit mesh: SurfaceTool.append_from (bake, opt3d) adds no indices for a mesh without them,
				# so in a merge with indexed meshes these triangles were never drawn (the roof of a house with a tower)
				st.index()
				out = st.commit(out)
				out.surface_set_material(out.get_surface_count() - 1, mi.mesh.surface_get_material(si))
				over.append(mi.get_surface_override_material(si))
		for si in mi.mesh.get_surface_count():
			mi.set_surface_override_material(si, null)
		mi.mesh = out
		for si in over.size():
			if over[si] != null:
				mi.set_surface_override_material(si, over[si])
		if OS.is_debug_build():
			print("[HouseBuilder] roof cut for the tower: %s, %d triangles clipped, %d surfaces left" % [mi.name, cut, out.get_surface_count()])
	for c in n.get_children():
		_clip_out(c, ref, rc)


## Splits a convex polygon of [plan, position, normal, uv] by the line plan[axis] = at: [the part on the side `sign`
## (outside), the rest].
static func _split(poly: Array, axis: int, at: float, sgn: float) -> Array:
	var a := []
	var b := []
	var n := poly.size()
	for i in n:
		var p: Array = poly[i]
		var q: Array = poly[(i + 1) % n]
		var dp: float = ((p[0] as Vector2)[axis] - at) * sgn
		var dq: float = ((q[0] as Vector2)[axis] - at) * sgn
		if dp >= 0.0:
			a.append(p)
		if dp <= 0.0:
			b.append(p)
		if (dp > 0.0 and dq < 0.0) or (dp < 0.0 and dq > 0.0):
			var k := dp / (dp - dq)
			var m := [(p[0] as Vector2).lerp(q[0], k), (p[1] as Vector3).lerp(q[1], k), (p[2] as Vector3).lerp(q[2], k), (p[3] as Vector2).lerp(q[3], k)]
			a.append(m)
			b.append(m)
	return [a, b]


## Cutaway: hide roof, floors above `level`, and walls whose outward side faces the camera.
static func set_cutaway(house: Node3D, on: bool, cam_dir_plan: Vector2, level := 0) -> void:
	for child in house.get_children():
		if child.is_in_group("roof"):
			child.visible = not on
		elif child.has_meta("level"):
			var lv: int = child.get_meta("level")
			child.visible = (not on) or lv <= level
			for wall in child.get_children():
				if wall.is_in_group("wall"):
					var facing: bool = (wall.get_meta("outward") as Vector2).dot(cam_dir_plan) > 0.1
					wall.visible = not (on and lv == level and facing)


# ---------------------------------------------------------------- baking
## Merge a built house into a few meshes (one per material inside each group) so a town of
## houses costs a handful of draw calls each. Groups kept apart: every level's walls per side
## (the cutaway hides camera-facing walls), the rest of each level, the roof, the interior, props.
static func bake(root: Node3D) -> void:
	for child in root.get_children():
		if child.has_meta("level"):
			var by_side := {}
			var misc := []
			var old := child.get_children()
			for c in old:
				if c.is_in_group("wall"):
					var k: Vector2 = c.get_meta("outward")
					if not by_side.has(k):
						by_side[k] = []
					by_side[k].append(c)
				else:
					misc.append(c)
			for k in by_side:
				var mi := _merge_into(by_side[k], child, "walls")
				if mi:
					mi.add_to_group("wall")
					mi.set_meta("outward", k)
			_merge_into(misc, child, "misc")
			for c in old:
				c.free()
		elif child is Node3D and (child.is_in_group("roof") or child.name == "Interior"):
			var old2 := child.get_children()
			_merge_into(old2, child, "baked")
			for c in old2:
				c.free()
	var loose := []
	for child in root.get_children():
		if not child.has_meta("level") and not child.is_in_group("roof") and child.name != "Interior":
			loose.append(child)
	if not loose.is_empty():
		_merge_into(loose, root, "props")
		for c in loose:
			c.free()


static func _rel(n: Node3D, ref: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != ref:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _collect(n: Node, ref: Node3D, tools: Dictionary, mats: Dictionary) -> void:
	if n is MeshInstance3D and n.mesh:
		var xf := _rel(n, ref)
		for i in n.mesh.get_surface_count():
			var mat: Material = n.get_active_material(i)
			var key: int = mat.get_instance_id() if mat else 0
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
				mats[key] = mat
			(tools[key] as SurfaceTool).append_from(n.mesh, i, xf)
	for c in n.get_children():
		_collect(c, ref, tools, mats)


static func _merge_into(sources: Array, owner: Node3D, name: String) -> MeshInstance3D:
	var tools := {}
	var mats := {}
	for s in sources:
		_collect(s, owner, tools, mats)
	if tools.is_empty():
		return null
	var am := ArrayMesh.new()
	for key in tools:
		am = (tools[key] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = am
	owner.add_child(mi)
	return mi
