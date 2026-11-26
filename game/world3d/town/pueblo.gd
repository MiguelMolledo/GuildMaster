extends "res://game/world3d/town/main.gd"
## A town built from a GuildMaster 2D tile map (data/maps/town_e.json); one tile = 2 m.
## Legend: # building · = road · , path · P/S/N plaza (S stall, N notice board) · f field ·
## w river · b bridge · T tree · . grass. One house per lot the 2D draws on the '#' blocks (each building on its footprint,
## the decor house lots, filler lots), sized to a kit module and centred on its door; the rest of each block is fenced yard
## (earth, vegetable plots and the 2D yard props). The lone '#' of the plaza is the well (tools/well.py).
## Run: godot --path . res://pueblo.tscn [-- --shots] [--map=<path>]

var DEFAULT_MAP: String = OS.get_environment("HOME").path_join("Code/GuildMaster/data/maps/town_e.json")  # the home folder was renamed once
const ROAD := "=,b"
const ROOF_W := {"": 45, "roof_oscura": 25, "roof_marron": 20, "roof_pizarra": 6, "roof_morado": 4}

var grid: Array[String] = []
var mapd: Dictionary
var W := 0
var H := 0
var rng := RandomNumberGenerator.new()
var _water: Array[ShaderMaterial] = []
var _map_path := DEFAULT_MAP
## The camera yaw the town opens with (--yaw=225). In town_e 14 of 18 fronts look north or west: from 45 the camera
## shows 4 fronts, from 225 it shows 14 (docs/interior3d.md): 225 is the default, `--yaw=45` gives the old view. The sun
## turns with it (here and in sim3d.gd), so the faces in view are the lit ones as they were from 45.
var home_yaw := 225.0
## What the sim knows of each building, by the origin tile of its footprint (sim3d.gd fills it from the trace before the
## town is built): {upgrades: [ids], construction: [kind, start, end] or [], work: [upgrade, start, end] or [],
## farm: bool (somebody of the house works the fields), now: minute}. Empty without a trace: the rules by data alone.
var sim_buildings := {}
var season_id := "spring"  # the sim's season (sim3d.gd sets it from the trace; --season= overrides): crops, trees
var vivo: RefCounted       # street furniture, animals, field crops, dock (scripts/pueblo_vivo.gd)


func _ready() -> void:
	if mapd.is_empty():  # GuildMaster: Town3D sets mapd (the catalog's map of the game) before _ready
		var path := DEFAULT_MAP
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--map="):
				path = a.trim_prefix("--map=")
		_map_path = path
		mapd = JSON.parse_string(FileAccess.get_file_as_string(path))
	grid.assign(mapd.rows)
	H = grid.size()
	W = grid[0].length()
	rng.seed = 2026
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--yaw="):
			home_yaw = float(a.trim_prefix("--yaw="))
		elif a.begins_with("--season="):
			season_id = a.trim_prefix("--season=")
	_river_under_blocks()
	_plots_of_sim()
	_build_world()
	for n in get_children():
		if n is DirectionalLight3D:
			(n as DirectionalLight3D).rotation_degrees.y += home_yaw - 45.0  # the lit faces are the ones in view
	_q = Node3D.new()
	_q.name = "Props"
	add_child(_q)
	vivo = preload("res://game/world3d/town/pueblo_vivo.gd").new(self)
	_town_buildings()
	_town_roads()
	_yard_ground()
	_river()
	if mill == null:
		_mill_wheel()
	_plaza_cross()
	_town_props()
	_town_trees()
	_town_nature()
	_collect_materials(self)
	set_style("outline")
	set_season(0)
	target = Vector3(W, 2, H)
	cam.size = 74
	yaw = home_yaw
	_update_camera()
	set_meta("opt_houses", true)  # opt3d merges the baked houses per cell (set_cutaway below swaps back to the pieces)
	preload("res://game/world3d/town/opt3d.gd").apply(self, OS.get_cmdline_user_args())  # rendering optimisations (bench3d.gd)
	vivo.live()  # lamps by the hour, the beasts near the camera animated
	if OS.is_debug_build():
		print("[Pueblo] %dx%d tiles, %d houses" % [W, H, houses.size()])
	if "--shots" in OS.get_cmdline_user_args():
		_town_shots()


func set_cutaway(on: bool) -> void:
	## the merged house cells (opt3d "houses") cannot drop single walls: the cutaway shows the house pieces instead
	if on:
		preload("res://game/world3d/town/opt3d.gd").house_sources(self, true)
	super(on)
	if not on:
		preload("res://game/world3d/town/opt3d.gd").house_sources(self, false)


func _t(c: int, r: int) -> String:
	if r < 0 or r >= H or c < 0 or c >= W:
		return "."
	return grid[r][c]


func _river_under_blocks() -> void:
	## The 2D map lets a '#' block lie over the river (town_e: the east blocks cover its two columns, so the river
	## stopped at their yards and started again after them). In 3D the river runs on: the '#' tiles between two water or
	## bridge tiles of one column (or row) become water. Nobody walks there either way.
	var made := 0
	for vertical in [true, false]:
		for a in (W if vertical else H):
			var last := -1
			for b in (H if vertical else W):
				var ch := _t(a, b) if vertical else _t(b, a)
				if ch != "w" and ch != "b":
					continue
				if last >= 0 and b - last > 1:
					var block := true
					for k in range(last + 1, b):
						if (_t(a, k) if vertical else _t(k, a)) != "#":
							block = false
					if block:
						for k in range(last + 1, b):
							var row: String = grid[k if vertical else a]
							row[a if vertical else k] = "w"
							grid[k if vertical else a] = row
							made += 1
				last = b
	if OS.is_debug_build():
		print("[Pueblo] river: %d '#' tiles between water tiles are water in 3D" % made)


func _tp(c: float, r: float) -> Vector2:
	## tile centre (fractional tiles allowed) -> plan metres
	return Vector2(c * 2.0 + 1.0, -(r * 2.0 + 1.0))


func _pick(weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	var x := rng.randi() % total
	for k in weights:
		x -= int(weights[k])
		if x < 0:
			return k
	return ""


# ---------------------------------------------------------------- buildings
## The lots the 2D view draws (GuildMaster WorldView._add_buildings / _add_decor / _add_filler): each building of the map
## (one per origin: player_ < other < house) on its footprint from its origin (data/buildings/<type>.json, the town
## hall's from the map); the decor house lots (decor items of kind "house" whose site has no building here); then the
## '#' tiles still free filled with house lots of the first size of LOT_SIZES that fits, scanning row by row (the decor
## yards stay yards). Every '#' tile no lot claims is a yard (fenced, not walkable, free for props).
const LOT_SIZES := [Vector2i(3, 4), Vector2i(4, 3), Vector2i(3, 3)]  # GuildMaster data/view.json filler.lot_sizes
var _fp_cache := {}


func _components() -> Array:
	var seen := {}
	var out := []
	for r in H:
		for c in W:
			if _t(c, r) != "#" or seen.has(Vector2i(c, r)):
				continue
			var stack := [Vector2i(c, r)]
			seen[Vector2i(c, r)] = true
			var tiles := {}
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				tiles[p] = true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if _t(q.x, q.y) == "#" and not seen.has(q):
						seen[q] = true
						stack.append(q)
			out.append(tiles)
	return out


func _footprint_of(type: String) -> Vector2i:
	## [cols, rows] of a building type as the 2D draws it: GuildMaster data/buildings/<type>.json "footprint" (next to the
	## map's data/maps/), the town hall's from the map; 3x3 if unknown
	if type == "town_hall":
		var f: Array = mapd.get("town_hall", {}).get("footprint", [3, 3])
		return Vector2i(int(f[0]), int(f[1]))
	if not _fp_cache.has(type):
		var fp := Vector2i(3, 3)
		var path := "%s/buildings/%s.json" % [_map_path.get_base_dir().get_base_dir(), type]
		if FileAccess.file_exists(path):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary and (d as Dictionary).get("footprint") is Array:
				fp = Vector2i(int(d.footprint[0]), int(d.footprint[1]))
		elif OS.is_debug_build():
			print("[Pueblo] no %s: %s takes a 3x3 footprint" % [path, type])
		_fp_cache[type] = fp
	return _fp_cache[type]


func _rect_free(free: Dictionary, rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not free.has(Vector2i(x, y)):
				return false
	return true


func _claim(free: Dictionary, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			free.erase(Vector2i(x, y))


func _entries() -> Array:
	## [origin, type, door, rank] of every building entry of the map (+ the town hall); rank: player_ < other < house
	var out := []
	for id in mapd.buildings:
		var b: Dictionary = mapd.buildings[id]
		var rank := 0 if String(id).begins_with("player_") else (2 if b.type == "house" else 1)
		out.append([Vector2i(int(b.origin[0]), int(b.origin[1])), String(b.type), Vector2i(int(b.door[0]), int(b.door[1])), rank, String(id)])
	var hall: Dictionary = mapd.get("town_hall", {})
	if not hall.is_empty():
		out.append([Vector2i(int(hall.origin[0]), int(hall.origin[1])), "town_hall",
			Vector2i(int(hall.service[0]), int(hall.service[1])), -1, "town_hall"])
	# what the sim builds on a plot during the trace (no entry of the map stands on that origin): its lot is there from
	# the start, empty until the works begin (_plots_of_sim made its tiles '#')
	var have := {}
	for e in out:
		have[e[0]] = true
	for o: Vector2i in sim_buildings:
		var sb: Dictionary = sim_buildings[o]
		if have.has(o) or not sb.has("type") or (sb.get("door", []) as Array).size() != 2:
			continue
		out.append([o, String(sb.type), Vector2i(int(sb.door[0]), int(sb.door[1])), 1, String(sb.get("id", ""))])
	return out


func _plots_of_sim() -> void:
	## A building of the trace on tiles that are not '#' in the map (a plot on grass bought and built during the game):
	## its footprint becomes '#' here, a lot like the others (earth, fenced, nobody walks it once it is built)
	var have := {}
	for id in mapd.get("buildings", {}):
		have[Vector2i(int(mapd.buildings[id].origin[0]), int(mapd.buildings[id].origin[1]))] = true
	for o: Vector2i in sim_buildings:
		var sb: Dictionary = sim_buildings[o]
		var fp: Array = sb.get("footprint", [])
		if have.has(o) or fp.size() != 2 or String(sb.get("type", "")) == "town_hall":
			continue
		var made := 0
		for y in range(o.y, o.y + int(fp[1])):
			for x in range(o.x, o.x + int(fp[0])):
				if y >= 0 and y < H and x >= 0 and x < W and grid[y][x] != "#":
					var row: String = grid[y]
					row[x] = "#"
					grid[y] = row
					made += 1
		if OS.is_debug_build():
			print("[Pueblo] %s of the sim (%s) at %s, footprint %s: not a building of the map, %d of its tiles made '#'" % [
				sb.get("id", "?"), sb.get("type", "?"), o, fp, made])


func _building_rects() -> Array:
	## [{box: Rect2i (the 2D footprint), type, door: Vector2i or (-1,-1), side}] and fills yard_tiles with the '#' tiles
	## no lot claims
	var free := {}
	for r in H:
		for c in W:
			if _t(c, r) == "#":
				free[Vector2i(c, r)] = true
	var out := []
	# 1. the buildings of the map on their footprint
	var by_origin := {}  # origin -> best entry
	for e in _entries():
		if free.has(e[0]) and (not by_origin.has(e[0]) or int(e[3]) < int(by_origin[e[0]][3])):
			by_origin[e[0]] = e
	var origins := by_origin.keys()
	origins.sort()
	for o in origins:
		var e: Array = by_origin[o]
		var rect := Rect2i(o, _footprint_of(e[1]))
		if not _rect_free(free, rect):
			# footprint off the '#' block or over another lot: the part of it that is still free from its origin
			var w := 0
			while w < rect.size.x and free.has(o + Vector2i(w, 0)):
				w += 1
			var h := 0
			while h < rect.size.y and _rect_free(free, Rect2i(o, Vector2i(w, h + 1))):
				h += 1
			if OS.is_debug_build():
				print("[Pueblo] %s at %s: footprint %s not all free '#', takes %dx%d" % [e[1], o, rect.size, w, h])
			rect = Rect2i(o, Vector2i(w, h))
			if w == 0 or h == 0:
				continue
		_claim(free, rect)
		out.append({box = rect, type = e[1], door = e[2], side = _side_of(rect, e[2]), id = e[4]})
	# 1b. the church, on the block the atrium fronts (before the decor and filler houses take it)
	var temple := _temple_lot(free)
	if not temple.is_empty():
		_claim(free, temple.box)
		out.append({box = temple.box, type = "church", door = Vector2i(-1, -1), side = temple.side})
	# 2. the decor lots: house lots, and the yards (they keep the filler houses off those tiles)
	var sites: Dictionary = mapd.get("buildings", {})
	var n_decor := 0
	for it in mapd.get("decor", {}).get("items", []):
		var kind := String(it.get("kind", ""))
		if not kind in ["house", "yard", "single"] or not it.has("at"):
			continue
		var site := String(it.get("site", ""))
		if site != "" and sites.has(site) and by_origin.has(Vector2i(int(sites[site].origin[0]), int(sites[site].origin[1]))):
			continue  # a site's lots dress its plot only while the plot has no building
		var sz: Array = it.get("size", [1, 1])
		var rect := Rect2i(int(it.at[0]), int(it.at[1]), int(sz[0]), int(sz[1]))
		if not _rect_free(free, rect):
			continue
		_claim(free, rect)
		if kind == "house":
			var f: Array = it.get("facing", [0, 1])
			var side := "south" if float(f[1]) > 0 else ("north" if float(f[1]) < 0 else ("east" if float(f[0]) > 0 else "west"))
			out.append({box = rect, type = "house", door = Vector2i(-1, -1), side = side})
			n_decor += 1
		else:
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					yard_tiles[Vector2i(x, y)] = true
	# 3. filler house lots on the free tiles, reading order, first size that fits (a lone tile is no lot)
	var keys := free.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var n_fill := 0
	for k in keys:
		if not free.has(k):
			continue
		for sz in LOT_SIZES:
			var rect := Rect2i(k, sz)
			if _rect_free(free, rect):
				_claim(free, rect)
				out.append({box = rect, type = "house", door = Vector2i(-1, -1), side = _road_side(rect)})
				n_fill += 1
				break
	for k in free:
		yard_tiles[k] = true
	if OS.is_debug_build():
		print("[Pueblo] lots as in 2D: %d buildings on their footprint, %d decor house lots, %d filler lots, %d yard tiles" % [
			origins.size(), n_decor, n_fill, yard_tiles.size()])
	return out


func _temple_lot(free: Dictionary) -> Dictionary:
	## {box, side} of the church site, {} if the map has none: the sim holds mass on the "atrium" social point, so the
	## church is the '#' block that atrium fronts, when it is a whole free rectangle (no building of the map on it) of
	## 6 x 6 m or more. The side is the one that looks at the atrium.
	var centre := Vector2.ZERO
	var n := 0
	for sp in mapd.get("social_points", []):
		if String(sp.get("kind", "")) == "atrium":
			for s in sp.slots:
				centre += Vector2(float(s[0]) + 0.5, float(s[1]) + 0.5)
				n += 1
	if n == 0:
		return {}
	centre /= n
	var best := {}
	var bd := 3.5  # tiles from the atrium to the block
	for comp: Dictionary in _components():
		var rect := Rect2i()
		var first := true
		var all_free := true
		for t: Vector2i in comp:
			rect = Rect2i(t, Vector2i.ONE) if first else rect.expand(t).expand(t + Vector2i.ONE)
			first = false
			all_free = all_free and free.has(t)
		if not all_free or rect.get_area() != comp.size() or rect.size.x < 3 or rect.size.y < 3:
			continue
		var near := Vector2(clampf(centre.x, rect.position.x, rect.end.x), clampf(centre.y, rect.position.y, rect.end.y))
		var dist := near.distance_to(centre)
		if dist < bd and dist > 0.0:
			bd = dist
			var side := "south" if centre.y >= rect.end.y else ("north" if centre.y <= rect.position.y else ("east" if centre.x >= rect.end.x else "west"))
			best = {box = rect, side = side}
	if OS.is_debug_build():
		print("[Pueblo] church site: atrium at tile %s -> %s" % [centre, best if not best.is_empty() else "no free block beside it"])
	return best


func _side_of(box: Rect2i, door: Vector2i) -> String:
	if door.y >= box.end.y:
		return "south"
	if door.y < box.position.y:
		return "north"
	if door.x >= box.end.x:
		return "east"
	return "west"


func _road_side(box: Rect2i) -> String:
	var best := "south"
	var most := -1
	var sides := {"south": [], "north": [], "east": [], "west": []}
	for c in range(box.position.x, box.end.x):
		sides.north.append(Vector2i(c, box.position.y - 1))
		sides.south.append(Vector2i(c, box.end.y))
	for r in range(box.position.y, box.end.y):
		sides.west.append(Vector2i(box.position.x - 1, r))
		sides.east.append(Vector2i(box.end.x, r))
	for s in sides:
		var n := 0
		for p in sides[s]:
			for k in 3:
				var q: Vector2i = p + {"south": Vector2i(0, k), "north": Vector2i(0, -k), "east": Vector2i(k, 0), "west": Vector2i(-k, 0)}[s]
				if _t(q.x, q.y) in ["=", ",", "P", "S"]:
					n += 3 - k
		if n > most:
			most = n
			best = s
	return best


func _fit(len_m: int, dep_m: int) -> Dictionary:
	## {w, d, ridge} of the widest house that fits a lot of len_m along its front and dep_m deep: the kit's roofs (4, 6
	## and 8 m of span), ours (8x6 and 10x8, kit/modules) and, on wide shallow lots, a kit roof turned so its ridge runs
	## along the front (ridge "x": 12x8, 14x8, 10x6, 12x6...). {} if nothing fits.
	for ww: int in [14, 12, 10, 8, 6, 4]:
		if ww > len_m:
			continue
		if ww < 10:
			var dd := _depth_for(ww, dep_m)
			if dd > 0:
				return {w = ww, d = dd, ridge = "y"}
			continue
		if _depth_for(ww, dep_m) > 0:
			return {w = ww, d = _depth_for(ww, dep_m), ridge = "y"}
		for dd: int in [8, 6]:
			if dd <= dep_m and HouseBuilder._exists("Roof_RoundTiles_%dx%d" % [dd, ww]):
				return {w = ww, d = dd, ridge = "x"}
	return {}


func _depth_for(w: int, avail: int) -> int:
	var opts := {4: [4, 6, 8], 6: [4, 6, 8, 10, 12, 14], 8: [6, 8, 10, 12, 14], 10: [8]}
	var best := -1
	for o in opts.get(w, []):
		if int(o) <= avail:
			best = int(o)
	return best


## Guild colours: shop awnings, shields and market stalls share them (every colour is one more material to draw)
const RED := Color(0.62, 0.16, 0.12)
const BLUE := Color(0.16, 0.3, 0.55)
const GREEN := Color(0.2, 0.42, 0.24)
const OCHRE := Color(0.72, 0.5, 0.16)


func _style(type: String, w: int, d: int, site := {}) -> Dictionary:
	## The def of a building of the town. site: what the lot gives this house (from _town_buildings): door_cell, ridge,
	## yard {side: [bool per cell]} (the cells of each wall with a yard tile of the lot behind them: a porch or a shed
	## only goes over a yard), level (1-3), wealth (houses: humble | well | noble), stage / stage_floor (building site).
	## The look comes from the table of types (BuildingTypes, data/building_types.json; docs/construccion.md); a type the
	## table does not have, or `--tipos=no`, keeps the plain house with the modules of _trade_modules. What the interior
	## in place of a type asks of its shell (data/interiors/<type>_sitio.json) rules over the table.
	var id := BuildingTypes.type_id(type, String(site.get("wealth", "humble")))
	var by_type: bool = BuildingTypes.types().has(id) and not "--tipos=no" in OS.get_cmdline_user_args()
	var dice: Dictionary = site.get("dice", {})  # seed and palette of the house when it is built again
	var plain := {}
	if dice.is_empty() or not by_type:
		plain = _style_plain(type, w, d, site)  # also keeps the town's dice where they were
		dice = {seed = plain.seed, palette = plain.palette}
	if not by_type:
		return plain
	var extra := {}
	if site.get("ridge", "y") == "x":
		extra.ridge = "x"
	if site.has("door_cell"):
		extra.door_cell = int(site.door_cell)
	if type == "house":
		extra.palette = dice.palette  # the houses keep the town's mix of plaster, tiles, timber and stone
	var level := int(site.get("level", 2))
	var yard: Dictionary = site.get("yard", {})
	var stage := String(site.get("stage", ""))
	if stage != "":
		extra.stage = stage
		extra.stage_floor = int(site.get("stage_floor", 0))
	var def := BuildingTypes.def_for(id, level, int(dice.seed), w, d, yard, extra)
	def.erase("court")  # the town fences every yard itself (_yard_fences)
	def["_level"] = level
	def["_dice"] = dice
	# the interior in place of this type at this level (SituShell, docs/interior3d.md): the def takes what it asks of
	# the shell when the house is the one it was drawn for (size, storeys, door cell, yard on the side it counts on)
	# (a copy: SituShell.apply turns the data into its mirror image when that is the one that fits)
	if stage != "":
		return def
	var sd := situ_for(id, level).duplicate(true)
	var why := "no interior drawn for %s level %d" % [id, level] if sd.is_empty() else SituShell.apply(def, sd, yard)
	if why != "":
		# the interior of its level is drawn for another house (the lot gives a smaller one): the one of the nearest
		# level drawn for this very house (the tavern of level 2 on a 6 m lot is the 6 x 6 m house of the level 1 inside)
		for l: int in [level - 1, level + 1, level - 2, level + 2]:
			var alt := situ_for(id, l).duplicate(true) if l >= 1 and l <= 3 else {}
			if alt.is_empty() or int(alt.shell.w) != w or int(alt.shell.d) != d or int(alt.shell.floors) != int(def.floors):
				continue
			if SituShell.apply(def, alt, yard) == "":
				if OS.is_debug_build():
					print("[Pueblo] interior in place: %s level %d takes the interior of level %d (%s)" % [id, level, l, why])
				sd = alt
				why = ""
				break
	if why == "":
		def["_situ_data"] = sd
		if (sd.shell as Dictionary).has("porch"):
			def.erase("yard")  # the ground under its shed belongs to the interior
	else:
		def["_situ_why"] = why
	return def


func _style_plain(type: String, w: int, d: int, site := {}) -> Dictionary:
	var plaster: String = ["plaster_ocre", "plaster_rosa", "plaster_azul", "plaster_verde", "", "", ""][rng.randi() % 7]
	var pal := {plaster = plaster, roof = _pick(ROOF_W), wood = ["", "", "wood_nogal", "wood_roja"][rng.randi() % 4],
		stone = ["", "stone_calida", "stone_oscura"][rng.randi() % 3]}
	var floors := 2
	match type:
		"tavern_inn", "town_hall":
			floors = 3
		"house":
			floors = 1 if w == 4 and rng.randf() < 0.6 else 2
	var walls := ["UnevenBrick"]
	for f in range(1, floors):
		walls.append("Plaster")
	if floors == 1 and rng.randf() < 0.4:
		walls = ["Plaster"]
	var def := {seed = rng.randi(), w = w, d = d, floors = floors, walls = walls,
		floors_mat = ["Floor_Brick", "Floor_WoodDark", "Floor_WoodDark"],
		corner = "Corner_ExteriorWide_Wood" if floors == 3 else "Corner_Exterior_Wood",
		window = "Window_Wide_Flat" if floors == 1 else "Window_Wide_Round", grid = true, shutters = true,
		side_windows = 0.5, chimneys = [0.5] if rng.randf() < 0.7 else [], palette = pal, round_door = floors > 1}
	if site.get("ridge", "y") == "x":
		def.ridge = "x"
	if site.has("door_cell"):
		def.door_cell = int(site.door_cell)
	_trade_modules(def, type, site.get("yard", {}))
	var sd := situ_for(type, 0).duplicate(true)  # `--tipos=no`: only the types with an interior for any level (the forge)
	if not sd.is_empty() and ("--tipos=no" in OS.get_cmdline_user_args() or not BuildingTypes.types().has(type)):
		if SituShell.apply(def, sd, site.get("yard", {})) == "":
			def["_situ_data"] = sd
	return def


# ---------------------------------------------------------------- level, wealth and building works
## Level of look (1-3) of a building, by data:
## - a trade or a farm: 2 when its plot is well placed (plots[].location >= PRIME_LOCATION) or it is one of the town's own
##   buildings (no plot: town hall, armory, tavern), else 1; one more for every LEVEL_UPGRADES finished upgrades the
##   sim has for it (trace buildings[].tl, tools/sim_trace.gd).
## - a house: its wealth by the place of its plot (well from WELL_LOCATION, noble on a lot of 12 x 8 m or more) and its
##   level by how far into that band it is. A lot without a plot (decor and filler houses): a value by its place.
## - a house of a family that works the fields (the trace) or that touches a field is a farm.
## Building works: a building the sim has under construction at the start of the trace shows the stage its progress
## gives (stakes < 20 % < foundation < 45 % < frame of the ground floor < 75 % < frame of the top floor); upgrade works
## that end in a new level show that level in frame over the storeys it had. Read once, when the town is built.
## `--nivel=2` (all), `--nivel=forge:3,workshop_tailor:1` (by type, map id or 3D name) and
## `--obra=<type | map id | 3D name>:<stakes|foundation|frame|frame1|frame2>[,...]` override them;
## `--tipo=<map id | 3D name>:<type>[,...]` gives a building the look of another type (the town has 8 of the 15).
const PRIME_LOCATION := 0.55
const WELL_LOCATION := 0.55
const LEVEL_UPGRADES := 3
const STAGES := ["stakes", "foundation", "frame", "frame1", "frame2"]


func _arg_pairs(prefix: String) -> Dictionary:
	## "--nivel=a:1,b:2" -> {a: "1", b: "2"}; "--nivel=2" -> {"*": "2"}
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with(prefix):
			continue
		for part in a.trim_prefix(prefix).split(",", false):
			if part.contains(":"):
				out[part.get_slice(":", 0)] = part.get_slice(":", 1)
			else:
				out["*"] = part
	return out


func _look_of(b: Dictionary) -> Dictionary:
	## {type (the look: "farm" for a farmers' house), level, wealth, stage, stage_floor, why}
	var type: String = b.type
	var id: String = b.get("id", "")
	var box: Rect2i = b.box
	var o := box.position
	var name3d := "%s_%d_%d" % [type, o.x, o.y]
	var loc := -1.0
	var sim: Dictionary = sim_buildings.get(o, {})
	for p in mapd.get("plots", []):
		# its plot: the one of its site in the map or, for what the sim builds on a free plot, the one the trace names
		if (id != "" and String(p.get("site", "")) == id) or (String(sim.get("plot", "")) != "" and String(p.get("id", "")) == String(sim.plot)):
			loc = float(p.get("location", -1.0))
	var out := {type = type, level = 2, wealth = "humble", stage = "", stage_floor = 0, why = ""}
	var tp := _arg_pairs("--tipo=")  # --tipo=house_nw:clinic,house_ne:den: another type's look on a building (to see them all)
	for key in [id, name3d]:
		if tp.has(key) and BuildingTypes.types().has(String(tp[key])):
			out.type = String(tp[key])
			type = out.type
	if type == "house":
		var farm := bool(sim.get("farm", false))
		for t in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			for y in range(box.position.y, box.end.y):
				for x in range(box.position.x, box.end.x):
					if _t(x + t.x, y + t.y) == "f":
						farm = true
		if farm:
			out.type = "farm"
	if out.type == "house":
		var l := loc if loc >= 0.0 else 0.32 + float(absi(hash("%d,%d" % [o.x, o.y])) % 36) / 100.0
		var along := maxi(box.size.x, box.size.y) * 2
		var across := mini(box.size.x, box.size.y) * 2
		if along >= 12 and across >= 8:
			out.wealth = "noble"
			out.level = clampi(1 + int((l - 0.3) / 0.2), 1, 3)
		elif l >= WELL_LOCATION:
			out.wealth = "well"
			out.level = clampi(1 + int((l - WELL_LOCATION) / 0.1), 1, 3)
		else:
			out.level = clampi(1 + int((l - 0.36) / 0.06), 1, 3)
		out.why = "location %.2f%s" % [l, "" if loc >= 0.0 else " (no plot: by its place)"]
	else:
		var ups: Array = sim.get("upgrades", [])
		out.level = clampi((2 if loc < 0.0 or loc >= PRIME_LOCATION else 1) + ups.size() / LEVEL_UPGRADES, 1, 3)
		out.why = "%s, %d upgrades" % ["no plot (the town's)" if loc < 0.0 else "location %.2f" % loc, ups.size()]
		# upgrade works that end in a new level: that level in frame over the storeys it had
		var work: Array = sim.get("work", [])
		if not work.is_empty() and (ups.size() + 1) / LEVEL_UPGRADES > ups.size() / LEVEL_UPGRADES and out.level < 3:
			out.level += 1
			out.stage = "frame"
			out.stage_floor = 9  # the top storey of the new level (_town_buildings clamps it)
			out.why += ", upgrade works to level %d" % out.level
	var cons: Array = sim.get("construction", [])
	if not bool(sim.get("exists", true)):
		out.stage = "empty"
		out.why += ", nothing built yet"
	elif not cons.is_empty():
		var k := clampf((float(sim.get("now", 0)) - float(cons[1])) / maxf(1.0, float(cons[2]) - float(cons[1])), 0.0, 1.0)
		out.stage = "stakes" if k < 0.2 else ("foundation" if k < 0.45 else "frame")
		out.stage_floor = 0 if k < 0.75 else 9
		out.why += ", under construction (%s, %d %%)" % [cons[0], int(k * 100.0)]
	var lv := _arg_pairs("--nivel=")
	for key in ["*", type, out.type, id, name3d]:
		if lv.has(key):
			out.level = clampi(int(lv[key]), 1, 3)
			out.why += ", --nivel"
	var ob := _arg_pairs("--obra=")
	for key in [type, out.type, id, name3d]:
		if ob.has(key) and String(ob[key]) in STAGES:
			var st: String = ob[key]
			out.stage = "frame" if st.begins_with("frame") else st
			out.stage_floor = int(st.trim_prefix("frame")) if st.begins_with("frame") and st != "frame" else 0
			out.why += ", --obra"
	return out


func _size_for(id: String, level: int, len_m: int, dep_m: int) -> Dictionary:
	## {w, d, ridge} of the house of that type and level on a lot of len_m along the door side and dep_m deep: the size the
	## table gives it on its own lot (data/building_types.json: lot + takes), no more than this lot allows
	var all := _fit(len_m, dep_m)
	if not BuildingTypes.types().has(id) or "--tipos=no" in OS.get_cmdline_user_args():
		return all
	var t: Dictionary = BuildingTypes.data().types[id]
	var lot := BuildingTypes.lot_of(id)
	var takes: Array = t.get("takes", BuildingTypes.data().get("takes", [[0, 0]]))
	var take: Array = takes[clampi(level, 1, takes.size()) - 1]
	var f := _fit(mini(len_m, maxi(4, lot.x + int(take[0]))), mini(dep_m, maxi(4, lot.y + int(take[1]))))
	return all if f.is_empty() else f


func _run_of(cells: Array) -> Array:
	## [from, to] of the longest run of true in cells, [] if none
	var best := []
	var s := -1
	for i in cells.size() + 1:
		var on: bool = i < cells.size() and bool(cells[i])
		if on and s < 0:
			s = i
		elif not on and s >= 0:
			if best.is_empty() or i - s > best[1] - best[0] + 1:
				best = [s, i - 1]
			s = -1
	return best


func _porch_on(def: Dictionary, yard: Dictionary, sides: Array, opts: Dictionary, max_cells := 9) -> bool:
	## a lean-to roof on posts (porch, shed) on the first of `sides` whose wall has two cells or more over a yard of the
	## lot (the posts stand 1.9 m out: never on a tile somebody walks). Side walls take the cells nearest the back.
	if int(def.floors) < 2:
		return false  # under the eaves of a one-storey house it does not fit (HouseBuilder would skip it)
	for side: String in sides:
		var run := _run_of(yard.get(side, []))
		if run.is_empty() or run[1] - run[0] < 1:
			continue
		if run[1] - run[0] + 1 > max_cells:
			# cells run left to right seen from outside: the back end of the left wall is its first cell
			run = [run[0], run[0] + max_cells - 1] if side == "left" else [run[1] - max_cells + 1, run[1]]
		var e := {side = side, from = run[0], to = run[1]}
		e.merge(opts)
		def.porch = def.get("porch", []) + [e]
		return true
	return false


func _trade_modules(def: Dictionary, type: String, yard: Dictionary) -> void:
	## What each kind of building adds to the plain house, with our own modules (docs/construccion.md). Data by type:
	## the forge its chimney and a boarded shed, the bakery its oven, the shops their counter windows and an awning in
	## the guild's colour, every trade its sign, the town hall and the rich houses portal, shield and twin windows.
	var n: int = int(def.w) / 2
	var door := HouseBuilder.door_cell(def, n)
	var mr := RandomNumberGenerator.new()  # its own dice: the modules do not shift the colours of the houses after this one
	mr.seed = hash(int(def.seed))
	var beside := []  # the front cells next to the door
	for i in [door - 1, door + 1]:
		if i >= 0 and i < n:
			beside.append(i)
	match type:
		"forge":
			def.chimneys = [{x = 0.45, y = 0.4, piece = "Prop_Chimney_Forge"}]
			def.sign = "Forge"
			_porch_on(def, yard, ["left", "right", "back"], {ends = "boards"}, 2)
		"armory":
			def.shop = {cells = beside, awning = BLUE, sign = "Armory"}
			_porch_on(def, yard, ["back", "left", "right"], {posts = "stone"})
		"carpentry":
			def.sign = "Carpenter"
			_porch_on(def, yard, ["back", "left", "right"], {ends = "boards"})
		"masonry":
			def.sign = "Blank"
			def.walls = ["UnevenBrick", "UnevenBrick"]
			_porch_on(def, yard, ["back", "left", "right"], {posts = "stone"})
		"tailor_shop":
			def.shop = {cells = beside, awning = RED, sign = "Blank"}
		"clinic":
			def.shop = {cells = beside.slice(0, 1), awning = GREEN, sign = "Alchemist"}
		"bakery":
			def.sign = "Grocer"
			for side: String in ["back", "left", "right"]:
				var run := _run_of(yard.get(side, []))
				if not run.is_empty():
					def.oven = {side = side, cell = run[0]}
					break
		"tavern_inn":
			def.sign = "Tavern"
			def.balcony = [{floor = int(def.floors) - 1, from = 0 if n <= 3 else 1, to = n - 1 if n <= 3 else n - 2}]
			_porch_on(def, yard, ["back"], {posts = "stone"})
		"town_hall", "bank":
			def.portal = true
			def.shield = BLUE if type == "town_hall" else OCHRE
			def.window = "Window_Twin"
			def.chimneys = [0.6, -0.6]
			if int(def.floors) > 2:
				def.balcony = [{floor = 2, from = maxi(0, door - (1 if door == n - 1 else 0)), to = mini(n - 1, door + (0 if door == n - 1 else 1))}]
			if type == "town_hall":
				def.dovecote = 0.0
		"farm":
			def.dovecote = -0.5
			_porch_on(def, yard, ["left", "right", "back"], {}, 2)
		"house":
			# plain houses keep their yards for the beds and sacks the 2D draws there (a shed leaves no room for them)
			if int(def.w) >= 8 and int(def.floors) >= 2:
				# a rich house: stone portal with the family shield, twin windows
				def.portal = true
				def.shield = [RED, BLUE, GREEN, OCHRE][mr.randi() % 4]
				def.window = "Window_Twin"


func _town_buildings() -> void:
	## one 3D house per 2D lot: the widest module (4 to 14 m along the door side: _fit) that fits the footprint, as deep
	## as it allows, with its door on the tile of the 2D door (the house slides along the lot and, when it fills it, the
	## door takes the cell that stands there); the rest of the footprint is yard. The church takes its own site (_church).
	var lots := _building_rects()
	_mill()  # before the houses: the lot beside it leaves a gap (the mill stands on its own, not as the wing of a house)
	for b in lots:
		_make_house(b)
	# '#' tiles not under any 3D house are yards too (the house is narrower or shallower than its rectangle)
	for r in H:
		for c in W:
			if _t(c, r) == "#" and _house_at_plan(_tp(c, r), -0.2) == null:
				yard_tiles[Vector2i(c, r)] = true
	for h in houses:
		if not h.get_meta("type") in ["house", "church", "mill"] and not h.has_meta("stage"):
			_trade_props(h, h.get_meta("type"))
	if OS.is_debug_build():
		print("[Pueblo] %d buildings, %d yard tiles" % [houses.size(), yard_tiles.size()])


func look_key(look: Dictionary) -> String:
	## what of a lot's look changes its house: when this changes the house is built again (rebuild_house)
	return "%s|%d|%s|%s|%d" % [look.type, int(look.level), look.wealth, look.stage, int(look.stage_floor)]


func _make_house(b: Dictionary, dice := {}) -> Node3D:
	## the 3D house of a lot ({box, type, door, side, id}: _building_rects) as its look says now (_look_of: level, wealth,
	## building works), added to the town and to `houses`. null for a lot no module fits (and for the church's).
	var box: Rect2i = b.box
	var side: String = b.side
	var door: Vector2i = b.door
	var kind: String = b.type
	if kind == "church":
		_church(b)
		return null
	var look := _look_of(b)
	var style_type: String = look.type
	var along_x := side == "south" or side == "north"
	var len_m := (box.size.x if along_x else box.size.y) * 2
	var dep_m := (box.size.y if along_x else box.size.x) * 2
	var door_along := len_m / 2.0
	if door.x >= 0:
		door_along = (door.x * 2 + 1 - box.position.x * 2) if along_x else (door.y * 2 + 1 - box.position.y * 2)
	# beside the mill: the house keeps 2 m off that end of its lot (a strip of yard between the two)
	var trim_lo := 0
	var trim_hi := 0
	if mill != null and mill.has_meta("box") and len_m >= 6:
		var mb: Rect2i = mill.get_meta("box")
		var a0 := box.position.x if along_x else box.position.y
		var a1 := box.end.x if along_x else box.end.y
		var m0 := mb.position.x if along_x else mb.position.y
		var m1 := mb.end.x if along_x else mb.end.y
		var overlap := (mb.position.y < box.end.y and mb.end.y > box.position.y) if along_x else (mb.position.x < box.end.x and mb.end.x > box.position.x)
		if overlap and m0 == a1 and door_along < len_m - 2:
			trim_hi = 2
		elif overlap and m1 == a0 and door_along > 2:
			trim_lo = 2
		if trim_lo + trim_hi > 0 and OS.is_debug_build():
			print("[Pueblo] %s lot %s beside the mill: its house keeps 2 m off that side" % [kind, box])
	len_m -= trim_lo + trim_hi
	door_along -= trim_lo
	var type_id := BuildingTypes.type_id(style_type, look.wealth)
	var fit := _size_for(type_id, look.level, len_m, dep_m)
	var tipos: bool = BuildingTypes.types().has(type_id) and not "--tipos=no" in OS.get_cmdline_user_args()
	var sd0 := (situ_for(type_id, look.level) if tipos else situ_for(style_type, 0)) if look.stage == "" else {}
	if not sd0.is_empty() and int(sd0.shell.w) <= len_m and int(sd0.shell.d) <= dep_m:
		var fs := _fit(int(sd0.shell.w), int(sd0.shell.d))  # the house its interior in place is drawn for
		if not fs.is_empty() and int(fs.w) == int(sd0.shell.w) and int(fs.d) == int(sd0.shell.d):
			fit = fs
	if fit.is_empty():
		if OS.is_debug_build():
			print("[Pueblo] %s lot %s: no kit module fits %dx%d m, left as yard" % [kind, box, len_m, dep_m])
		return null
	var w: int = fit.w
	var d: int = fit.d
	var whole: bool = not sd0.is_empty() and int(sd0.shell.d) == d and int(sd0.shell.w) == w
	if TRADE_PROPS.has(kind) and w == len_m and d == dep_m and d >= 8 and not whole:
		d -= 2  # a trade whose footprint is all house: a 2 m work yard at the back for its props (the tavern's terrace)
	# the door: cell n/2 of the front, at local x `off`; along the lot it stands at cursor + w/2 +- off
	var n_cells := w / 2
	var cell := n_cells / 2
	if whole and (sd0.shell as Dictionary).has("door_cell"):
		cell = clampi(int(sd0.shell.door_cell), 0, n_cells - 1)  # the door where the interior has it, if the lot lets it
	var cell0 := cell
	var off := -w / 2.0 + 1.0 + 2.0 * cell
	var sgn := 1.0 if side in ["south", "west"] else -1.0
	var cursor := clampi(int(round((door_along - w / 2.0 - sgn * off) / 2.0)) * 2, 0, len_m - w)
	if door.x >= 0:
		# the house cannot slide any further: the door goes to the cell that stands on the 2D door
		var want := (door_along - cursor - w / 2.0) * sgn
		cell = clampi(int(round((want + w / 2.0 - 1.0) / 2.0)), 0, n_cells - 1)
		off = -w / 2.0 + 1.0 + 2.0 * cell
	var seg := w
	var x0 := box.position.x * 2.0 + (trim_lo if along_x else 0)
	var x1 := box.end.x * 2.0
	var y_top := -box.position.y * 2.0 - (0 if along_x else trim_lo)
	var y_bot := -box.end.y * 2.0
	var c := Vector2.ZERO
	var rot := 0.0
	match side:
		"south":
			c = Vector2(x0 + cursor + seg / 2.0, y_bot + d / 2.0)
		"north":
			c = Vector2(x0 + cursor + seg / 2.0, y_top - d / 2.0)
			rot = 180.0
		"east":
			c = Vector2(x1 - d / 2.0, y_top - cursor - seg / 2.0)
			rot = 90.0
		"west":
			c = Vector2(x0 + d / 2.0, y_top - cursor - seg / 2.0)
			rot = 270.0
	var site := {ridge = fit.ridge, yard = _yard_cells(w, d, c, rot, box), level = look.level, wealth = look.wealth}
	if not dice.is_empty():
		site.dice = dice  # a house built again (rebuild_house): the colours and the seed it had
	if cell != n_cells / 2 or cell != cell0:
		site.door_cell = cell
	if look.stage != "":
		site.stage = look.stage
		site.stage_floor = look.stage_floor
	var def := _style(style_type, w, d, site)
	if def.has("stage"):
		def.stage_floor = clampi(int(def.get("stage_floor", 0)), 0, int(def.floors) - 1)
	def.name = "%s_%d_%d" % [kind, box.position.x, box.position.y]
	var h: Node3D
	if look.stage == "empty":
		h = Node3D.new()  # a lot the sim has nothing on yet: bare ground until its works begin (rebuild_house)
		h.name = def.name
		def.erase("_situ_data")
		def.erase("_situ_why")
	else:
		h = HouseBuilder.build(def)
	var sd: Dictionary = def.get("_situ_data", {})
	var leaves := SituShell.edit(h, def, sd) if not sd.is_empty() else []
	if look.stage != "empty":
		HouseBuilder.bake(h)
	if not sd.is_empty():
		SituShell.finish(h, def, sd, leaves)  # the door leaves stay pieces of their own (SituCut opens them); meta "interior"
	elif def.has("_situ_why"):
		h.set_meta("no_interior", String(def._situ_why))
	h.position = HouseBuilder.plan_to_godot(Vector3(c.x, c.y, 0))
	h.rotation.y = deg_to_rad(rot)
	h.set_meta("wd", Vector2(w, d))
	h.set_meta("type", kind)
	h.set_meta("box", box)
	h.set_meta("door_x", off)
	h.set_meta("look", style_type)
	h.set_meta("wealth", String(look.wealth))
	h.set_meta("map_id", String(b.get("id", "")))
	h.set_meta("level", int(def.get("_level", 0)))
	h.set_meta("top", 1.0 + 3.0 * int(def.floors))
	if def.has("stage"):
		h.set_meta("stage", String(def.stage))
	h.set_meta("lot", b)
	h.set_meta("dice", def.get("_dice", {}))
	h.set_meta("look_key", look_key(look))
	add_child(h)
	houses.append(h)
	var ob0 := seat_obstacles.size()
	if look.stage != "empty":
		_module_spots(h, def)
	else:
		h.set_meta("lantern_side", 0.0)
	h.set_meta("obstacles", seat_obstacles.slice(ob0))
	if not sd.is_empty():
		_shell_site(h, def, sd)
	if OS.is_debug_build():
		print("[Pueblo] %s on 2D footprint %s (%dx%d m, door %s): %s level %d (%s)%s, house %dx%d m of %d floors at %.0f m along, door cell %d%s%s" % [
			def.name, box, len_m, dep_m, side, type_id, int(def.get("_level", 0)), look.why,
			", stage %s" % def.stage if def.has("stage") else "", w, d, int(def.floors), cursor, cell, ", ridge x" if fit.ridge == "x" else "", _modules_txt(def)])
		print("[Pueblo]   interior in place of %s: %s" % [def.name, String(sd._path).get_file() if not sd.is_empty() else "none (%s)" % def.get("_situ_why", "building site")])
	return h


## A house built again where it stands, when the sim finishes an upgrade that changes its level of look or its works
## go on to the next stage (sim3d.gd calls it as the trace plays): only that house. The lot, the colours and the seed
## are the ones it had (metas "lot", "dice"); its pieces are styled and merged like the others' (opt3d: one mesh per
## house + its glass). What stands in its yard is not moved: the fences, the props and the trade's things stay where
## the first house left them. Returns the new house (null if its look is the same).
var rebuild_ms := {}  # house name -> [ms of the last rebuilds]
var merge_ms := {}    # house name -> [ms of merging its pieces, the frame after]


func rebuild_house(old: Node3D) -> Node3D:
	if not old.has_meta("lot"):
		return null
	var b: Dictionary = old.get_meta("lot")
	var key := look_key(_look_of(b))
	if key == String(old.get_meta("look_key", "")):
		return null
	var t0 := Time.get_ticks_usec()
	var at := houses.find(old)
	houses.erase(old)
	for ob in old.get_meta("obstacles", []):
		seat_obstacles.erase(ob)
	var opt := preload("res://game/world3d/town/opt3d.gd")
	for mi in opt._meshes_any(old, []):
		_orig.erase(mi)  # set_style would touch freed nodes
	for meta_key in ["opt_house_sources", "opt_house_chunks", "opt_house_glass"]:
		if has_meta(meta_key):
			var keep := []
			for n in get_meta(meta_key):
				if is_instance_valid(n) and not old.is_ancestor_of(n):
					keep.append(n)
			set_meta(meta_key, keep)
	remove_child(old)
	old.queue_free()
	var t1 := Time.get_ticks_usec()
	var h := _make_house(b, old.get_meta("dice", {}))
	if h == null:
		return null
	houses.erase(h)
	houses.insert(clampi(at, 0, houses.size()), h)
	var t2 := Time.get_ticks_usec()
	_collect_materials(h)
	for mi in opt._meshes_any(h, []):
		var mats: Array = _orig.get(mi, [])
		for i in mats.size():
			(mi as MeshInstance3D).set_surface_override_material(i, _variant(mats[i], style))
	var t3 := Time.get_ticks_usec()
	# its pieces are merged on the next frame (it is drawn by its pieces for one frame: the same picture): building and
	# merging are about half of the cost each, and this way no frame carries both
	if has_meta("opt3d") and opt.active.get("houses", false):
		_opt_later(h)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if not rebuild_ms.has(String(h.name)):
		rebuild_ms[String(h.name)] = []
	rebuild_ms[String(h.name)].append(snappedf(ms, 0.1))
	if OS.is_debug_build():
		print("[Pueblo] %s built again in %.1f ms (old out %.1f, build and bake %.1f, style %.1f): %s -> %s" % [h.name, ms,
			(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, old.get_meta("look_key", "?"), key])
	return h


func _opt_later(h: Node3D) -> void:
	await get_tree().process_frame
	if not is_instance_valid(h) or not h.is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	_opt_house(h)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if not merge_ms.has(String(h.name)):
		merge_ms[String(h.name)] = []
	merge_ms[String(h.name)].append(snappedf(ms, 0.1))
	if OS.is_debug_build():
		print("[Pueblo] %s merged in %.1f ms (the frame after it was built again)" % [h.name, ms])
	_house_merged(h)


func _house_merged(_h: Node3D) -> void:
	pass  # sim3d.gd: its window glass is the merged one now


func _opt_house(h: Node3D) -> void:
	## what opt3d does to every house when the town is built (_merge_houses, lods), for one: its pieces in one mesh with
	## a surface per material and its window glass in another, the pieces hidden (the cutaway and SituCut show them)
	var opt := preload("res://game/world3d/town/opt3d.gd")
	var tools := {}
	var mats := {}
	var g := {tools = {}, mats = {}}
	var hinv := h.global_transform.affine_inverse()
	var mine := []
	for mi: MeshInstance3D in opt._meshes_any(h, []):
		if not mi.is_visible_in_tree():
			continue
		opt._append(mi, hinv * mi.global_transform, self, tools, mats, g, hinv * mi.global_transform)
		mine.append(mi)
	var mm: MeshInstance3D = opt._commit(tools, mats, h, "merged", self)
	if mm:
		mm.set_meta("opt_house", true)
		if opt.active.get("lods", false) and opt._tri_count(mm.mesh) >= 1500:
			# its LODs are worked out on another thread (they are most of the cost and only matter from afar): the house
			# shows at full detail for the few frames that takes
			var src: ArrayMesh = mm.mesh
			WorkerThreadPool.add_task(func() -> void:
				var lod: ArrayMesh = opt.with_lods(src)
				_lods_ready.call_deferred(mm, src, lod))
		set_meta("opt_house_chunks", get_meta("opt_house_chunks", []) + [mm])
	var gmi: MeshInstance3D = opt._commit(g.tools, g.mats, h, "glass", self)
	if gmi:
		gmi.set_meta("opt_glass", true)
		set_meta("opt_house_glass", get_meta("opt_house_glass", []) + [gmi])
	for mi: MeshInstance3D in mine:
		mi.visible = false
	set_meta("opt_house_sources", get_meta("opt_house_sources", []) + mine)
	if cutaway:
		opt.house_sources(self, true)


func _lods_ready(mm: MeshInstance3D, src: ArrayMesh, lod: ArrayMesh) -> void:
	if not is_instance_valid(mm) or mm.mesh != src:
		return  # built again meanwhile
	var over := []
	for i in src.get_surface_count():
		over.append(mm.get_surface_override_material(i))
	mm.mesh = lod
	for i in mini(over.size(), lod.get_surface_count()):
		mm.set_surface_override_material(i, over[i])


func _modules_txt(def: Dictionary) -> String:
	var out := []
	for k in ["shop", "display", "sign", "porch", "balcony", "oven", "dovecote", "portal", "shield", "plinth", "tower", "barn", "loft", "hatch", "herbs", "cloth", "grille", "yard"]:
		if def.has(k):
			out.append(k)
	for cx in def.get("chimneys", []):
		if cx is Dictionary:
			out.append(String(cx.get("piece", "Prop_Chimney")))
	return "" if out.is_empty() else "; modules: " + ", ".join(out)


func _local_plan(c: Vector2, rot: float, p: Vector2) -> Vector2:
	## a point of a house's own plan (x right, y back, the front at -y) -> town plan
	return c + p.rotated(deg_to_rad(rot))


func _yard_cells(w: int, d: int, c: Vector2, rot: float, box: Rect2i) -> Dictionary:
	## side -> [bool per cell, left to right from outside]: the tile behind that wall cell is a yard of this lot (a '#'
	## tile of the lot the house leaves free, or one no lot claims), so a porch may stand on it
	var house := Rect2(c - (Vector2(w, d) if is_zero_approx(fmod(rot, 180.0)) else Vector2(d, w)) / 2.0, Vector2(w, d) if is_zero_approx(fmod(rot, 180.0)) else Vector2(d, w))
	var out := {}
	for side: String in HouseBuilder.SIDES:
		var cells := []
		for cell: Vector2 in HouseBuilder._wall_cells(w, d, side):
			var p := _local_plan(c, rot, cell + (HouseBuilder.OUTWARD[side] as Vector2) * 1.0)
			var t := Vector2i(floori(p.x / 2.0), floori(-p.y / 2.0))
			cells.append(_t(t.x, t.y) == "#" and not house.has_point(p) and (box.has_point(t) or yard_tiles.has(t)))
		out[side] = cells
	return out


func _module_spots(h: Node3D, def: Dictionary) -> void:
	## What the modules of a house put on the ground, for whoever places props or walks by: the porch posts (no prop on
	## them: _post_spots), the place of work under a shed (meta work_at: the trade props go there), and the shop
	## counters, which fold down 0.75 m over the street (seat_obstacles: the view steers walkers round them)
	var w := int(def.w)
	var d := int(def.d)
	var c := Vector2(h.position.x, -h.position.z)
	var rot := rad_to_deg(h.rotation.y)
	if def.has("stage"):
		# a building site: no lantern, no modules yet; its timber and stone wait at the back corners of the house
		h.set_meta("lantern_side", 0.0)
		if String(def.stage) != "frame":
			for q in [Vector2(-w / 2.0 + 1.4, d / 2.0 - 1.2), Vector2(w / 2.0 - 1.4, d / 2.0 - 1.4)]:
				_prop_spots.append(_local_plan(c, rot, q))
		return
	for e: Dictionary in def.get("porch", []):
		var side: String = e.side
		var cells := HouseBuilder._wall_cells(w, d, side)
		var out: Vector2 = HouseBuilder.OUTWARD[side]
		var along := Vector2(-out.y, out.x)
		var work := Vector2.ZERO
		var stalls := []
		for i in range(int(e.from), int(e.to) + 1):
			var cell: Vector2 = cells[i]
			work += _local_plan(c, rot, cell + out * 1.0)
			for sx in ([-1.0, 1.0] if i == int(e.to) else [-1.0]):
				_post_spots.append(_local_plan(c, rot, cell + out * 1.9 + along * sx))
			_porch_cells.append([_local_plan(c, rot, cell + out * 1.0), rot])
			if e.get("stalls", false):
				# stable stalls under the lean-to: the place of a beast each (PuebloVivo), not of the trade props
				stalls.append({at = _local_plan(c, rot, cell + out * 1.0), rot = rot + float(HouseBuilder.SIDES[side])})
				_prop_spots.append(_local_plan(c, rot, cell + out * 1.0))
		if not stalls.is_empty():
			h.set_meta("stalls", h.get_meta("stalls", []) + stalls)
		elif not h.has_meta("work_at"):
			h.set_meta("work_at", work / (int(e.to) - int(e.from) + 1))
	# what the type's def stands on the ground of the lot (yard things, cellar hatch, oven): no prop on them; on a tile
	# somebody walks (the tavern's barrels by its door) walkers are steered round them like round a shop counter
	var ground := []
	for e: Dictionary in def.get("yard", []):
		var side: String = e.get("side", "back")
		var cells := HouseBuilder._wall_cells(w, d, side)
		var i := clampi(int(e.get("cell", 0)) if int(e.get("cell", 0)) >= 0 else cells.size() + int(e.get("cell", 0)), 0, cells.size() - 1)
		ground.append((cells[i] as Vector2) + (HouseBuilder.OUTWARD[side] as Vector2) * float(e.get("out", 1.0))
			+ Vector2(float(e.get("along", 0.0)), 0).rotated(deg_to_rad(HouseBuilder.SIDES[side])))
	for k in ["hatch", "oven"]:
		if def.has(k):
			var side: String = def[k].get("side", "back")
			var cells := HouseBuilder._wall_cells(w, d, side)
			var cell: Vector2 = cells[clampi(int(def[k].get("cell", 0)), 0, cells.size() - 1)]
			for o in [0.6, 1.4]:
				ground.append(cell + (HouseBuilder.OUTWARD[side] as Vector2) * o)
	for q: Vector2 in ground:
		var gp := _local_plan(c, rot, q)
		_prop_spots.append(gp)
		if walkable(floori(gp.x / 2.0), floori(-gp.y / 2.0)):
			seat_obstacles.append([gp, gp, 0.5])
	if def.get("lantern", false):
		h.set_meta("own_lantern", true)
	# the wall lantern by the door (sim3d.gd): right of the door (+1) unless the sign hangs there or a shop window opens
	# there, then left (-1), and none (0) with shop windows on both sides
	var n_front := w / 2
	var dcell := HouseBuilder.door_cell(def, n_front)
	var shop_cells: Array = def.shop.get("cells", []) if def.has("shop") and def.shop.get("side", "front") == "front" else []
	var right_free: bool = not def.has("sign") and not (def.has("shop") and def.shop.has("sign")) and not (dcell + 1) in shop_cells
	var left_free: bool = not (dcell - 1) in shop_cells
	if def.get("lantern", false) or def.has("display") or def.has("herbs"):
		right_free = false  # the def hangs its own lantern, or its shop windows and planters take the wall by the door
		left_free = false
	h.set_meta("lantern_side", 1.0 if right_free else (-1.0 if left_free else 0.0))
	if def.has("shop"):
		var side: String = def.shop.get("side", "front")
		var cells := HouseBuilder._wall_cells(w, d, side)
		var out: Vector2 = HouseBuilder.OUTWARD[side]
		var along := Vector2(-out.y, out.x)
		var door := HouseBuilder.door_cell(def, cells.size())
		for i in def.shop.get("cells", []):
			if int(i) == door or int(i) < 0 or int(i) >= cells.size():
				continue
			var cell: Vector2 = cells[int(i)]
			seat_obstacles.append([_local_plan(c, rot, cell + out * 0.37 - along * 0.5), _local_plan(c, rot, cell + out * 0.37 + along * 0.5), 0.4])


# ---------------------------------------------------------------- interior in place
## A building type with data/interiors/<type>_sitio.json has its interior inside its own house of the town
## (docs/interior3d.md, «Interior en sitio»). The file's "shell" says what that house must be: size, floors, door cell
## and the modules the interior counts on (shop window, shed, chimney over the hearth), plus what only the inside asks
## of the walls: a doorway to the shed, wall cells without a window where a partition or a tall piece stands, the
## stair hole in the upper floor. A house the lot does not let be like that keeps its usual look and has no interior
## in place. `--interior=grande` leaves every house as it was (the separate big interior of interior3d.gd).
var _situ_cache := {}


func situ_for(id: String, level: int) -> Dictionary:
	## the interior in place of a building type at a level of look (SituShell.data_for: data/interiors/<id>_sitio_n<level>.json
	## or the file that serves that level); level 0: the file without a level. {} if none, or with `--interior=grande`.
	## `--forja=6x8`: that variant of the forge (tools/sims_variant.py).
	var key := "%s|%d" % [id, level]
	if not _situ_cache.has(key):
		var sd := {}
		if not "--interior=grande" in OS.get_cmdline_user_args():
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--forja=") and id == "forge":
					sd = SituShell.data_for(id, level, a.trim_prefix("--forja="))
					if level > 0 and sd.has("for_levels") and not (sd.for_levels as Array).has(float(level)):
						sd = {}
			if sd.is_empty():
				sd = SituShell.data_for(id, level)
		_situ_cache[key] = sd
	return _situ_cache[key]


func _shell_site(h: Node3D, def: Dictionary, sd: Dictionary) -> void:
	## the house knows its interior; the ground under its shed is kept for it (no yard props, no vegetable beds) and the
	## props of the trade go to the yard behind the house
	var w := int(def.w)
	var d := int(def.d)
	var keep := []
	for e: Dictionary in def.get("porch", []):
		var cells := HouseBuilder._wall_cells(w, d, e.side)
		var out: Vector2 = HouseBuilder.OUTWARD[e.side]
		for i in range(int(e.from), int(e.to) + 1):
			var c: Vector2 = (cells[i] as Vector2) + out * 1.05
			keep.append(Rect2(c - Vector2(1.0, 1.0), Vector2(2.0, 2.0)).grow(0.1))
	if keep.is_empty():
		return
	h.set_meta("keep_clear", keep)
	var c0 := Vector2(h.position.x, -h.position.z)
	h.set_meta("work_at", _local_plan(c0, rad_to_deg(h.rotation.y), Vector2(0, d / 2.0 + 1.0)))


func _kept_clear(p: Vector2, margin: float) -> bool:
	## plan point on ground an interior in place keeps for itself (under its shed)
	for h in houses:
		if not h.has_meta("keep_clear"):
			continue
		var local := h.transform.affine_inverse() * HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0.0))
		for rc: Rect2 in h.get_meta("keep_clear"):
			if rc.grow(margin).has_point(Vector2(local.x, -local.z)):
				return true
	return false


# ---------------------------------------------------------------- church
var church: Node3D  # the church of the town (one of `houses`, type "church"), null if the map has no site for it
const CHURCHES := [["parroquia", 12, 8, 2.0], ["ermita", 6, 12, 0.0], ["ermita_corta", 6, 8, 0.0], ["capilla", 6, 6, 0.0]]


func _church(b: Dictionary) -> void:
	## The church on its site (LandmarkBuilder, kit/landmarks): the biggest of CHURCHES ([assembly, metres along the front,
	## metres deep, where its door stands from the middle of its front]) that fits, its front on the edge that looks at
	## the atrium. It is one more of `houses` (footprint, merging, the lantern by the door); nobody goes in.
	var box: Rect2i = b.box
	var side: String = b.side
	var along_x := side == "south" or side == "north"
	var len_m := (box.size.x if along_x else box.size.y) * 2
	var dep_m := (box.size.y if along_x else box.size.x) * 2
	for ch in CHURCHES:
		var w := int(ch[1])
		var d := int(ch[2])
		if w > len_m or d > dep_m or LandmarkBuilder.info(ch[0]).is_empty():
			continue
		var lm := LandmarkBuilder.build(ch[0])
		if lm == null:
			continue
		var cursor := int((len_m - w) / 4) * 2
		var c := Vector2.ZERO
		var rot := 0.0
		match side:
			"south":
				c = Vector2(box.position.x * 2.0 + cursor + w / 2.0, -box.end.y * 2.0 + d / 2.0)
			"north":
				c = Vector2(box.position.x * 2.0 + cursor + w / 2.0, -box.position.y * 2.0 - d / 2.0)
				rot = 180.0
			"east":
				c = Vector2(box.end.x * 2.0 - d / 2.0, -box.position.y * 2.0 - cursor - w / 2.0)
				rot = 90.0
			"west":
				c = Vector2(box.position.x * 2.0 + d / 2.0, -box.position.y * 2.0 - cursor - w / 2.0)
				rot = 270.0
		var h := Node3D.new()
		h.name = "church_%d_%d" % [box.position.x, box.position.y]
		lm.position = HouseBuilder.plan_to_godot(Vector3(float(ch[3]), -d / 2.0 + 0.3, 0))  # the front wall 0.3 m inside the lot
		h.add_child(lm)
		h.position = HouseBuilder.plan_to_godot(Vector3(c.x, c.y, 0))
		h.rotation.y = deg_to_rad(rot)
		h.set_meta("wd", Vector2(w, d))
		h.set_meta("type", "church")
		h.set_meta("box", box)
		h.set_meta("door_x", float(ch[3]))
		add_child(h)
		houses.append(h)
		church = h
		if OS.is_debug_build():
			print("[Pueblo] church: %s (%dx%d m) on the site %s (%dx%d m), front %s" % [ch[0], w, d, box, len_m, dep_m, side])
		return
	if OS.is_debug_build():
		print("[Pueblo] church: nothing of kit/landmarks fits the site %s (%dx%d m)" % [box, len_m, dep_m])


func _door(h: Node3D) -> Array:
	## [door plan pos, outward plan dir, side plan dir]
	var wd: Vector2 = h.get_meta("wd")
	var tr: Transform3D = h.transform
	var dg := tr * Vector3(float(h.get_meta("door_x", 0.0)), 0, wd.y / 2.0)
	var og := (tr.basis * Vector3(0, 0, 1)).normalized()
	var out := Vector2(og.x, -og.z)
	return [Vector2(dg.x, -dg.z), out, Vector2(-out.y, out.x)]


# ---------------------------------------------------------------- props off the sim's walkable tiles
## The sim's walkable tiles: walk_mask (rows of "0"/"1", sim3d copies it from the trace) or, without it, the map's
## walkable characters (the same mask the trace carries for town_e: grass, roads, paths, plaza, fields, bridges).
var walk_mask: Array = []
var yard_tiles := {}       # Vector2i -> true: '#' tiles no 3D house covers
var prop_stats := {"placed": 0, "moved": 0, "dropped": 0}
var _prop_spots: Array[Vector2] = []  # plan positions of the props placed so far (no two on one spot)
var _post_spots: Array[Vector2] = []  # plan positions of the porch and shed posts of the houses (_module_spots)
const WALKABLE_CHARS := ".=,Pfb"
const PROP_CLEAR := 1.25  # min distance from a prop to the centre of a walkable tile (m)


func walkable(c: int, r: int) -> bool:
	if r < 0 or r >= H or c < 0 or c >= W:
		return false
	if not walk_mask.is_empty():
		return String(walk_mask[r])[c] == "1"
	return WALKABLE_CHARS.contains(_t(c, r))


func _house_at_plan(p: Vector2, margin: float) -> Node3D:
	for h in houses:
		var wd: Vector2 = h.get_meta("wd")
		var local := h.transform.affine_inverse() * HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0.5))
		if absf(local.x) < wd.x / 2.0 + margin and absf(local.z) < wd.y / 2.0 + margin:
			return h
	return null


func spot_free(p: Vector2, radius := 0.45) -> bool:
	## a prop of `radius` at plan point p keeps clear of every walkable tile, every 3D house and the other props
	var c := int(floor(p.x / 2.0))
	var r := int(floor(-p.y / 2.0))
	if walkable(c, r) or _t(c, r) == "w" or _t(c, r) == "b":
		return false
	for q in _post_spots:
		if q.distance_to(p) < radius + 0.2:
			return false
	if _near_water(Vector2(p.x, -p.y), radius + WATER_CLEAR - 0.45):
		return false
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if walkable(c + dc, r + dr) and _tp(c + dc, r + dr).distance_to(p) < PROP_CLEAR + radius - 0.45:
				return false
	if _house_at_plan(p, radius) != null or _kept_clear(p, radius):
		return false
	for q in _prop_spots:
		if q.distance_to(p) < 0.9:
			return false
	if _lat_ready:
		# what stands there by its footprint (fences, gates, the pieces of PuebloVivo)
		for o in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
			if _lat_used.has(Vector2i(floori((p.x + o.x * 0.7) / LAT), floori((-p.y + o.y * 0.7) / LAT))):
				return false
	return true


const WATER_CLEAR := 1.3  # from a prop to a water tile: the river ribbon wanders up to a metre over its banks


func _near_water(g: Vector2, clear := WATER_CLEAR) -> bool:
	## godot x/z point within `clear` m of a water tile (the yards of a block by the river end at the water)
	var c := floori(g.x / 2.0)
	var r := floori(g.y / 2.0)
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if _t(c + dc, r + dr) != "w":
				continue
			var near := Vector2(clampf(g.x, (c + dc) * 2.0, (c + dc + 1) * 2.0), clampf(g.y, (r + dr) * 2.0, (r + dr + 1) * 2.0))
			if near.distance_to(g) < clear:
				return true
	return false


func _near_spot(p: Vector2, radius := 0.45, reach := 2.5) -> Vector2:
	## p if free, else the nearest free point (half-tile steps) within `reach` m; Vector2.INF if none
	if spot_free(p, radius):
		return p
	var best := Vector2.INF
	var bd := reach + 0.01
	var k := -reach
	while k <= reach:
		var j := -reach
		while j <= reach:
			var q := p + Vector2(k, j)
			var d := q.distance_to(p)
			if d < bd and spot_free(q, radius):
				bd = d
				best = q
			j += 0.5
		k += 0.5
	return best


func _prop(kind: String, name: String, at: Vector3, rot := 0.0, radius := 0.45, reach := 2.5) -> Node3D:
	## kind "q" (Fantasy Props), "p" (kit/props @ or village pieces): placed off the walkable tiles, moved to the
	## nearest free spot or dropped (prop_stats)
	var want := Vector2(at.x, at.y)
	var p := _near_spot(want, radius, reach)
	if p == Vector2.INF:
		prop_stats.dropped += 1
		_dropped.append({kind = kind, name = name, want = want, rot = rot, house = null})
		if OS.is_debug_build():
			print("[Pueblo] prop %s has no free spot near %s: kept for _recover_props" % [name, want])
		return null
	if p != want:
		prop_stats.moved += 1
	prop_stats.placed += 1
	_prop_spots.append(p)
	_lat_sync()
	var v := Vector3(p.x, p.y, at.z)
	if kind == "q":
		var n: Node3D = load(QPROPS % name).instantiate()
		n.position = HouseBuilder.plan_to_godot(v)
		n.rotation.y = deg_to_rad(rot)
		_q.add_child(n)
		return n
	return HouseBuilder._piece(name, _q, v, rot)


func _yard_spots(h: Node3D) -> Array:
	## free yard points of this building's rectangle and its neighbourhood, nearest the door first
	var dd := _door(h)
	var door: Vector2 = h.get_meta("work_at", dd[0])  # under its shed if it has one, else by the door
	if String(h.get_meta("type", "")) in TALL_TRADE_PROPS:
		door = dd[0]  # its racks stand taller than the eaves of a lean-to (they came out through its tiles)
	var box: Rect2i = h.get_meta("box")
	var out := []
	for k in yard_tiles:
		var t: Vector2i = k
		if not box.grow(1).has_point(t):
			continue
		var c := _tp(t.x, t.y)
		for off in [Vector2.ZERO, Vector2(0.5, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5)]:
			out.append(c + off)
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(door) < b.distance_to(door))
	return out


const TALL_TRADE_PROPS := ["armory"]
const TRADE_PROPS := {
	"forge": [["q", "Anvil_Log", 20], ["q", "Barrel", 0], ["q", "Whetstone", 0], ["p", "@carbon", 0]],
	"armory": [["q", "WeaponStand", 180], ["q", "Shield_Wooden", 0]],
	"carpentry": [["p", "@lena", 90], ["q", "Workbench", 180]],
	"masonry": [["p", "@banco", 0], ["p", "Prop_Brick1", 30]],
	"tailor_shop": [["q", "Dummy", 180], ["p", "@telas", 0]],
	"clinic": [["p", "@bancal", 0], ["q", "Cauldron", 0]],
	"tavern_inn": [["p", "@mesa_taberna", 0], ["p", "@banco_corrido", 0], ["q", "Barrel", 0], ["q", "Barrel", 30]]}


func _trade_props(h: Node3D, type: String) -> void:
	## the props of a trade on the free yard tiles of its rectangle (nearest the door); none on walkable ground
	var face := rad_to_deg(atan2((_door(h)[1] as Vector2).x, (_door(h)[1] as Vector2).y))
	var spots := _yard_spots(h)
	var placed := 0
	for pr in TRADE_PROPS.get(type, []):
		if type == "tavern_inn":
			# long pieces (bench, table 2.8 m): placed by their real footprint on the terrace (_recover_props)
			_dropped.append({kind = pr[0], name = pr[1], want = _door(h)[0], rot = face + float(pr[2]), house = h})
			prop_stats.dropped += 1
			continue
		var done := false
		for sp in spots:
			var q: Vector2 = sp
			if type in TALL_TRADE_PROPS and _under_porch(q):
				continue
			if spot_free(q):
				_prop(pr[0], pr[1], Vector3(q.x, q.y, 0), face + float(pr[2]), 0.45, 0.0)
				done = true
				placed += 1
				break
		if not done:
			prop_stats.dropped += 1
			var dd: Array = _door(h)
			_dropped.append({kind = pr[0], name = pr[1], want = dd[0], rot = face + float(pr[2]), house = h})
	if OS.is_debug_build():
		print("[Pueblo] %s %s: %d/%d trade props on its yard" % [type, h.name, placed, TRADE_PROPS.get(type, []).size()])


# ---------------------------------------------------------------- roads, plaza, fields
func _runs(chars: String, horizontal: bool) -> Array:
	## maximal straight runs of the given tile chars, merged into bands: [start, end, band0, band1]
	var lines := []
	var n1 := H if horizontal else W
	var n2 := W if horizontal else H
	for a in n1:
		var b := 0
		while b < n2:
			var ch := _t(b, a) if horizontal else _t(a, b)
			if chars.contains(ch):
				var s := b
				while b < n2 and chars.contains(_t(b, a) if horizontal else _t(a, b)):
					b += 1
				if b - s >= 3:
					lines.append([s, b - 1, a, a])
			else:
				b += 1
	var bands := []
	for l in lines:
		var merged := false
		for bd in bands:
			if bd[0] == l[0] and bd[1] == l[1] and bd[3] == l[2] - 1:
				bd[3] = l[2]
				merged = true
				break
		if not merged:
			bands.append(l.duplicate())
	return bands


func _band_ribbon(bd: Array, horizontal: bool, extra: float, mat: Material, lift: float, wobble: float) -> MeshInstance3D:
	var mid: float = (bd[2] + bd[3]) / 2.0
	var pts := []
	var k: float = bd[0] - 0.4
	while k <= bd[1] + 0.4:
		var p := _tp(k, mid) if horizontal else _tp(mid, k)
		var j := rng.randf_range(-wobble, wobble)
		p += Vector2(0, j) if horizontal else Vector2(j, 0)
		pts.append(p)
		k += 2.5
	var end := _tp(bd[1] + 0.4, mid) if horizontal else _tp(mid, bd[1] + 0.4)
	pts.append(end)
	var width: float = (bd[3] - bd[2] + 1) * 2.0 + extra
	var r := RoadBuilder.build(pts, width, mat, lift, rng.randi() % 997)
	add_child(r)
	return r


func _town_roads() -> void:
	var road := _road_mat(0.32)
	var path := _road_mat(0.0)
	var plaza := _road_mat(0.92)
	for hz in [true, false]:
		for bd in _runs("=b", hz):
			if bd[3] - bd[2] <= 3:
				_band_ribbon(bd, hz, 1.6, road, 0.02, 0.35)
		for bd in _runs(",", hz):
			if bd[3] - bd[2] <= 2:
				_band_ribbon(bd, hz, 0.6, path, 0.016, 0.25)
	# plaza: one wide ribbon over the bounding box of P/S/N tiles
	var box := Rect2i()
	var first := true
	for r in H:
		for c in W:
			if _t(c, r) in ["P", "S", "N"]:
				box = Rect2i(c, r, 1, 1) if first else box.expand(Vector2i(c, r)).expand(Vector2i(c + 1, r + 1))
				first = false
	if not first:
		var cx := box.position.x + box.size.x / 2.0 - 0.5
		add_child(RoadBuilder.build([_tp(cx, box.position.y - 0.6), _tp(cx + 0.2, box.position.y + box.size.y / 2.0),
			_tp(cx, box.end.y - 0.4)], box.size.x * 2.0 + 1.5, plaza, 0.024, 5))
	# fields: dark soil strips per row of 'f', crop rows on top
	var soil := _road_mat(0.0)
	soil.set_shader_parameter("dirt", load("res://kit/streets/tierra_albedo.png"))
	for bd in _runs("f", true):
		_band_ribbon(bd, true, 0.8, soil, 0.014, 0.1)
	if vivo.crops():
		return  # the fields carry the crop beds of the catalogue, by field and season
	for r in H:
		for c in W:
			if _t(c, r) == "f" and r % 2 == 0:
				var fur := HouseBuilder._piece("@surco", _q, Vector3(_tp(c, r).x, _tp(c, r).y - 1.0, 0), 0)
				if fur:
					fur.set_meta("flat", true)  # crop rows: ground cover the sim walks over


func _yard_ground() -> void:
	## worn earth on the yards (the '#' tiles no house covers; not the plaza well's lone tile): one soil ribbon per band of
	## yard tiles (rows with the same span merged), like the fields, all merged into one mesh without shadow
	var soil := _road_mat(0.0)
	soil.set_shader_parameter("dirt", load("res://kit/streets/tierra_albedo.png"))
	var lines := []
	for r in H:
		var c := 0
		while c < W:
			var t := Vector2i(c, r)
			if not yard_tiles.has(t) or (walkable(c - 1, r) and walkable(c + 1, r) and walkable(c, r - 1) and walkable(c, r + 1)):
				c += 1
				continue
			var s := c
			while c < W and yard_tiles.has(Vector2i(c, r)):
				c += 1
			lines.append([s, c - 1, r, r])
	var bands := []
	for l in lines:
		var merged := false
		for bd in bands:
			if bd[0] == l[0] and bd[1] == l[1] and bd[3] == l[2] - 1:
				bd[3] = l[2]
				merged = true
				break
		if not merged:
			bands.append(l.duplicate())
	var st := SurfaceTool.new()
	var n := 0
	for bd in bands:
		# along the longer side of the band (a ribbon is long and narrow)
		var horiz: bool = bd[1] - bd[0] >= bd[3] - bd[2]
		var rb := [bd[0], bd[1], bd[2], bd[3]] if horiz else [bd[2], bd[3], bd[0], bd[1]]
		var mi := _band_ribbon(rb, horiz, 0.3, soil, 0.013, 0.08)
		st.append_from(mi.mesh, 0, mi.transform)
		remove_child(mi)
		mi.free()  # now: queued it would still be in the tree for _collect_materials (set_style then hits a freed node)
		n += 1
	if n == 0:
		return
	var yard := MeshInstance3D.new()
	yard.name = "YardGround"
	yard.mesh = st.commit()
	yard.material_override = soil
	yard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(yard)
	if OS.is_debug_build():
		print("[Pueblo] yard ground: %d bands of yard tiles in one mesh" % n)


# ---------------------------------------------------------------- river
func _river() -> void:
	var water := ShaderMaterial.new()
	water.shader = load("res://game/world3d/shaders/water.gdshader")
	_water.append(water)
	var bank := _road_mat(0.0)
	for bd in _runs("wb", false):
		_band_ribbon(bd, false, 3.6, bank, 0.012, 0.6)
		var r := _band_ribbon(bd, false, 0.8, water, 0.05, 0.6)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# bridges over the 'b' tiles: the timber bridge of kit/landmarks (4 m wide with a ramp at each end for a road of two
	# tiles, 3 m for one), as long as its tiles and one more on each bank
	var seen := {}
	for r in H:
		for c in W:
			if _t(c, r) != "b" or seen.has(Vector2i(c, r)):
				continue
			var c1 := c
			while _t(c1 + 1, r) == "b":
				c1 += 1
			var r1 := r
			while _t(c, r1 + 1) == "b":
				r1 += 1
			for rr in range(r, r1 + 1):
				for cc in range(c, c1 + 1):
					seen[Vector2i(cc, rr)] = true
			# it runs along x when the road comes in from west and east (the river then flows north-south)
			var along_x := _t(c - 1, r) != "w" and _t(c1 + 1, r) != "w"
			var n_along := (c1 - c + 1) if along_x else (r1 - r + 1)
			var n_across := (r1 - r + 1) if along_x else (c1 - c + 1)
			var id := "puente_madera_4" if n_across >= 2 else "puente_madera"
			var info := LandmarkBuilder.info(id)
			var node: Node3D = LandmarkBuilder.build(id) if not info.is_empty() else null
			if node == null:
				push_warning("[Pueblo] no bridge piece %s: run tools/make_landmarks.py" % id)
				continue
			var fp: Array = info.footprint
			var centre := (_tp(c, r) + _tp(c1, r1)) / 2.0
			var length := n_along * 2.0 + 4.0
			var width := maxf(float(fp[1]), n_across * 2.0)
			node.position = HouseBuilder.plan_to_godot(Vector3(centre.x, centre.y, 0))
			node.rotation.y = 0.0 if along_x else PI / 2.0
			node.scale = Vector3(length / float(fp[0]), 1, width / float(fp[1]))
			node.set_meta("flat", true)  # walked over (the sim's check does not take it for an obstacle)
			_q.add_child(node)
			bridges.append({inv = node.transform.affine_inverse(), half = Vector2(float(fp[0]), float(fp[1])) / 2.0, profile = info.deck.profile})
			if OS.is_debug_build():
				print("[Pueblo] bridge %s over tiles (%d,%d)-(%d,%d): %.0f x %.0f m, %s" % [id, c, r, c1, r1, length, width, "along x" if along_x else "along y"])


## The bridges of the town: [{inv: Transform3D (town -> the piece), half: Vector2 (half length, half width of the piece),
## profile: [[x, height]] of its deck}]. ground_y() is the height whoever walks there stands at.
var bridges: Array = []
const GROUND_Y := 0.03


func ground_y(p: Vector2) -> float:
	## height of the ground under a plan point: the deck of the bridge it is on (ramps at both ends: no step), else GROUND_Y
	for b in bridges:
		var l: Vector3 = (b.inv as Transform3D) * Vector3(p.x, 0, -p.y)
		var half: Vector2 = b.half
		if absf(l.x) > half.x or absf(l.z) > half.y + 0.2:
			continue
		var prof: Array = b.profile
		for i in range(1, prof.size()):
			if l.x <= float(prof[i][0]):
				var k := (l.x - float(prof[i - 1][0])) / maxf(0.001, float(prof[i][0]) - float(prof[i - 1][0]))
				return maxf(GROUND_Y, lerpf(float(prof[i - 1][1]), float(prof[i][1]), clampf(k, 0.0, 1.0)))
		return maxf(GROUND_Y, float(prof[-1][1]))
	return GROUND_Y


# ---------------------------------------------------------------- mill wheel, wayside cross, market stalls
class Spinner extends Node:
	## turns the animated parts of the landmarks (mill wheel): [[Node3D, axis in its own space, rad per second]]
	var parts: Array = []

	func _process(dt: float) -> void:
		for p in parts:
			(p[0] as Node3D).rotate_object_local(p[1], float(p[2]) * dt)


var mill: Node3D  # the water mill (one of `houses`, type "mill") or, without a site for it, the wheel on a house; null if neither


func _mill() -> void:
	## The water mill of kit/landmarks (molino_agua: a house of 4 x 6 m with its wheel on its +x side) on a yard by the
	## river: 2 x 3 yard tiles (nobody walks them) with water all along the wheel side, the door towards a street if
	## there is one. It is one more of `houses` (type "mill": footprint, merging, lantern); its wheel leaves the house
	## node (opt3d merges a house into one mesh) and turns (Spinner).
	var info := LandmarkBuilder.info("molino_agua")
	if info.is_empty():
		return
	var best := {}
	var bs := 0
	var keys := yard_tiles.keys()
	keys.sort()
	for k: Vector2i in keys:
		for o in [[Vector2i(2, 3), 0.0], [Vector2i(2, 3), 180.0], [Vector2i(3, 2), 90.0], [Vector2i(3, 2), 270.0]]:
			var rect := Rect2i(k, o[0])
			# tile steps towards the wheel (+x of the piece) and towards the front (-y), turned with the piece
			var wv := Vector2(1, 0).rotated(deg_to_rad(o[1]))
			var fv := Vector2(0, -1).rotated(deg_to_rad(o[1]))
			var wt := Vector2i(roundi(wv.x), -roundi(wv.y))
			var ft := Vector2i(roundi(fv.x), -roundi(fv.y))
			var ok := true
			var street := 0
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var t := Vector2i(x, y)
					ok = ok and yard_tiles.has(t) and _t(x, y) == "#"
					if not rect.has_point(t + wt):
						ok = ok and _t(x + wt.x, y + wt.y) == "w"
					if not rect.has_point(t + ft) and walkable(x + ft.x, y + ft.y):
						street += 2 if _t(x + ft.x, y + ft.y) in ["=", ",", "P"] else 1
			if ok and street > bs:
				bs = street
				best = {rect = rect, rot = o[1]}
	if best.is_empty():
		if OS.is_debug_build():
			print("[Pueblo] mill: no yard of 2 x 3 tiles with the river along one side")
		return
	# its own look by data (data/pueblo_vivo.json `mill`: palette of kit/variants): beside a house it must not read as
	# one more of them
	var mopts: Dictionary = vivo.cfg.get("mill", {}) if vivo != null and vivo.on() else {}
	var lm := LandmarkBuilder.build("molino_agua", mopts)
	if lm == null:
		return
	var rect: Rect2i = best.rect
	var h := Node3D.new()
	h.name = "mill_%d_%d" % [rect.position.x, rect.position.y]
	h.add_child(lm)
	h.position = HouseBuilder.plan_to_godot(Vector3(rect.position.x + rect.end.x, -(rect.position.y + rect.end.y), 0))
	h.rotation.y = deg_to_rad(best.rot)
	var hb: Array = info.get("bounds_house", [4, 6])
	h.set_meta("wd", Vector2(float(hb[0]), float(hb[1])))
	h.set_meta("type", "mill")
	h.set_meta("box", rect)
	var doors: Array = info.get("doors", [])
	h.set_meta("door_x", float(doors[0].at[0]) if not doors.is_empty() else 0.0)
	add_child(h)
	houses.append(h)
	mill = h
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			yard_tiles.erase(Vector2i(x, y))
	var n := _spin(lm, true)
	if OS.is_debug_build():
		print("[Pueblo] mill: molino_agua on the yard %s, turned %.0f, door to %d street points, %d turning parts" % [rect, best.rot, bs, n])


func _spin(root: Node3D, detach: bool) -> int:
	## the animated parts of a landmark (LandmarkBuilder.animated) turn from now on; detach: they become children of the
	## town where they stand (out of a house node that opt3d merges)
	var sp := get_node_or_null("Spinner") as Spinner
	if sp == null:
		sp = Spinner.new()
		sp.name = "Spinner"
		add_child(sp)
	var seen := {}
	for a in LandmarkBuilder.animated(root):
		var part: Node3D = a.node
		if seen.has(part):
			continue
		seen[part] = true
		if detach:
			var gt := part.global_transform
			part.get_parent().remove_child(part)
			add_child(part)
			part.global_transform = gt
		sp.parts.append([part, a.axis, 0.6])
	return seen.size()


func _mill_wheel() -> void:
	## Without a yard for the whole mill: a water wheel (kit/landmarks molino_rueda: wheel, stone bearing, landing) on the
	## river wall of the first house with a whole side or back wall over water tiles; that house is the mill.
	for h in houses:
		if h.get_meta("type") in ["church", "mill"]:
			continue
		var wd: Vector2 = h.get_meta("wd")
		var c := Vector2(h.position.x, -h.position.z)
		var rot := rad_to_deg(h.rotation.y)
		for side: String in ["right", "left", "back"]:
			var cells := HouseBuilder._wall_cells(int(wd.x), int(wd.y), side)
			var out: Vector2 = HouseBuilder.OUTWARD[side]
			var wet := cells.size() >= 2
			for cell: Vector2 in cells:
				var q := _local_plan(c, rot, cell + out)
				if _t(floori(q.x / 2.0), floori(-q.y / 2.0)) != "w":
					wet = false
			if not wet:
				continue
			var node := LandmarkBuilder.build("molino_rueda")
			if node == null:
				return
			# the piece: wall face at x = 0, +x out over the water, the axle at y = 0 (0.6 m off the middle of the wall:
			# its landing then ends at the corner of the house)
			var along := Vector2(-out.y, out.x)
			var mid: Vector2 = ((cells[0] as Vector2) + (cells[-1] as Vector2)) / 2.0
			var at := _local_plan(c, rot, mid + along * 0.6 + out * 0.02)
			node.position = HouseBuilder.plan_to_godot(Vector3(at.x, at.y, 0))
			node.rotation.y = deg_to_rad(rot) + out.angle()
			add_child(node)
			mill = node
			h.set_meta("mill", true)
			var n := _spin(node, false)
			if OS.is_debug_build():
				print("[Pueblo] mill: wheel on the %s wall of %s (%d turning parts)" % [side, h.name, n])
			return
	if OS.is_debug_build():
		print("[Pueblo] mill: no house with a wall over the river")


func _plaza_cross() -> void:
	## A wayside cross (kit/landmarks cruceiro) in the atrium, before the church: on the corner of four plaza or grass
	## tiles nearest the point 2 m in front of the middle of the church. A walker on a tile centre passes 1.4 m from it
	## (its base is 1 m of radius); who cuts the corner is steered round it (seat_obstacles), like round the benches.
	if church == null or LandmarkBuilder.info("cruceiro").is_empty():
		return
	var dd := _door(church)
	var wd: Vector2 = church.get_meta("wd")
	var out: Vector2 = dd[1]
	var front := Vector2(church.position.x, -church.position.z) + out * (wd.y / 2.0)
	var want := front + out * 2.0
	var best := Vector2.INF
	var bd := 7.0
	for i in range(-4, 5):
		for j in range(-4, 5):
			var p := Vector2(roundf(want.x / 2.0) * 2.0 + i * 2.0, roundf(want.y / 2.0) * 2.0 + j * 2.0)
			if (p - front).dot(out) < 1.5 or p.distance_to(want) >= bd:
				continue
			var ok := true
			for dc in [-1, 0]:
				for dr in [-1, 0]:
					var t := Vector2i(roundi(p.x / 2.0) + dc, roundi(-p.y / 2.0) + dr)
					if not walkable(t.x, t.y) or not (_t(t.x, t.y) in ["P", "."]):
						ok = false
			if ok:
				bd = p.distance_to(want)
				best = p
	if best == Vector2.INF:
		if OS.is_debug_build():
			print("[Pueblo] cross: no corner of four free tiles before the church")
		return
	var node := LandmarkBuilder.build("cruceiro")
	node.position = HouseBuilder.plan_to_godot(Vector3(best.x, best.y, 0))
	node.rotation.y = atan2(out.x, -out.y)
	_q.add_child(node)
	_prop_spots.append(best)
	prop_stats.placed += 1
	seat_obstacles.append([best, best, 1.0])
	if OS.is_debug_build():
		print("[Pueblo] cross: cruceiro at %s, %.1f m before the church" % [best, (best - front).dot(out)])


## what each market stall of the map (data/market.json ids) shows on its counter and the colour of its awning
const STALL_GOODS := {"resources": ["sacos", OCHRE], "food": ["fruta", RED], "materials": ["herramientas", OCHRE],
	"clothier": ["telas", BLUE], "goods": ["ceramica", BLUE], "apothecary": ["botica", GREEN], "livestock": ["ganado", GREEN],
	"armory": ["forja", OCHRE]}


func _stall(c: int, r: int, id: String, turn: float, pick: int) -> void:
	## the market stall of an 'S' tile (kit/landmarks puesto_s: 1.84 m, inside its tile): its goods and awning by the
	## stall of the map that stands there, its counter towards the tile where the sim serves its customers
	var p := _tp(c, r)
	var cfg: Array = STALL_GOODS.get(id, [["fruta", "telas", "ceramica", "herramientas"][pick % 4], [RED, BLUE, GREEN, OCHRE][pick % 4]])
	var rot := turn
	var st: Dictionary = mapd.get("stalls", {}).get(id, {})
	if st.has("service"):
		var f := Vector2(float(st.service[0]) - c, -(float(st.service[1]) - r))
		if f != Vector2.ZERO:
			rot = rad_to_deg(f.angle()) + 90.0  # the piece's front is -y
	var node: Node3D = null
	if not LandmarkBuilder.info("puesto_s").is_empty():
		node = LandmarkBuilder.build("puesto_s", {"awning": cfg[1], "goods": cfg[0]})
	if node == null:
		_prop("q", "Stall_Empty", Vector3(p.x, p.y, 0), turn, 0.45, 0.0)
		return
	node.position = HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0))
	node.rotation.y = deg_to_rad(rot)
	_q.add_child(node)
	_prop_spots.append(p)
	prop_stats.placed += 1
	if OS.is_debug_build():
		print("[Pueblo] stall %s at tile (%d, %d): %s, awning %s, yaw %.0f" % [id if id != "" else "(no stall of the map)", c, r, cfg[0], (cfg[1] as Color).to_html(false), rot])


# ---------------------------------------------------------------- props, trees, ground cover
func _town_props() -> void:
	var stall_at := {}  # tile -> stall id of the map
	for id in mapd.get("stalls", {}):
		var st: Dictionary = mapd.stalls[id]
		if st.has("tile"):
			stall_at[Vector2i(int(st.tile[0]), int(st.tile[1]))] = String(id)
	for r in H:
		for c in W:
			var p := _tp(c, r)
			match _t(c, r):
				"S":
					# a turn and a pick for an 'S' tile that is no stall of the map (those go by their data)
					var turn := rng.randi_range(0, 3) * 90.0
					var pick := rng.randi()
					_stall(c, r, stall_at.get(Vector2i(c, r), ""), turn, pick)
				"N":
					if not vivo.board(c, r):
						_prop("p", "@cartel", Vector3(p.x, p.y, 0), 0, 0.45, 0.0)
	_recover_trade()  # the trade props still without a place, then the fences and gates of the yards
	_porch_cover()
	vivo.yards()      # by their real footprint, before the loose yard props: dock, cart, sheds, lines, hives, beasts
	for it in mapd.decor.items:
		if not it.has("at") or vivo.handles(it):
			continue
		var p := _tp(float(it.at[0]), float(it.at[1]))
		var v := Vector3(p.x, p.y, 0)
		# the dressing the 2D gives a yard that in 3D is the river, the church or the mill is not moved to another yard
		var under := _house_at_plan(p, 0.0)
		if _t(int(it.at[0]), int(it.at[1])) == "w" or (under != null and under.get_meta("type") in ["church", "mill"]):
			prop_stats.off_site = int(prop_stats.get("off_site", 0)) + 1
			continue
		match String(it.id):
			"yard_plot":
				_prop("p", "@bancal", v, 90.0 * (rng.randi() % 2))
			"yard_plot_sack":
				_prop("p", "@bancal", v, 0)
				_prop("p", "@sacos", v + Vector3(0.6, -0.7, 0), rng.randf() * 90)
			"yard_sacks", "grain_sack":
				_prop("p", "@sacos", v, rng.randf() * 90)
			"yard_crates", "crate":
				_prop("q", "Crate_Wooden", v, rng.randf() * 90)
			"yard_cart", "cart":
				_prop("p", "Prop_Wagon", v, rng.randf() * 360, 0.9)
			"yard_barrels", "barrel":
				_prop("q", "Barrel", v, 0)
				_prop("q", "Barrel", v + Vector3(0.7, 0.3, 0), 0)
			"well", "well_roof":
				if not vivo.well(p):
					_prop("p", "@pozo", v, 0, 0.8, 0.0)  # the lone '#' of the plaza (tools/well.py; no well in the kits)
			"bench":
				pass  # benches go where the sim seats people (_seats), not where the 2D decor draws them
			"fence":
				var off: Array = it.get("off", [0, 0])
				var a := signf(float(off[0]))
				var b := signf(float(off[1]))
				var dc := (a + b) / 2.0
				var dr := (b - a) / 2.0
				_prop("p", "Prop_WoodenFence_Single", Vector3(p.x + dc * 0.95, p.y - dr * 0.95, 0), 90.0 if dc != 0.0 else 0.0, 0.3, 0.0)
	_seats()
	vivo.street()  # lamps, stone benches, hedges and bushes on tile corners and edges: walkers are steered round them
	_recover_props()
	if OS.is_debug_build():
		print("[Pueblo] props: %d placed (%d moved off walkable tiles), %d recovered off the walkable tiles, %d dropped" % [
			prop_stats.placed, prop_stats.moved, prop_stats.get("recovered", 0), prop_stats.dropped])


# ---------------------------------------------------------------- props with no free spot: recovered off the walkable tiles
## A prop with no free spot near its 2D place (most 2D decor stands on grass the sim walks on) is not thrown away: it goes
## to the nearest gap no walker uses: the '#' tiles of a building rectangle the 3D house leaves free (yard corners, the
## strip along a wall), with its whole footprint (the model's AABB, rotated) out of every walkable tile, off the corners
## where two walkable tiles meet diagonally (a diagonal step cuts that corner), off the houses and the other props.
## Near a wall the piece lies along it. Fence pieces (the 2D fences ring the fields, which are walked) fence the yards
## instead: one piece per yard edge that faces a walkable tile.
const LAT := 0.25          # lattice step (m)
const RECOVER_REACH := 20.0
var _dropped: Array = []   # [{kind, name, want: plan, rot, house}]
var _lat_free := {}        # Vector2i lattice cell (godot x/z / LAT) -> true where a footprint may stand
var _lat_used := {}        # Vector2i -> true: covered by a prop
var _foot_cache := {}      # piece name -> Rect2 footprint in the piece's local x/z
var _lat_wall := {}        # Vector2i -> yaw along the nearest house wall within 1.2 m (no key: none)
var _lat_posts := {}       # Vector2i -> true: a porch post stands there (furniture keeps off it; the fence runs past it)


func _lat_ok(g: Vector2) -> bool:
	## godot x/z point: on a non-walkable tile, not in a house, not on a walkable diagonal corner
	var c := floori(g.x / 2.0)
	var r := floori(g.y / 2.0)
	if walkable(c, r) or _t(c, r) != "#":
		return false
	if _house_at_plan(Vector2(g.x, -g.y), 0.08) != null or _kept_clear(Vector2(g.x, -g.y), 0.3):
		return false
	if _near_water(g, WATER_CLEAR - 0.4):
		return false
	# corners of this tile where the two tiles across it are walkable (a diagonal step passes there)
	for cx in [0, 1]:
		for cy in [0, 1]:
			var corner := Vector2((c + cx) * 2.0, (r + cy) * 2.0)
			if g.distance_to(corner) > 0.45:
				continue
			var dc := 1 if cx == 1 else -1
			var dr := 1 if cy == 1 else -1
			if walkable(c + dc, r) and walkable(c, r + dr):
				return false  # the step between those two cuts this corner
	return true


var _lat_ready := false
var _lat_synced := 0  # how many of _prop_spots are already marked on the lattice


func _lat_sync() -> void:
	## the props placed since the last call take their disc of the lattice
	if not _lat_ready:
		return
	while _lat_synced < _prop_spots.size():
		var q := _prop_spots[_lat_synced]
		_mark_disc(Vector2(q.x, -q.y), 0.5)
		_lat_synced += 1


func _lat_build() -> void:
	if _lat_ready:
		_lat_sync()
		return
	_lat_ready = true
	for r in H:
		for c in W:
			if _t(c, r) != "#":
				continue
			if walkable(c - 1, r) and walkable(c + 1, r) and walkable(c, r - 1) and walkable(c, r + 1):
				continue  # a lone '#' (the plaza well of the 2D map) is not a yard
			var n := int(2.0 / LAT)
			for i in n:
				for j in n:
					var g := Vector2(c * 2.0 + (i + 0.5) * LAT, r * 2.0 + (j + 0.5) * LAT)
					if _lat_ok(g):
						var k := Vector2i(floori(g.x / LAT), floori(g.y / LAT))
						_lat_free[k] = true
						var wy := _wall_yaw(g)
						if not is_nan(wy):
							_lat_wall[k] = wy
	# what is already there: the props placed so far (radius 0.45 round their spot) and the porch posts
	_lat_sync()
	for q in _post_spots:
		var g := Vector2(q.x, -q.y)
		for i in range(floori((g.x - 0.3) / LAT), floori((g.x + 0.3) / LAT) + 1):
			for j in range(floori((g.y - 0.3) / LAT), floori((g.y + 0.3) / LAT) + 1):
				_lat_posts[Vector2i(i, j)] = true


func _mark_disc(g: Vector2, rad: float) -> void:
	var k0 := Vector2i(floori((g.x - rad) / LAT), floori((g.y - rad) / LAT))
	var k1 := Vector2i(floori((g.x + rad) / LAT), floori((g.y + rad) / LAT))
	for i in range(k0.x, k1.x + 1):
		for j in range(k0.y, k1.y + 1):
			if Vector2((i + 0.5) * LAT, (j + 0.5) * LAT).distance_to(g) <= rad:
				_lat_used[Vector2i(i, j)] = true


func _footprint(kind: String, name: String) -> Rect2:
	## local x/z rectangle of the piece (AABB of its meshes), cached
	var key := kind + name
	if _foot_cache.has(key):
		return _foot_cache[key]
	var n: Node3D = load(QPROPS % name).instantiate() if kind == "q" else (load("res://kit/props/%s.glb" % name.substr(1)) if name.begins_with("@") else load(HouseBuilder.KIT % name)).instantiate()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var q: Node = mi
		while q != n and q != null:
			if q is Node3D:
				xf = (q as Node3D).transform * xf
			q = q.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	n.free()
	var rc := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	_foot_cache[key] = rc
	return rc


func _foot_cells(rc: Rect2, at: Vector2, rot_deg: float, grow: float) -> Array:
	## lattice cells under the footprint rc (local x/z) placed at godot x/z `at`, turned rot_deg about y
	var out := []
	var a := deg_to_rad(rot_deg)
	var cs := cos(a)
	var sn := sin(a)
	var x := rc.position.x - grow
	while x <= rc.end.x + grow + 0.001:
		var z := rc.position.y - grow
		while z <= rc.end.y + grow + 0.001:
			# Node3D.rotation.y = a: local (x, z) -> world (x cos + z sin, -x sin + z cos)
			var g := at + Vector2(x * cs + z * sn, -x * sn + z * cs)
			out.append(Vector2i(floori(g.x / LAT), floori(g.y / LAT)))
			z += LAT * 0.5
		x += LAT * 0.5
	return out


func _fits(rc: Rect2, at: Vector2, rot_deg: float, past_posts := false) -> bool:
	# corners and centre first (most misses), then the whole footprint
	var a := deg_to_rad(rot_deg)
	var cs := cos(a)
	var sn := sin(a)
	for q in [rc.get_center(), rc.position - Vector2(0.05, 0.05), rc.end + Vector2(0.05, 0.05),
			Vector2(rc.position.x - 0.05, rc.end.y + 0.05), Vector2(rc.end.x + 0.05, rc.position.y - 0.05)]:
		var g: Vector2 = at + Vector2(q.x * cs + q.y * sn, -q.x * sn + q.y * cs)
		var k := Vector2i(floori(g.x / LAT), floori(g.y / LAT))
		if not _lat_free.has(k) or _lat_used.has(k):
			return false
	for k in _foot_cells(rc, at, rot_deg, 0.05):
		if not _lat_free.has(k) or _lat_used.has(k) or (not past_posts and _lat_posts.has(k)):
			return false
	return true


func _wall_yaw(g: Vector2) -> float:
	## yaw (deg) that lays a piece along the nearest house wall within 1.2 m, NAN if none
	var h := _house_at_plan(Vector2(g.x, -g.y), 1.2)
	if h == null:
		return NAN
	var local := h.transform.affine_inverse() * Vector3(g.x, 0, g.y)
	var wd: Vector2 = h.get_meta("wd")
	var along_x := absf(absf(local.z) - wd.y / 2.0) < absf(absf(local.x) - wd.x / 2.0)
	return rad_to_deg(h.rotation.y) + (0.0 if along_x else 90.0)


var _fences_made := 0
var _porch_cells: Array = []  # [plan centre, yaw of the house] of every 2 x 2 m of ground under a porch or a shed


func _under_porch(p: Vector2) -> bool:
	for pc in _porch_cells:
		if (pc[0] as Vector2).distance_to(p) < 1.5:
			return true
	return false


func _porch_cover() -> void:
	## the ground under the lean-to roofs is taken from here on: what comes after the trade props (trees, sheds, hay,
	## vegetable beds) stays out from under them
	for pc in _porch_cells:
		var k := -0.95
		while k <= 0.95:
			var j := -0.95
			while j <= 0.95:
				var q: Vector2 = (pc[0] as Vector2) + Vector2(k, j).rotated(deg_to_rad(float(pc[1])))
				_lat_used[Vector2i(floori(q.x / LAT), floori(-q.y / LAT))] = true
				j += LAT * 0.5
			k += LAT * 0.5


func _recover_trade() -> void:
	## first of all in the yards: the trade props of a building that found no spot by its door (the big ones first: they
	## fit in fewer places), then the fence of every yard with its gate (a terrace keeps its bench)
	var t0 := Time.get_ticks_msec()
	_lat_build()
	var items := []
	for d in _dropped:
		if d.house != null:
			items.append(d)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _footprint(a.kind, a.name).get_area() > _footprint(b.kind, b.name).get_area())
	var got := 0
	var cands: Array = _lat_free.keys()
	for d in items:
		if _recover_one(d, cands):
			got += 1
		d["tried"] = true
	_fences_made = _yard_fences(1 << 30)
	prop_stats.recovered = int(prop_stats.get("recovered", 0)) + got
	prop_stats.dropped -= got
	if OS.is_debug_build():
		print("[Pueblo] recover: %d/%d trade props into gaps of their yards, %d lattice points free, %d ms" % [got, items.size(), _lat_free.size(), Time.get_ticks_msec() - t0])


func yard_fit(rc: Rect2, want: Vector2, house: Node3D = null, reach := RECOVER_REACH, rots := [], near_house := 1.5, only_tiles := {}) -> Array:
	## The best gap of the yards for a footprint rc (the piece's local x/z rectangle) near `want` (godot x/z): [at
	## (godot x/z), yaw in degrees], [] if none within `reach`. Along a wall when one is near (unless `rots` gives the
	## yaws to try); with `house`, only within near_house m of that house. yard_take() marks it used.
	_lat_build()
	var best := Vector2.INF
	var best_rot := 0.0
	var best_s := 1e9
	var cands: Array = _lat_free.keys()
	for kk in cands.size() * 2:
		var k: Vector2i = cands[kk / 2]
		if _lat_used.has(k):
			continue
		var g := Vector2((k.x + 0.5) * LAT, (k.y + 0.5) * LAT) if kk % 2 == 0 else Vector2(k.x * LAT, k.y * LAT)
		var dist := g.distance_to(want)
		if dist > reach or dist - 1.5 >= best_s:
			continue
		if house != null and _house_at_plan(Vector2(g.x, -g.y), near_house) != house:
			continue
		if not only_tiles.is_empty() and not only_tiles.has(Vector2i(floori(g.x / 2.0), floori(g.y / 2.0))):
			continue
		var wy: float = _lat_wall.get(k, NAN)
		var s := dist - (1.5 if not is_nan(wy) else 0.0)
		if s >= best_s:
			continue
		var tries: Array = rots if not rots.is_empty() else ([0.0, 90.0] if is_nan(wy) else [wy, wy + 180.0, wy + 90.0, wy + 270.0])
		for ro in tries:
			if _fits(rc, g, ro):
				best = g
				best_rot = ro
				best_s = s
				break
	return [] if best == Vector2.INF else [best, best_rot]


func yard_take(rc: Rect2, at: Vector2, rot: float, grow := 0.12) -> void:
	for k in _foot_cells(rc, at, rot, grow):
		_lat_used[k] = true


func lat_open(g: Vector2) -> bool:
	## godot x/z point on free yard ground (no house, no prop, no fence, no post)
	var k := Vector2i(floori(g.x / LAT), floori(g.y / LAT))
	return _lat_free.has(k) and not _lat_used.has(k) and not _lat_posts.has(k)


func _recover_props() -> void:
	## last: the loose props with no free spot near their 2D place, into the gaps the yards still have
	var t0 := Time.get_ticks_msec()
	_lat_build()
	var fences := 0
	var items := []
	for d in _dropped:
		if String(d.name) == "Prop_WoodenFence_Single":
			fences += 1
		elif not d.get("tried", false):
			items.append(d)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _footprint(a.kind, a.name).get_area() > _footprint(b.kind, b.name).get_area())
	var got := 0
	var cands: Array = _lat_free.keys()
	var got_f := mini(_fences_made, fences)
	for d in items:
		if _recover_one(d, cands):
			got += 1
	prop_stats.recovered = int(prop_stats.get("recovered", 0)) + got + got_f
	prop_stats.dropped -= got + got_f
	if OS.is_debug_build():
		print("[Pueblo] recover: %d/%d props into gaps off the walkable tiles, %d/%d fence pieces round the yards, %d lattice points free, %d ms" % [
			got, items.size(), got_f, fences, _lat_free.size(), Time.get_ticks_msec() - t0])


func _recover_one(d: Dictionary, cands: Array) -> bool:
	## puts one dropped prop in the best gap near its 2D place (along a wall if there is one); false if none
	var rc := _footprint(d.kind, d.name)
	var want := Vector2(d.want.x, -d.want.y)  # godot x/z
	var best := Vector2.INF
	var best_rot := 0.0
	var best_s := 1e9
	for kk in cands.size() * 2:
		var k: Vector2i = cands[kk / 2]
		if _lat_used.has(k):
			continue
		# cell centres and cell corners (a corner can be a tile centre: a 1.8 m bed fits a 2 m tile only there)
		var g := Vector2((k.x + 0.5) * LAT, (k.y + 0.5) * LAT) if kk % 2 == 0 else Vector2(k.x * LAT, k.y * LAT)
		var dist := g.distance_to(want)
		if dist > RECOVER_REACH or dist - 1.5 >= best_s:
			continue
		if d.house != null and _house_at_plan(Vector2(g.x, -g.y), 1.5) != d.house:
			continue  # a trade prop stays against its own building
		var wy: float = _lat_wall.get(k, NAN)
		var s := dist - (1.5 if not is_nan(wy) else 0.0)
		if s >= best_s:
			continue
		var rots := [d.rot] if is_nan(wy) else [wy, wy + 180.0, wy + 90.0, wy + 270.0]
		for ro in rots:
			if _fits(rc, g, ro):
				best = g
				best_rot = ro
				best_s = s
				break
	if best == Vector2.INF:
		if OS.is_debug_build():
			print("[Pueblo] recover: no gap for %s near %s" % [d.name, d.want])
		return false
	for k in _foot_cells(rc, best, best_rot, 0.12):
		_lat_used[k] = true
	var v := Vector3(best.x, -best.y, 0)
	var n: Node3D
	if d.kind == "q":
		n = load(QPROPS % d.name).instantiate()
		n.position = HouseBuilder.plan_to_godot(v)
		n.rotation.y = deg_to_rad(best_rot)
		_q.add_child(n)
	else:
		n = HouseBuilder._piece(d.name, _q, v, best_rot)
	n.set_meta("recovered", true)
	_prop_spots.append(Vector2(best.x, -best.y))
	if OS.is_debug_build():
		print("[Pueblo] recover: %s from %s to tile %s (%.1f m, yaw %.0f%s)" % [d.name, d.want, Vector2i(floori(best.x / 2.0), floori(best.y / 2.0)),
			best.distance_to(want), best_rot, ", along a wall" if _lat_wall.has(Vector2i(floori(best.x / LAT), floori(best.y / LAT))) else ""])
	return true


func _yard_fences(budget: int) -> int:
	## The yard fence: one piece along every yard edge that faces a walkable tile, FENCE_IN m inside the yard (flush with
	## the facades on the street side: the houses stand on the edge of their footprint); where the full piece would cut a
	## corner a diagonal step crosses, a shorter piece away from that corner. Returns the pieces that stand for the 2D
	## fences (at most `budget`); the rest count in prop_stats.yard_fence.
	var made := 0
	var keys := yard_tiles.keys()
	keys.sort()
	for k: Vector2i in keys:
		for e in [[Vector2i(0, -1), 0.0], [Vector2i(0, 1), 0.0], [Vector2i(-1, 0), 90.0], [Vector2i(1, 0), 90.0]]:
			var nb: Vector2i = k + e[0]
			if not walkable(nb.x, nb.y):
				continue
			var ctr := Vector2(k.x * 2.0 + 1.0, k.y * 2.0 + 1.0) + Vector2(e[0]) * (1.0 - FENCE_IN)
			var along := Vector2(1, 0) if e[1] == 0.0 else Vector2(0, 1)
			var done := false
			for v in FENCE_FITS:  # [scale along, shift along (m)]
				var half := 0.97 * float(v[0]) / 0.94
				var rc := Rect2(-half, -0.06, half * 2.0, 0.12)
				var at: Vector2 = ctr + along * float(v[1])
				if not _fits(rc, at, e[1], true):
					continue
				for c in _foot_cells(rc, at, e[1], 0.0):
					_lat_used[c] = true  # no margin: the pieces of one edge line touch end to end
				var n := HouseBuilder._piece("Prop_WoodenFence_Single", _q, Vector3(at.x, -at.y, 0), e[1])
				n.scale.x = float(v[0])
				n.set_meta("recovered", true)
				n.set_meta("yard_fence", true)
				_fence_pieces.append({node = n, tile = k, edge = e[0], at = ctr})
				made += 1
				done = true
				break
			if OS.is_debug_build() and not done:
				print("[Pueblo] fence: no room on the edge of yard tile %s facing %s" % [k, nb])
	prop_stats.yard_fence = made
	prop_stats.gates = _yard_gates()
	if OS.is_debug_build():
		print("[Pueblo] fence: %d pieces round the yards, %d of them gates" % [made, prop_stats.gates])
	return mini(made, budget)


var _fence_pieces: Array = []  # the fence pieces of the yards: [{node, tile, edge: Vector2i towards the street, at: godot x/z of the middle of that edge}]
const STONE_GATE_TYPES := ["church", "town_hall", "armory", "bank"]


func _yard_gates() -> int:
	## One gate per yard (a run of touching yard tiles beside a house): of its fence pieces, the one that faces a street
	## (road, path or plaza; any walked tile if none) nearest the door of its house, first on the side the door looks
	## at, becomes a gate of kit/modules as wide as the tile, with the yard on its hinge side: the timber gate, or the
	## stone gateway on the yards of STONE_GATE_TYPES. Not on an edge whose end a diagonal step cuts (the fence there
	## is a short piece away from that corner).
	var comp_of := {}
	var n_comp := 0
	for k0: Vector2i in yard_tiles:
		if comp_of.has(k0):
			continue
		var stack := [k0]
		comp_of[k0] = n_comp
		while not stack.is_empty():
			var t: Vector2i = stack.pop_back()
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = t + dv
				if yard_tiles.has(q) and not comp_of.has(q):
					comp_of[q] = n_comp
					stack.append(q)
		n_comp += 1
	var by_comp := {}
	for f: Dictionary in _fence_pieces:
		var ci: int = comp_of.get(f.tile, -1)
		var al := Vector2(1, 0) if (f.edge as Vector2i).x == 0 else Vector2(0, 1)
		var whole := true
		for sg in [-0.9, 0.9]:
			var g: Vector2 = (f.at as Vector2) + al * sg
			whole = whole and _lat_free.has(Vector2i(floori(g.x / LAT), floori(g.y / LAT)))
		if not whole:
			continue
		if not by_comp.has(ci):
			by_comp[ci] = []
		by_comp[ci].append(f)
	var owners := {}  # comp -> {house: tiles of the yard beside it}
	for t: Vector2i in comp_of:
		var h := _house_at_plan(_tp(t.x, t.y), 1.2)
		if h != null:
			var ci: int = comp_of[t]
			if not owners.has(ci):
				owners[ci] = {}
			owners[ci][h] = int(owners[ci].get(h, 0)) + 1
	var made := 0
	var comps := by_comp.keys()
	comps.sort()
	if OS.is_debug_build():
		print("[Pueblo] gate: %d yards, %d with a whole edge to the street, %d beside a house" % [n_comp, by_comp.size(), owners.size()])
	for ci: int in comps:
		if not owners.has(ci):
			continue
		var owner: Node3D = null
		for h: Node3D in owners[ci]:
			if owner == null or int(owners[ci][h]) > int(owners[ci][owner]):
				owner = h
		var dd := _door(owner)
		var door_g := Vector2((dd[0] as Vector2).x, -(dd[0] as Vector2).y)
		var out_t := Vector2i(roundi((dd[1] as Vector2).x), -roundi((dd[1] as Vector2).y))
		var best := {}
		var bs := 1e9
		for f: Dictionary in by_comp[ci]:
			var nb: Vector2i = (f.tile as Vector2i) + (f.edge as Vector2i)
			var sc: float = (f.at as Vector2).distance_to(door_g) + (0.0 if _t(nb.x, nb.y) in ["=", ",", "P"] else 30.0) + (0.0 if f.edge == out_t else 3.0)
			if sc < bs:
				bs = sc
				best = f
		if best.is_empty():
			continue
		var e: Vector2i = best.edge
		# the gate's leaves hang on the left of its +x: the yard goes there (it lies opposite the edge)
		var rot := 180.0 if e == Vector2i(0, -1) else (0.0 if e == Vector2i(0, 1) else (270.0 if e == Vector2i(-1, 0) else 90.0))
		var piece := "Prop_StoneGate" if String(owner.get_meta("type", "")) in STONE_GATE_TYPES else "Prop_WoodenFence_Gate"
		var at: Vector2 = best.at
		var g := HouseBuilder._piece(piece, _q, Vector3(at.x, -at.y, 0), rot)
		if g == null:
			continue
		g.scale.x = 0.94
		g.set_meta("recovered", true)
		g.set_meta("yard_fence", true)
		g.set_meta("gate", true)
		(best.node as Node3D).free()
		best.node = g
		best["gate"] = true
		_mark_disc(at - Vector2(e) * 0.9, 0.75)  # the way in behind the gate stays clear
		made += 1
		if OS.is_debug_build():
			print("[Pueblo] gate: %s on yard tile %s facing %s, %.1f m from the door of %s" % [piece, best.tile, (best.tile as Vector2i) + e, at.distance_to(door_g), owner.name])
	return made


const FENCE_IN := 0.14
const FENCE_FITS := [[0.94, 0.0], [0.6, 0.32], [0.6, -0.32], [0.45, 0.45], [0.45, -0.45]]


## Seats where the sim sits people: one bench along the slots of each "bench" social point and a stool per slot of a
## "dice" point round a small crate. They sit on walkable tiles on purpose (the sim puts the sitters there), pushed
## 0.7 m towards the side of the slots fewer people walk by (_tile_traffic); sim3d_chars sits on them whoever the
## trace has on a slot, and steers walkers round them (sim3d.gd avoid()).
## seats: "<point id>|<slot>" -> {pos: plan, dir: plan direction the sitter faces, kind: bench|stool, top: seat height}
## seat_obstacles: [[plan a, plan b, radius]] (a capsule; a == b for a round one).
var seats := {}
var seat_obstacles: Array = []


func _tile_traffic() -> Dictionary:
	## Vector2i tile -> how many walkers cross it (sim3d fills it from the trace); empty here
	return {}


func _corner_traffic() -> Dictionary:
	## Vector2i corner (the point where tiles (c-1, r-1), (c, r-1), (c-1, r) and (c, r) meet) -> diagonal steps that cut
	## it (sim3d fills it from the trace); empty here
	return {}


func _seats() -> void:
	var traffic := _tile_traffic()
	var load_of := func(t: Vector2i) -> int:
		if not walkable(t.x, t.y):
			return -1  # a wall or a stall: nobody walks there
		return int(traffic.get(t, 0))
	for sp in mapd.get("social_points", []):
		var kind := String(sp.get("kind", ""))
		if kind != "bench" and kind != "dice":
			continue
		var slots: Array = sp.slots
		var pts: Array[Vector2] = []
		var tiles: Array[Vector2i] = []
		for s in slots:
			pts.append(_tp(float(s[0]), float(s[1])))
			tiles.append(Vector2i(int(s[0]), int(s[1])))
		var centre := Vector2.ZERO
		for q in pts:
			centre += q
		centre /= pts.size()
		# the quietest of the four sides of the group: traffic over the slots' neighbours on that side
		var best := Vector2i(1, 0)
		var best_load := 1 << 30
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := 0
			for t in tiles:
				if tiles.has(t + d):
					continue
				n += load_of.call(t + d)
			if n < best_load:
				best_load = n
				best = d
		var shift := Vector2(best.x, -best.y) * 0.7  # tile step -> plan (rows grow southwards = -y)
		if kind == "bench":
			var along := (pts[-1] - pts[0]).normalized() if pts.size() > 1 else Vector2(-shift.y, shift.x).normalized()
			var normal := -shift.normalized()  # the sitters face away from the quiet side, towards the passers
			if absf(normal.dot(along)) > 0.5:
				normal = Vector2(-along.y, along.x)
			var mid := centre + shift
			var n := _seat_piece("q", "Bench", mid, rad_to_deg(atan2(along.y, along.x)))
			n.scale = Vector3(1, 1.11, 1)  # seat top 0.53 -> 0.59 m, the height of the own sit_stool pose
			n.set_meta("seat", true)
			var half := maxf(1.0, pts[0].distance_to(pts[-1]) / 2.0)
			seat_obstacles.append([mid - along * 1.35, mid + along * 1.35, 0.3])
			for i in pts.size():
				var on := mid + along * clampf((pts[i] - centre).dot(along), -half, half)
				seats["%s|%d" % [sp.id, i]] = {pos = on, dir = normal, kind = "bench", top = 0.59}
		else:
			var mid := centre + shift
			var table := _seat_piece("q", "Crate_Wooden", mid, 15.0)
			table.scale = Vector3(0.6, 0.55, 0.6)
			table.set_meta("seat", true)
			seat_obstacles.append([mid, mid, 1.25])  # the whole group: walkers go round it, not between the stools
			for i in pts.size():
				var dir := (centre - pts[i]).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2(1, 0)
				var at := mid - dir * 0.95
				var n := _seat_piece("q", "Stool", at, 0.0)
				n.set_meta("seat", true)
				seats["%s|%d" % [sp.id, i]] = {pos = at, dir = dir, kind = "stool", top = 0.58}
	if OS.is_debug_build():
		print("[Pueblo] %d seats at the sim's bench/dice slots (%d obstacles)" % [seats.size(), seat_obstacles.size()])


func _seat_piece(kind: String, name: String, p: Vector2, rot: float) -> Node3D:
	if kind == "q":
		if not ResourceLoader.exists(QPROPS % name):
			return null
		var n: Node3D = load(QPROPS % name).instantiate()
		n.position = HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0))
		n.rotation.y = deg_to_rad(rot)
		_q.add_child(n)
		return n
	return HouseBuilder._piece(name, _q, Vector3(p.x, p.y, 0), rot)


func _free_tile(c: int, r: int) -> bool:
	if _t(c, r) != "." and _t(c, r) != "T":
		return false
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if _t(c + dc, r + dr) in ["#", "=", "P", "S", "w", "b"]:
				return false
	return true


## The wood round the map, outside it: trees per tile. It was 0.22 before the map's own decor trees were planted (72 in
## town_e, most along its edges and the river): with them the wood is as thick with fewer, and trees are what the far
## view pays most for (5.9 of its 16 ms at 1600 x 900, out/p3_fpsprof.json).
const RING_TREES := 0.16


func _town_trees() -> void:
	vivo.trees()  # the trees, bushes and hedges the 2D map draws as decor, each on its tile
	var q_trees := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3"]
	var mine := ["roble", "frutal", "chopo", "pino"]
	for r in range(-6, H + 6):
		for c in range(-6, W + 6):
			var inside := r >= 0 and r < H and c >= 0 and c < W
			var want := false
			if inside:
				want = _t(c, r) == "T"  # random trees only outside the map: every grass tile is walkable for the sim
			else:
				want = rng.randf() < (RING_TREES if vivo.on() else 0.22)
			if not want:
				continue
			var p := _tp(c + rng.randf_range(-0.3, 0.3), r + rng.randf_range(-0.3, 0.3))
			var t: Node3D
			if rng.randf() < 0.55:
				t = load(QNATURE % q_trees[rng.randi() % q_trees.size()]).instantiate()
			else:
				var fam: String = mine[rng.randi() % mine.size()]
				_tree_materials(fam)
				t = load("res://kit/trees/%s_%d.glb" % [fam, rng.randi() % 3]).instantiate()
				_skin_tree(t, fam)
			t.position = HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0))
			t.rotation.y = rng.randf() * TAU
			t.scale = Vector3.ONE * rng.randf_range(0.8, 1.15)
			t.add_to_group("tree")
			add_child(t)


func _town_nature() -> void:
	var kinds := {"Grass_Common_Short": 900, "Grass_Common_Tall": 300, "Grass_Wispy_Short": 400, "Grass_Wispy_Tall": 180,
		"Flower_3_Group": 140, "Flower_4_Group": 140, "Clover_1": 200, "Fern_1": 90, "Bush_Common_Flowers": 50,
		"Rock_Medium_1": 12, "Rock_Medium_2": 12, "Pebble_Round_2": 90, "Pebble_Square_3": 60, "Mushroom_Common": 40, "Plant_1": 60}
	for kind in kinds:
		var src := _first_mesh(load(QNATURE % kind).instantiate())
		if src == null:
			continue
		var small: bool = kind.begins_with("Grass") or kind.begins_with("Flower") or kind.begins_with("Clover") or kind.begins_with("Fern") or kind.begins_with("Plant")
		var xs: Array[Transform3D] = []
		var tries := 0
		var want: int = kinds[kind]
		while xs.size() < want and tries < want * 30:
			tries += 1
			var c := rng.randf_range(-6, W + 6)
			var r := rng.randf_range(-6, H + 6)
			if not _free_tile(int(floor(c)), int(floor(r))):
				continue
			var p := Vector2(c * 2.0, -r * 2.0)
			var sc := rng.randf_range(0.4, 0.7) if small else rng.randf_range(0.7, 1.2)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0))))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.add_to_group("tree")
		add_child(mmi)


func set_season(i: int) -> void:
	super(i)
	for wm in _water:
		wm.set_shader_parameter("frozen", 1.0 if SEASONS[season] == "invierno" else 0.0)


# ---------------------------------------------------------------- screenshots
func _town_shots() -> void:
	var plaza := Vector3(40, 2, 40)
	for shot in [["town_vista.png", Vector3(W, 2, H), 74.0, 45.0, 0], ["town_vista_otro_lado.png", Vector3(W, 2, H), 74.0, 225.0, 0],
			["town_plaza.png", plaza, 30.0, 45.0, 0], ["town_rio.png", Vector3(72, 1, 38), 26.0, 45.0, 0],
			["town_otono.png", Vector3(W, 2, H), 74.0, 45.0, 1], ["town_invierno.png", Vector3(W, 2, H), 74.0, 45.0, 2]]:
		set_season(int(shot[4]))
		target = shot[1]
		cam.size = shot[2]
		yaw = shot[3]
		_update_camera()
		await _snap(shot[0])
	get_tree().quit()
