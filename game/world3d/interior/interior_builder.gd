class_name Interior3DBuilder
extends RefCounted
## Builds a cutaway 3D interior from a GuildMaster interior file (data/interiors/<building>.json, copied from
## GuildMaster: same fields, same meaning as tools/interiors/interiores.py there).
##
## Grid mapping: one interior tile = one kit wall module = 2 m (TILE). Tile (c, r) has its centre at
## x = c*2+1, z = r*2+1; col grows toward +x, row toward +z, so the 2D camera (looking from high col/row toward
## the back walls nw/ne) is a camera at +x+z looking at -x-z (yaw 45). A floor is 3.12 m (the kit's wall
## height): wall_height (64 px) is the kit's full wall, floor_height (80 px) is drawn in 2D as wall + slab, here
## the slab sits inside the 3.12 m. A one-step level (levels[].step) is STEP m.
## Walls come out of the rooms as in interiores.py: an edge between two rooms is an inner wall (or a door if
## listed), an edge with no room on the other side is an exterior wall. Every wall knows its plan normal, so the
## cutaway can lower whichever side faces the camera after a 90 degree turn.

## Metres per tile and per floor. The big interiors (GuildMaster's 2D data as it is) use 2 m and 3.12 m; an interior in
## place (data with "tile_m" and "shell": docs/interior3d.md) brings its own tile and stands on the house's 3 m floors.
var TILE := 2.0
var FLOOR_H := 3.12
const STEP := 0.35
const BLOCK_SHARE := 0.1  # compact interiors: a tile is blocked when a piece covers more than this share of it
const LOW_H := 0.85  # height of a lowered wall
const VILLAGE := "res://kit/village/%s.gltf"
const QP := "res://kit/q_props/Exports/glTF/%s.gltf"
const WALL_SHADER := "res://game/world3d/shaders/interior_wall.gdshader"
const MUEBLES := "res://kit/muebles/%s.gltf"  # furniture at real scale (tools/make_muebles.py)
const MUEBLES_DATA := "res://game/world3d/kit_data/interiors/muebles.json"
const WALL_IN := 0.33  # from the line of an outer wall of the house to where a piece set against it stands (the kit wall is 0.31 m inside its line)
const SNAP_OUT := {"back": Vector2(0, -1), "front": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}  # local x, z
const SNAP_ROT := {"back": 0.0, "front": 180.0, "left": 90.0, "right": -90.0}
## plan boxes [x0, z0, x1, z1] of the pieces of the kits an upgrade may bring (those of kit/muebles are in its catalogue)
const KIT_BOX := {"q:BookStand": [-0.26, -0.26, 0.26, 0.26], "barrel": [-0.35, -0.35, 0.35, 0.35], "q:Barrel": [-0.35, -0.35, 0.35, 0.35],
	"q:FarmCrate_Apple": [-0.36, -0.21, 0.36, 0.21], "q:Bucket_Wooden_1": [-0.22, -0.2, 0.22, 0.18], "sack": [-0.33, -0.24, 0.33, 0.3],
	"sack_pile": [-0.69, -0.31, 0.67, 0.31], "crates_small": [-0.45, -0.47, 0.45, 0.47], "_anvil": [-0.33, -0.32, 0.7, 0.32],
	"stone_trough": [-0.48, -0.18, 0.48, 0.18], "q:Book_Stack_2": [-0.14, -0.1, 0.13, 0.13]}

## GuildMaster prop id -> 3D pieces: [piece, offset (local: x right, y up, z front), rot deg, scale]
## "@name" = res://kit/props/name.glb, "q:Name" = Fantasy Props MegaKit, "box:..." = a simple prop.
const PIECES := {
	"shop_counter": [["q:Table_Large", Vector3(0, 0, 0), 0, Vector3(1.35, 1.12, 1.0)], ["q:Cabinet", Vector3(0, 0, 0.22), 0, Vector3(2.6, 0.9, 1.4)]],
	"crate_stack": [["q:Crate_Wooden", Vector3(-0.3, 0, 0), 10, Vector3.ONE], ["q:Crate_Wooden", Vector3(0.35, 0, 0.1), -8, Vector3.ONE],
		["q:Crate_Wooden", Vector3(0.0, 0.88, 0.0), 25, Vector3(0.9, 0.9, 0.9)]],
	"display_shelf": [["q:WeaponStand", Vector3(-0.9, 0, 0), 0, Vector3.ONE], ["q:WeaponStand", Vector3(0.9, 0, 0), 0, Vector3.ONE],
		["q:Sword_Bronze", Vector3(-1.2, 0.35, 0.05), 0, Vector3.ONE], ["q:Sword_Bronze", Vector3(-0.6, 0.35, 0.05), 0, Vector3.ONE],
		["q:Axe_Bronze", Vector3(0.65, 0.55, 0.05), 0, Vector3(1.3, 1.3, 1.3)], ["q:Sword_Bronze", Vector3(1.2, 0.35, 0.05), 0, Vector3.ONE]],
	"weapon_display": [["q:WeaponStand", Vector3(0, 0, 0), 0, Vector3.ONE], ["q:Sword_Bronze", Vector3(-0.3, 0.35, 0.05), 0, Vector3.ONE],
		["q:Sword_Bronze", Vector3(0.3, 0.35, 0.05), 0, Vector3.ONE]],
	"candle_stand": [["q:CandleStick_Stand", Vector3.ZERO, 0, Vector3(1.2, 1.2, 1.2)]],
	"armor_stand_forge": [["q:Dummy", Vector3.ZERO, 0, Vector3.ONE], ["q:Shield_Wooden", Vector3(0.0, 1.05, 0.28), 0, Vector3.ONE]],
	"banner_stand": [["box:post", Vector3.ZERO, 0, Vector3(0.1, 2.5, 0.1)], ["q:Banner_1", Vector3(-0.05, 2.45, 0.08), 0, Vector3(0.8, 0.8, 0.8)]],
	"kitchen_hearth": [["box:hearth", Vector3.ZERO, 0, Vector3(1.6, 0.5, 1.2)], ["q:Cauldron", Vector3(0, 0.5, 0), 0, Vector3(0.9, 0.9, 0.9)]],
	"crockery_shelf": [["q:Cabinet", Vector3.ZERO, 0, Vector3.ONE], ["q:Pot_1", Vector3(-0.3, 1.0, 0), 0, Vector3.ONE], ["q:Mug", Vector3(0.3, 1.0, 0), 0, Vector3.ONE]],
	"pantry_shelf": [["q:Bookcase_2", Vector3.ZERO, 0, Vector3(1.0, 0.8, 1.0)]],
	"kitchen_table": [["q:Table_Large", Vector3.ZERO, 0, Vector3.ONE]],
	"dining_table": [["q:Table_Large", Vector3.ZERO, 0, Vector3.ONE]],
	"stool": [["q:Stool", Vector3.ZERO, 0, Vector3.ONE]],
	"bed_double": [["q:Bed_Twin1", Vector3(-0.85, 0, -0.1), 0, Vector3(0.88, 0.88, 0.85)], ["q:Bed_Twin1", Vector3(0.85, 0, -0.1), 0, Vector3(0.88, 0.88, 0.85)]],
	"bunk_bed": [["q:Bed_Twin2", Vector3.ZERO, 0, Vector3.ONE]],
	"cradle": [["q:Chest_Wood", Vector3.ZERO, 0, Vector3(0.7, 0.8, 0.7)]],
	"chest": [["q:Chest_Wood", Vector3.ZERO, 0, Vector3.ONE]],
	"strongbox": [["q:Chest_Wood", Vector3.ZERO, 0, Vector3(0.8, 0.8, 0.8)]],
	"wardrobe": [["q:Cabinet", Vector3.ZERO, 0, Vector3(1.0, 2.0, 1.4)]],
	"sack_pile": [["@sacos", Vector3.ZERO, 0, Vector3.ONE]],
	"sack": [["q:Bag", Vector3.ZERO, 0, Vector3.ONE]],
	"big_jar": [["q:Vase_4", Vector3.ZERO, 0, Vector3(1.5, 1.5, 1.5)]],
	"barrel": [["q:Barrel", Vector3.ZERO, 0, Vector3.ONE]],
	"water_barrel": [["q:Barrel", Vector3.ZERO, 0, Vector3.ONE]],
	"firewood_pile": [["@lena", Vector3.ZERO, 0, Vector3(0.9, 0.9, 0.9)]],
	"coal_sack": [["@carbon", Vector3.ZERO, 0, Vector3.ONE]],
	"ingot_stack": [["box:ingots", Vector3.ZERO, 0, Vector3.ONE]],
	"ingot_pile": [["box:ingots_low", Vector3.ZERO, 0, Vector3.ONE]],
	"tongs": [["box:tongs", Vector3.ZERO, 0, Vector3.ONE]],
	"coin_pile": [["q:Coin_Pile", Vector3.ZERO, 0, Vector3(2, 2, 2)]],
	"bowl_stew": [["q:Pot_1", Vector3.ZERO, 0, Vector3.ONE]],
	"horseshoe_nails": [["q:Peg_Rack", Vector3.ZERO, 0, Vector3.ONE]],
	"banner_wall": [["q:Banner_2", Vector3(-0.6, 0.6, 0), 0, Vector3(0.75, 0.75, 0.75)]],
	"tapestry_red": [["q:Banner_1_Cloth", Vector3(-0.6, 0.6, 0), 0, Vector3(0.75, 0.75, 0.75)]],
	"staircase": [["v:Stair_Interior_Solid", Vector3.ZERO, 0, Vector3.ONE]],
	"_furnace": [["@fragua", Vector3(0.3, 0, 0.1), 0, Vector3(0.95, 0.95, 0.95)]],
	# a size up from the furnace, moved off the walls it stands against (it went 0.14 m into the back one); the log that
	# stood by it took the place of whoever works the furnace
	"_furnace_master": [["@fragua", Vector3(0.45, 0, 0.15), 0, Vector3(1.05, 1.12, 1.05)]],
	"_anvil": [["@yunque", Vector3.ZERO, 0, Vector3.ONE]],
	"bellows": [["q:Bag", Vector3.ZERO, 90, Vector3(1.2, 0.6, 1.2)]],
	"quench_tub": [["q:Bucket_Wooden_1", Vector3.ZERO, 0, Vector3(2.4, 2.4, 2.4)]],
	"stone_trough": [["@abrevadero", Vector3.ZERO, 0, Vector3(0.6, 0.6, 0.6)]],
	"market_shelf": [["q:Bookcase_2", Vector3(-0.8, 0, 0), 0, Vector3.ONE], ["q:Bookcase_2", Vector3(0.8, 0, 0), 0, Vector3.ONE]],
	"master_bench": [["q:Workbench", Vector3.ZERO, 0, Vector3(0.8, 1, 0.8)]],
	"engraving_bench": [["q:Workbench", Vector3.ZERO, 0, Vector3(0.8, 1, 0.8)]],
	# compact interiors (interior in place): pieces at their real size, fewer of them
	"bed": [["q:Bed_Twin1", Vector3.ZERO, 0, Vector3.ONE]],
	"crates_small": [["q:Crate_Wooden", Vector3(0, 0, 0), 8, Vector3(0.8, 0.8, 0.8)], ["q:Crate_Wooden", Vector3(0.05, 0.95, 0.0), 30, Vector3(0.6, 0.6, 0.6)]],
	"hearth_small": [["box:hearth", Vector3.ZERO, 0, Vector3(1.0, 0.45, 0.8)], ["q:Cauldron", Vector3(0, 0.45, 0), 0, Vector3(0.75, 0.75, 0.75)]],
	"flue": [["box:flue", Vector3.ZERO, 0, Vector3(0.72, 3.0, 0.9)]],
}
## station zone -> prop when the station has none in the data (the 2D draws them with the station art)
const STATION_PIECE := {"furnace": "_furnace", "furnace_2": "_furnace", "anvil": "_anvil", "anvil_2": "_anvil"}
const FLOOR_PIECE := {"planks": "Floor_WoodDark", "stone": "Floor_Brick", "rug": "Floor_RedBrick"}
const FLOOR_TEX := {"flagstone": "res://kit/streets/losas_albedo.png", "earth": "res://kit/streets/tierra_albedo.png"}
const WALL_PIECE := {"stone": "UnevenBrick", "timber": "Plaster"}
const NAMES := {"workshop": "Taller", "storage": "Almacén", "shop": "Tienda", "kitchen": "Cocina", "bedroom": "Dormitorio",
	"furnace": "Fragua", "furnace_2": "Fragua 2", "anvil": "Yunque", "anvil_2": "Yunque 2", "counter": "Mostrador"}

var d: Dictionary
var cat: Dictionary
var lights_def: Dictionary
var W := 0
var H := 0
var floors: Array = []
var room_of := {}  # floor -> {Vector2i: room id}
var rooms := {}  # id -> room dict
var doors := {}  # "f|c|r|side" -> true
var step := {}  # "f|c|r" -> -1 / +1
var blocked := {}  # floor -> {Vector2i: true}
var placed: Array = []
var root: Node3D
var wall_groups: Array = []  # [{node, floor, normal: Vector2, kind, front, behind}]
var room_lights: Array = []  # [{light, room, def}]
var zones := {}  # zone id -> {tiles: [Vector2i], floor, stand: Vector2i, tile: Vector2i, kind}
var edge_group := {}  # "f|c|r|side" (back edges nw/ne of a tile) -> wall group
var _scenes := {}
## Own furniture (tools/make_furniture.py, data/props/ropa_muebles.json): GuildMaster id -> [piece spec, top height m]
## for every id a catalog entry lists in "pieces" and whose kit/props/<id>.glb exists; it replaces PIECES[id]
static var _own := {}
static var _own_loaded := false
var wall_shader: Shader  # null = WALL_SHADER; an interior in place uses the town's toon variant (SituCut.shader)
var in_situ := false  # the data has "shell": the house of the town is the outside; only partitions, pieces and lights are built
var compact := false  # the data has "tile_m": pieces placed by "pos"/"rot", tiles blocked by the real size of the pieces
var origin := Vector2.ZERO  # local x/z of the corner of tile (0, 0)
var open_pairs := {}  # "roomA|roomB" -> true: no wall between them, walk across anywhere
var obstacles := {}  # floor -> [Rect2 local x/z] of the pieces that block (compact: for clearance checks)
var stair_runs: Array = []  # compact: [{floor, to_floor, from: Vector2i, to: Vector2i, foot: Vector3, top: Vector3}]
var done_upgrades: Array = []  # ids of the finished upgrades (the sim's or the interior's nodes) whose pieces are shown
var upgrades_given := false  # a list of finished upgrades was given: the base pieces that stand for an upgrade wait for it
var upgrade_state := {}  # node -> {status: placed | fits | base | needs | none | no_room, where: [[floor, c, r]], note}
var _up_zones := {}  # zones that a finished upgrade added
var _ghosts: Array = []  # [{floor, rect, tall, blocks}] places of upgrade pieces not bought (explicit or base ones)
var _ghost_tiles: Array = []  # [[floor, Vector2i]] tiles kept free for them (where the worker of a zone will stand)
var _src_path := ""
var _autos: Array = []  # [{node, e, done}] upgrade pieces whose place is found here (auto), in the order of the data
var _ons: Array = []  # [{node, e}] finished upgrade pieces that go on top of a named piece
var _wall_used := {}  # floor -> [Rect2]: tall and hung pieces along the walls
var _res_tiles := {}  # floor -> {Vector2i: true}: tiles kept for upgrades not bought yet
var _res_stands := {}  # floor -> {Vector2i: true}: where the workers of the upgrades' stations stand: kept free and reachable
var hung: Array = []  # compact: [{node, floor, normal: Vector2 (local x, z, out of the wall it hangs on), base, top}]
const HANG_LOW := 0.92   # where a hung piece's top goes when its wall is lowered (a hand under SituCut.LOW_H, 0.95)
var fires: Array = []  # compact: [{floor, at: Vector3 (local), id}] where the light of a hearth or an oven goes
var zone_pos := {}  # zone -> Vector3 (local): the middle of the piece of a station
var named := {}  # prop "name" -> {pos: Vector3 (local), rot: degrees, id, floor}: seats and beds the cast is sent to
static var _muebles := {}
static var _muebles_loaded := false
static var _fx_mats := {}
var _holders: Array = []  # [piece dict, holder node]
var beds_placed: Array = []  # [{pos (local), rot, id, floor}] of every piece one lies on (the game's inn beds: Inn3D)
var _wall_mats := {}
var _simple_mats := {}
var _rng := RandomNumberGenerator.new()


static func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[Interior] " + msg)


## opts: mirror (the interior reflected left to right: SituShell.mirrored), upgrades (the ids of the finished upgrades of
## the building: only their pieces are shown)
func _init(path: String, catalog_path := "res://data/view3d/interiors/props_catalog.json", lights_path := "res://data/view3d/interiors/lights.json", opts := {}) -> void:
	d = JSON.parse_string(FileAccess.get_file_as_string(path))
	_src_path = path
	if opts.get("mirror", false):
		d = SituShell.mirrored(d)
	if opts.get("upgrades", null) != null:
		upgrades_given = true
		done_upgrades = opts.upgrades
	cat = JSON.parse_string(FileAccess.get_file_as_string(catalog_path)).props
	lights_def = JSON.parse_string(FileAccess.get_file_as_string(lights_path)).lights
	W = int(d.size[0])
	H = int(d.size[1])
	compact = d.has("tile_m")
	in_situ = d.has("shell")
	if compact:
		TILE = float(d.tile_m)
	if in_situ:
		FLOOR_H = 3.0  # HouseBuilder stacks its floors every 3 m
	var om: Array = d.get("origin_m", [0, 0])
	origin = Vector2(float(om[0]), float(om[1]))
	for pair in d.get("open", []):
		open_pairs["%s|%s" % [pair[0], pair[1]]] = true
		open_pairs["%s|%s" % [pair[1], pair[0]]] = true
	_rng.seed = int(d.get("seed", 1))
	for room in d.rooms:
		rooms[room.id] = room
		var f := int(room.floor)
		if not room_of.has(f):
			room_of[f] = {}
			floors.append(f)
		for rc in room.rects:
			for r in range(int(rc[1]), int(rc[3]) + 1):
				for c in range(int(rc[0]), int(rc[2]) + 1):
					room_of[f][Vector2i(c, r)] = room.id
	floors.sort()
	for x in d.get("doors", []):
		doors["%d|%d|%d|%s" % [x.floor, x.tile[0], x.tile[1], x.side]] = true
	for lv in d.get("levels", []):
		var rc: Array = lv.rect
		for r in range(int(rc[1]), int(rc[3]) + 1):
			for c in range(int(rc[0]), int(rc[2]) + 1):
				step["%d|%d|%d" % [lv.floor, c, r]] = int(lv.step)
	_upgrades(bool(d.get("show_upgrades", false)))
	placed = _placed(false)
	for f in floors:
		blocked[f] = {}
		obstacles[f] = []
	for p in placed:
		if compact:
			break  # by the real size of the pieces, once they are placed (_block_real)
		var pr: Dictionary = cat.get(p.id, {})
		if pr.get("walkable", false) or pr.get("hangs", false) or p.has("lift") or pr.get("category", "") == "small":
			continue
		for t in footprint(p):
			blocked[int(p.floor)][t] = true
	for s in d.get("stairs", []):
		if s.has("tiles"):  # compact: the tiles under the flight, and the hole over them on the floor it reaches
			for t in s.tiles:
				blocked[int(s.floor)][Vector2i(t[0], t[1])] = true
				blocked[int(s.to_floor)][Vector2i(t[0], t[1])] = true
			continue
		for t in footprint({"id": s.prop, "tile": s.tile, "flip": s.get("flip", false)}):
			blocked[int(s.floor)][t] = true
	for z in d.get("stations", {}):
		var s: Dictionary = d.stations[z]
		var tiles: Array = [Vector2i(s.tile[0], s.tile[1])]
		if s.has("prop") and not compact:
			tiles = footprint({"id": s.prop, "tile": s.tile, "flip": s.get("flip", false)})
		var st := stand(z)
		if not tiles.has(st):
			tiles.append(st)
		zones[z] = {"tiles": tiles, "floor": int(s.floor), "stand": st, "tile": Vector2i(s.tile[0], s.tile[1])}
	dbg("loaded %s: %dx%d, floors %s, %d rooms, %d doors, %d pieces, zones %s" % [path, W, H, floors, rooms.size(), doors.size(), placed.size(), zones.keys()])


# ------------------------------------------------------------------ layout (same rules as interiores.py)
func _placed(upgrades := false) -> Array:
	var out := []
	for p in d.get("props", []) + d.get("resolved", []):
		out.append(p.duplicate())
	for z in d.get("stations", {}):
		var s: Dictionary = d.stations[z]
		var e := {}
		if s.has("prop"):
			e = {"id": s.prop, "floor": s.floor, "tile": s.tile, "flip": s.get("flip", false), "zone": z}
		elif STATION_PIECE.has(z):
			e = {"id": STATION_PIECE[z], "floor": s.floor, "tile": s.tile, "flip": false, "zone": z}
		else:
			continue
		for k in ["pos", "rot", "snap", "gap", "flip_x"]:
			if s.has(k):
				e[k] = s[k]
		out.append(e)
	if compact:
		for p in out:
			resolve_prop(p, d)
	# upgrade stations (furnace_2, anvil_2) only exist with their upgrade
	var all_up := bool(d.get("show_upgrades", false))
	return out.filter(func(p): return not String(p.get("zone", "")).ends_with("_2") or all_up or _up_zones.has(String(p.get("zone", ""))))


## the catalogue of the furniture at real scale (data/interiors/muebles.json)
static func muebles() -> Dictionary:
	if not _muebles_loaded:
		_muebles_loaded = true
		var txt := FileAccess.get_file_as_string(MUEBLES_DATA)
		if txt != "":
			_muebles = JSON.parse_string(txt).get("props", {})
		dbg("furniture catalogue: %d pieces" % _muebles.size())
	return _muebles


## the plan box [x0, z0, x1, z1] of a piece of the catalogue round its origin, turned `rot` degrees (steps of 90)
static func turned_box(id: String, rot: float) -> Rect2:
	var b: Array = muebles().get(id, {}).get("box", KIT_BOX.get(id, [-0.45, -0.45, 0.45, 0.45]))
	var rc := Rect2()
	var first := true
	for c in [Vector2(b[0], b[1]), Vector2(b[2], b[1]), Vector2(b[2], b[3]), Vector2(b[0], b[3])]:
		var v := Vector3(c.x, 0, c.y).rotated(Vector3.UP, deg_to_rad(rot))
		if first:
			rc = Rect2(v.x, v.z, 0, 0)
			first = false
		else:
			rc = rc.expand(Vector2(v.x, v.z))
	return rc


## Compact interiors: a piece given by "tile" (the centre of that tile) and "snap" (the outer wall or walls of the
## house it stands against: back, front, left, right; the first one is the wall it looks away from) gets its "pos"
## and "rot" here, from the box of the catalogue: the same sum for the builder and for who prepares the shell.
static func resolve_prop(p: Dictionary, data: Dictionary) -> void:
	if not p.has("pos") and p.has("tile"):
		p["pos"] = [float(p.tile[0]), float(p.tile[1])]
	if not p.has("snap") or not p.has("pos") or not data.has("shell"):
		return
	var sides: PackedStringArray = String(p.snap).split(",", false)
	if not p.has("rot"):
		p["rot"] = SNAP_ROT.get(sides[0].strip_edges(), 0.0)
	var om: Array = data.get("origin_m", [0, 0])
	var tm := float(data.get("tile_m", 1.0))
	var at := Vector2(float(om[0]) + (float(p.pos[0]) + 0.5) * tm, float(om[1]) + (float(p.pos[1]) + 0.5) * tm)
	var rc := turned_box(String(p.id), float(p.rot))
	var hw := float(data.shell.w) / 2.0 - WALL_IN
	var hd := float(data.shell.d) / 2.0 - WALL_IN
	var gap := float(p.get("gap", 0.0))
	for sd in sides:
		match sd.strip_edges():
			"back": at.y = -hd - rc.position.y + gap
			"front": at.y = hd - rc.end.y - gap
			"left": at.x = -hw - rc.position.x + gap
			"right": at.x = hw - rc.end.x - gap
	p["pos"] = [(at.x - float(om[0])) / tm - 0.5, (at.y - float(om[1])) / tm - 0.5]
	p["wall"] = sides[0].strip_edges()


func footprint(p: Dictionary) -> Array:
	var fp: Array = cat.get(p.id, {}).get("footprint", [1, 1])
	var a := int(fp[0])
	var b := int(fp[1])
	var c := int(p.tile[0])
	var r := int(p.tile[1])
	var out := []
	for i in a:
		for j in b:
			out.append(Vector2i(c - i, r - j) if p.get("flip", false) else Vector2i(c - j, r - i))
	return out


func stand(zone: String) -> Vector2i:
	var s: Dictionary = d.stations[zone]
	if s.has("stand"):
		return Vector2i(s.stand[0], s.stand[1])
	return Vector2i(int(s.tile[0]) - 1, int(s.tile[1]))


func room_at(f: int, t: Vector2i) -> String:
	return room_of.get(f, {}).get(t, "")


func step_at(f: int, t: Vector2i) -> int:
	return step.get("%d|%d|%d" % [f, t.x, t.y], 0)


func is_door(f: int, t: Vector2i, side: String) -> bool:
	return doors.has("%d|%d|%d|%s" % [f, t.x, t.y, side])


func passable(f: int, a: Vector2i, b: Vector2i, extra_block := {}) -> bool:
	var rof: Dictionary = room_of[f]
	if not rof.has(b) or blocked[f].has(b) or extra_block.has(b):
		return false
	if absi(step_at(f, a) - step_at(f, b)) > 1:
		return false
	if rof[a] == rof[b] or open_pairs.has("%s|%s" % [rof[a], rof[b]]):
		return true
	if b.x == a.x + 1:
		return is_door(f, b, "nw")
	if b.x == a.x - 1:
		return is_door(f, a, "nw")
	if b.y == a.y + 1:
		return is_door(f, b, "ne")
	return is_door(f, a, "ne")


## Shortest walk (4-neighbour BFS) from a to b on one floor; [] if unreachable. b itself may be blocked
## (a station tile), the path then stops next to it.
func path(f: int, a: Vector2i, b: Vector2i, extra_block := {}) -> Array:
	var prev := {a: a}
	var q := [a]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur == b:
			break
		for nb in [cur + Vector2i(1, 0), cur + Vector2i(-1, 0), cur + Vector2i(0, 1), cur + Vector2i(0, -1)]:
			if prev.has(nb):
				continue
			if passable(f, cur, nb, extra_block) or (nb == b and room_of[f].has(nb)):
				prev[nb] = cur
				q.append(nb)
	if not prev.has(b):
		return []
	var out := [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out


## the free tile of floor f nearest to a local point (where to stand to use a bed or a bench), within `reach` m
func near_free(f: int, at: Vector3, reach := 3.2) -> Vector2i:
	var best := Vector2i(-99, -99)
	var bd := reach
	for t: Vector2i in room_of[f]:
		if blocked[f].has(t) or rooms[room_of[f][t]].get("annex", false):
			continue
		var c := tile_pos(f, t)
		var dd := Vector2(c.x - at.x, c.z - at.z).length()
		if dd < bd:
			bd = dd
			best = t
	return best


func tile_pos(f: int, t: Vector2i) -> Vector3:
	return Vector3(origin.x + t.x * TILE + TILE / 2.0, f * FLOOR_H + step_at(f, t) * STEP, origin.y + t.y * TILE + TILE / 2.0)


## a point given in tile units (a whole number is a tile centre), on floor f
func pos_at(f: int, cr: Vector2) -> Vector3:
	return Vector3(origin.x + (cr.x + 0.5) * TILE, f * FLOOR_H, origin.y + (cr.y + 0.5) * TILE)


func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / TILE), floori((p.z - origin.y) / TILE))


## the tile k steps out of the entrance (1 = the threshold on the wall line of a house in place, 2 = the street)
func entrance_out(k: int) -> Vector2i:
	var e: Dictionary = d.entrance
	var n: Vector2i = {"nw": Vector2i(-1, 0), "ne": Vector2i(0, -1), "se": Vector2i(1, 0), "sw": Vector2i(0, 1)}[String(e.side)]
	return Vector2i(e.tile[0], e.tile[1]) + n * k


func reach_of(zone: String, fallback: float) -> float:
	return float(d.stations.get(zone, {}).get("reach", fallback))


# ------------------------------------------------------------------ building
func build() -> Node3D:
	var t0 := Time.get_ticks_usec()
	root = Node3D.new()
	root.name = "Interior_" + String(d.get("id", "forge"))
	for f in floors:
		var level := Node3D.new()
		level.name = "Floor%d" % f
		level.set_meta("level", f)
		root.add_child(level)
		if in_situ:
			_partitions(level, f)  # the house of the town has the floors and the outer walls
		else:
			_floor_tiles(level, f)
			_walls(level, f)
		_room_lights(level, f)
	for p in placed:
		_place(p)
	for s in d.get("stairs", []):
		if s.has("foot"):
			_stair_run(s)
		else:
			_place({"id": s.prop, "floor": s.floor, "tile": s.tile, "flip": s.get("flip", false), "stair": true})
	if compact:
		_block_real()
		_auto_upgrades()
	_merge_static()
	dbg("built in %.1f ms: %d wall groups, %d room lights" % [(Time.get_ticks_usec() - t0) / 1000.0, wall_groups.size(), room_lights.size()])
	return root


func level_node(f: int) -> Node3D:
	return root.get_node("Floor%d" % f)


func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var p := ""
		if name.begins_with("@"):
			p = "res://kit/props/%s.glb" % name.substr(1)
		elif name.begins_with("q:"):
			p = QP % name.substr(2)
		elif name.begins_with("v:"):
			p = VILLAGE % name.substr(2)
		elif name.begins_with("m:"):
			p = MUEBLES % name.substr(2)
		elif name.begins_with("x:"):
			p = "res://kit/extras/%s.gltf" % name.substr(2)  # tools/make_extras.py: an animal in its static pose, a cart
		else:
			p = VILLAGE % name
		_scenes[name] = load(p) if ResourceLoader.exists(p) else null
		if _scenes[name] == null:
			push_warning("[Interior] missing piece %s (%s)" % [name, p])
	return _scenes[name]


func _inst(name: String, parent: Node3D, pos: Vector3, rot_deg := 0.0, sc := Vector3.ONE) -> Node3D:
	var n: Node3D
	if name.begins_with("box:"):
		n = _simple(name.substr(4))
	else:
		var s := _scene(name)
		if s == null:
			n = _placeholder(name)
		else:
			n = s.instantiate()
			if name.begins_with("@"):
				HouseBuilder.skin_prop(n)
			elif name.begins_with("m:"):
				_fx(n)
	n.position = pos
	n.rotation.y = deg_to_rad(rot_deg)
	n.scale = sc
	parent.add_child(n)
	return n


## the materials of the furniture that are not the kit's: embers glow, the hole of a trapdoor is flat black
static func _fx(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var src: Material = n.mesh.surface_get_material(i)
			var nm: String = src.resource_name if src else ""
			if nm != "MI_Ember" and nm != "MI_Hole":
				continue
			if not _fx_mats.has(nm):
				var m := StandardMaterial3D.new()
				m.resource_name = nm
				if nm == "MI_Ember":
					m.albedo_color = Color(1.0, 0.45, 0.1)
					m.emission_enabled = true
					m.emission = Color(1.0, 0.42, 0.08)
					m.emission_energy_multiplier = 3.5
				else:
					m.albedo_color = Color(0.02, 0.015, 0.012)
					m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_fx_mats[nm] = m
			n.set_surface_override_material(i, _fx_mats[nm])
	for c in n.get_children():
		_fx(c)


func smat(key: String, col: Color, metal := 0.0, rough := 0.85, emit := 0.0) -> StandardMaterial3D:
	if not _simple_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = metal
		m.roughness = rough
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = emit
		_simple_mats[key] = m
	return _simple_mats[key]


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Simple props made here (not in any kit): posts, ingots, tongs, a stone hearth.
func _simple(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	var iron := smat("iron_bar", Color(0.5, 0.5, 0.55), 0.7, 0.4)
	var wood := smat("wood", Color(0.36, 0.24, 0.15))
	match kind:
		"post":
			_box(n, Vector3(1, 1, 1), Vector3(0, 0.5, 0), wood)
		"hearth":
			_box(n, Vector3(1, 1, 1), Vector3(0, 0.5, 0), smat("hearth", Color(0.38, 0.35, 0.33)))
		"flue":
			_box(n, Vector3(1, 1, 1), Vector3(0, 0.5, 0), _tri_mat("res://kit/village/T_UnevenBrick_BaseColor.png", 0.6))
		"ingots", "ingots_low":
			var rows := 3 if kind == "ingots" else 1
			for y in rows:
				for i in 3:
					var b := _box(n, Vector3(0.14, 0.08, 0.42), Vector3((i - 1) * 0.17, 0.04 + y * 0.085, 0), iron)
					b.rotation.y = deg_to_rad(90 if y % 2 else 0)
		"tongs":
			for s in [-1, 1]:
				var b := _box(n, Vector3(0.025, 0.025, 0.55), Vector3(s * 0.02, 0.02, 0), iron)
				b.rotation.y = deg_to_rad(s * 3)
	return n


func _placeholder(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = "missing_" + name
	_box(n, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0), smat("missing", Color(1, 0, 1)))
	var l := Label3D.new()
	l.text = name
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 1.0
	l.pixel_size = 0.004
	n.add_child(l)
	return n


func _tri_mat(tex: String, sc: float) -> StandardMaterial3D:
	if not _simple_mats.has(tex):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(tex)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * sc
		m.roughness = 0.95
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_simple_mats[tex] = m
	return _simple_mats[tex]


func _floor_tiles(level: Node3D, f: int) -> void:
	var y0 := f * FLOOR_H
	var slab := smat("slab", Color(0.3, 0.2, 0.13))
	var rim := _tri_mat(FLOOR_TEX.flagstone, 0.5)
	var hole := {}
	if f > 0:
		for s in d.get("stairs", []):
			if int(s.to_floor) == f:
				for t in footprint({"id": s.prop, "tile": s.tile, "flip": s.get("flip", false)}):
					hole[t] = true
	for t in room_of[f]:
		if hole.has(t):
			continue
		var room: Dictionary = rooms[room_of[f][t]]
		var kind: String = room.get("floor_kind", "planks")
		var p := tile_pos(f, t)
		if FLOOR_PIECE.has(kind):
			var piece := _inst(FLOOR_PIECE[kind], level, p)
			piece.set_meta("floor_piece", true)
		else:
			var mi := _box(level, Vector3(TILE, 0.04, TILE), p - Vector3(0, 0.02, 0), _tri_mat(FLOOR_TEX.get(kind, FLOOR_TEX.earth), 0.5 if kind == "flagstone" else 0.35))
			mi.set_meta("floor_piece", true)
		if f > 0:  # slab under an upper floor (the ceiling of the floor below)
			var sb := _box(level, Vector3(TILE, 0.24, TILE), p - Vector3(0, 0.14, 0), slab)
			sb.set_meta("floor_piece", true)
		# the pit (or dais): a stone rim on every edge between two step heights
		var s0 := step_at(f, t)
		for nb in [t + Vector2i(1, 0), t + Vector2i(-1, 0), t + Vector2i(0, 1), t + Vector2i(0, -1)]:
			var s1 := step_at(f, nb)
			if s1 > s0 or (not room_of[f].has(nb) and s0 < 0):
				var dir := Vector2(nb - t)
				var mid := p + Vector3(dir.x, 0, dir.y) * (TILE / 2.0) + Vector3(0, (s1 - s0) * STEP / 2.0, 0)
				var size := Vector3(0.14 if dir.x != 0 else TILE, (s1 - s0) * STEP, TILE if dir.x != 0 else 0.14)
				_box(level, size, mid, rim).set_meta("floor_piece", true)
				# a lip on top of the upper side
				_box(level, Vector3(size.x + (0.1 if dir.x != 0 else 0), 0.05, size.z + (0.1 if dir.x == 0 else 0)), mid + Vector3(0, size.y / 2.0, 0), rim).set_meta("floor_piece", true)


## Walls: for every tile edge, what is on each side. Back edges (nw: x = c*2, ne: z = r*2) and front edges
## (se: x = (c+1)*2, sw: z = (r+1)*2) with no room behind are exterior walls; edges between two rooms are inner
## walls or doors. Each edge is built once (from the tile that owns it) and filed in a group by
## (floor, kind, normal, rooms) so the cutaway hides whole runs and the group merges into one mesh.
func _walls(level: Node3D, f: int) -> void:
	var rof: Dictionary = room_of[f]
	var groups := {}
	var ent: Dictionary = d.get("entrance", {})
	var posts := {}  # Vector2i grid vertex -> [group keys]
	for t in rof:
		var room: String = rof[t]
		# [side, neighbour, plan normal pointing out of this tile, edge midpoint offset, rot]
		for e in [["nw", t + Vector2i(-1, 0), Vector2(-1, 0)], ["ne", t + Vector2i(0, -1), Vector2(0, -1)],
				["se", t + Vector2i(1, 0), Vector2(1, 0)], ["sw", t + Vector2i(0, 1), Vector2(0, 1)]]:
			var side: String = e[0]
			var nb: Vector2i = e[1]
			var n: Vector2 = e[2]
			var other: String = rof.get(nb, "")
			if other == room:
				continue
			var kind := "ext"
			var door := false
			if other != "":
				if side in ["se", "sw"]:
					continue  # inner edges are built once, from the tile whose back edge it is
				kind = "inner"
				door = is_door(f, t, side)
			elif not ent.is_empty() and int(ent.floor) == f and Vector2i(ent.tile[0], ent.tile[1]) == t and ent.side == side:
				door = true
			var style: String = rooms[room].get("wall_style", "timber")
			var key := "%d|%s|%s|%s|%s" % [f, kind, n, room, other]
			if not groups.has(key):
				var g := Node3D.new()
				g.name = "Walls_%s_%s_%s" % [kind, room, other if other != "" else ("%+d%+d" % [n.x, n.y])]
				g.set_meta("wall_group", true)
				level.add_child(g)
				groups[key] = {"node": g, "floor": f, "normal": n, "kind": kind, "room": room, "other": other, "low": false, "fade": 0.0}
				wall_groups.append(groups[key])
			var g2: Node3D = groups[key].node
			edge_group["%d|%d|%d|%s" % [f, t.x, t.y, side]] = groups[key]
			var c := Vector3(t.x * TILE + TILE / 2.0, f * FLOOR_H, t.y * TILE + TILE / 2.0) + Vector3(n.x, 0, n.y) * (TILE / 2.0)
			# the kit wall's outer face is local +z: turn it toward the normal (out of the room)
			var rot := rad_to_deg(atan2(n.x, n.y))
			var piece := "Wall_%s_%s" % [WALL_PIECE.get(style, "Plaster"), "Door_Flat" if door else "Straight"]
			if not door and kind == "ext" and side in ["nw", "ne"] and _rng.randf() < (0.22 if style == "stone" else 0.4):
				piece = "Wall_%s_Window_Wide_Flat" % WALL_PIECE.get(style, "Plaster")
			elif not door and style == "timber":
				piece = "Wall_Plaster_WoodGrid"
			_inst(piece, g2, c, rot)
			if piece == "Wall_Plaster_WoodGrid":  # the grid is only the timber frame: plaster behind it
				_inst("Wall_Plaster_Straight", g2, c, rot)
			if piece.contains("Window"):
				_inst("Window_Wide_Flat1", g2, c, rot)
			if door and kind == "ext":
				var hinge := Vector3(-0.53, 0, 0).rotated(Vector3.UP, deg_to_rad(rot))
				var leaf := _inst("Door_1_Flat", g2, c + hinge, rot - 100.0)
				leaf.set_meta("door_leaf", true)
			# grid vertices at both ends of the edge
			var along := Vector2i(absi(int(n.y)), absi(int(n.x)))  # edge direction on the grid
			var v0 := Vector2i(t.x + (1 if side == "se" else 0), t.y + (1 if side == "sw" else 0))
			for v in [v0, v0 + along]:
				if not posts.has(v):
					posts[v] = []
				if not (posts[v] as Array).has(key):
					posts[v].append(key)
	# corner posts where wall runs meet (hide the joints); a post belongs to the walls around it
	for v in posts:
		var keys: Array = posts[v]
		keys.sort()
		var pk := "%d|post|%s" % [f, ",".join(keys)]
		if not groups.has(pk):
			var g := Node3D.new()
			g.name = "Posts"
			g.set_meta("wall_group", true)
			level.add_child(g)
			groups[pk] = {"node": g, "floor": f, "normal": Vector2.ZERO, "kind": "post", "of": keys.map(func(k): return groups[k]), "low": false, "fade": 0.0}
			wall_groups.append(groups[pk])
		var stone := false
		for k in keys:
			if rooms.has(groups[k].room) and rooms[groups[k].room].get("wall_style", "") == "stone":
				stone = true
		_inst("Corner_Exterior_Brick" if stone else "Corner_Exterior_Wood", groups[pk].node, Vector3(v.x * TILE, f * FLOOR_H, v.y * TILE))
	for g in wall_groups:
		if int(g.floor) == f:
			_wallify(g.node)


## Kit materials -> the cutaway wall shader (same textures), cached per source material.
func _wallify(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var src: Material = n.mesh.surface_get_material(i)
			n.set_surface_override_material(i, wall_mat(src))
	for c in n.get_children():
		_wallify(c)


func wall_mat(src: Material) -> Material:
	var key := src.get_instance_id() if src else 0
	if _wall_mats.has(key):
		return _wall_mats[key]
	var m := ShaderMaterial.new()
	m.shader = wall_shader if wall_shader else load(WALL_SHADER)
	var sm := src as StandardMaterial3D
	if sm:
		m.set_shader_parameter("albedo_tex", sm.albedo_texture)
		m.set_shader_parameter("albedo_color", sm.albedo_color)
		m.set_shader_parameter("use_normal", sm.normal_enabled and sm.normal_texture != null)
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("uv_scale", sm.uv1_scale)
		m.set_shader_parameter("uv_offset", sm.uv1_offset)
		m.set_shader_parameter("rough", sm.roughness)
		if sm.albedo_texture == null:
			m.set_shader_parameter("albedo_tex", _white())
	_wall_mats[key] = m
	return m


static var _white_tex: ImageTexture
static func _white() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


# ------------------------------------------------------------------ props
## Which way a piece looks: away from the wall it stands against (back walls first), else into the room.
func _facing(f: int, p: Dictionary, tiles: Array) -> float:
	var t: Vector2i = tiles[0]
	var room := room_at(f, t)
	var along_x: bool = p.get("flip", false) and tiles.size() > 1
	var along_z: bool = not p.get("flip", false) and tiles.size() > 1
	var cands := []  # [rot, priority]
	if not along_x:  # can face +x/-x
		if room_at(f, t + Vector2i(-1, 0)) != room:
			cands.append([90.0, 0])
		elif room_at(f, t + Vector2i(1, 0)) != room:
			cands.append([-90.0, 1])
	if not along_z:
		if room_at(f, t + Vector2i(0, -1)) != room:
			cands.append([0.0, 0])
		elif room_at(f, t + Vector2i(0, 1)) != room:
			cands.append([180.0, 1])
	if cands.is_empty():
		return 0.0 if along_x else 90.0
	cands.sort_custom(func(a, b): return a[1] < b[1])
	return cands[0][0]


static func own_furniture() -> Dictionary:
	if _own_loaded:
		return _own
	_own_loaded = true
	var txt := FileAccess.get_file_as_string("res://game/world3d/kit_data/props/ropa_muebles.json")
	if txt == "":
		return _own
	var cat_own: Dictionary = JSON.parse_string(txt).get("props", {})
	for pid in cat_own:
		var e: Dictionary = cat_own[pid]
		if not ResourceLoader.exists("res://kit/props/%s.glb" % pid):
			continue
		for gid in e.get("pieces", []):
			_own[String(gid)] = [[["@" + String(pid), Vector3.ZERO, 0, Vector3.ONE]], float(e.get("seat_h", e.get("height", 0.8)))]
	if OS.is_debug_build():
		print("[Interior3DBuilder] own furniture for %s" % [_own.keys()])
	return _own


## the 3D pieces of a GuildMaster prop id: the own piece if there is one, else PIECES
static func spec_of(id: String) -> Array:
	var o: Dictionary = own_furniture()
	return o[id][0] if o.has(id) else PIECES.get(id, [])


## height of the top (or the seat) of the piece standing for `id`, `fallback` when it is not an own piece
static func top_of(id: String, fallback: float) -> float:
	var o: Dictionary = own_furniture()
	return float(o[id][1]) if o.has(id) else fallback


func _place(p: Dictionary) -> void:
	var f := int(p.floor)
	var id: String = p.id
	var spec: Array = spec_of(id)
	var mueble: Dictionary = muebles().get(id, {}) if compact else {}
	if not mueble.is_empty():
		spec = [["m:" + id, Vector3.ZERO, 0, Vector3.ONE]]
	elif id.begins_with("x:") or id.begins_with("q:") or id.begins_with("@"):
		spec = [[id, Vector3.ZERO, 0, Vector3.ONE]]  # a piece of the kits by its own name
	var tiles := footprint(p) if p.has("tile") and not p.has("pos") else [world_to_tile(pos_at(f, Vector2(p.pos[0], p.pos[1])))]
	var centre := Vector3.ZERO
	for t in tiles:
		centre += tile_pos(f, t)
	centre /= tiles.size()
	var holder := Node3D.new()
	holder.name = id
	level_node(f).add_child(holder)
	var rot := float(p.rot) if p.has("rot") else _facing(f, p, tiles)
	if p.has("pos"):  # compact: placed by hand, in tile units
		centre = pos_at(f, Vector2(p.pos[0], p.pos[1])) + Vector3(0, float(p.get("y", 0.0)), 0)
	elif p.has("hang"):
		# on the wall of that side of the tile, facing into the room, at head height
		var t: Vector2i = tiles[0]
		var base := tile_pos(f, t)
		if p.hang == "nw":
			centre = Vector3(t.x * TILE + 0.22, base.y + 1.7, base.z)
			rot = 90.0
		else:
			centre = Vector3(base.x, base.y + 1.7, t.y * TILE + 0.22)
			rot = 0.0
	elif p.has("lift"):
		var over := String(p.get("over", ""))
		centre.y += top_of(over, {"shop_counter": 0.92, "kitchen_table": 0.82}.get(over, 0.8))
		var sh: Array = p.get("shift", [0, 0])
		centre += Vector3(float(sh[0]) / 32.0, 0, -float(sh[1]) / 32.0) * 0.5
	if p.get("stair", false):
		# the kit stair climbs toward its local -z: put its foot on the front edge of the first tile
		var t := Vector2i(p.tile[0], p.tile[1])
		centre = Vector3(t.x * TILE + TILE / 2.0, f * FLOOR_H, (t.y + 1) * TILE - 0.3)
		rot = 0.0 if not p.get("flip", false) else 90.0
	holder.position = centre
	holder.rotation.y = deg_to_rad(rot)
	if p.get("flip_x", false):  # a mirrored interior: the piece reflected, kept out of the merged mesh (its faces turn)
		holder.scale.x = -1.0
		holder.add_to_group("loose_piece")
	if p.has("hang"):
		# hung on a wall: it goes (and hides) with that wall when the cutaway lowers it
		var t: Vector2i = tiles[0]
		var g: Dictionary = edge_group.get("%d|%d|%d|%s" % [f, t.x, t.y, p.hang], {})
		if not g.is_empty():
			holder.reparent(g.node, false)
			holder.set_meta("hung", true)
			if not g.has("hung"):
				g.hung = []
			g.hung.append(holder)
	_holders.append([p, holder])
	if p.has("zone"):
		zone_pos[p.zone] = centre
	if p.has("name") or p.has("zone"):
		named[String(p.get("name", p.get("zone", "")))] = {"pos": centre, "rot": rot, "id": id, "floor": f}
	if mueble.has("lie"):
		beds_placed.append({"pos": centre, "rot": rot, "id": id, "floor": f})  # named or not (the merge frees holders)
	if mueble.has("fire"):
		var fv := Vector3(mueble.fire[0], mueble.fire[1], mueble.fire[2]).rotated(Vector3.UP, deg_to_rad(rot))
		fires.append({"floor": f, "at": centre + fv, "id": id})
	if mueble.get("hang", false) or p.get("loose", false):
		# hung on an outer wall of the house: it stays a piece of its own, to go when that wall is lowered
		holder.add_to_group("loose_piece")
		if mueble.get("hang", false):
			hung.append({"node": holder, "floor": f, "normal": SNAP_OUT.get(String(p.get("wall", "")), Vector2.ZERO)})
	if spec.is_empty():
		holder.add_child(_placeholder(id))
		dbg("no 3D piece for %s at %s (placeholder)" % [id, p.get("tile", p.get("pos"))])
		return
	for e in spec:
		_inst(e[0], holder, e[1], e[2], e[3])
	if p.has("zone"):
		holder.set_meta("zone", p.zone)
		holder.add_to_group("station_piece")


# ------------------------------------------------------------------ compact interiors (interior in place)
## Partition walls of an interior in place: an edge between two rooms of the house (not "open", neither of them an
## annex) is a kit wall. The pieces stay on the kit's 2 m grid along the wall (the cells of the shell: centres at
## -len/2 + 1 + 2k), so a partition runs from outer wall to outer wall or ends on a cell line; across it sits on a
## tile edge. A door listed on any tile of a cell makes that cell a door piece: its opening is the middle of the
## cell, which is a tile centre.
func _partitions(level: Node3D, f: int) -> void:
	var rof: Dictionary = room_of[f]
	var sh: Dictionary = d.shell
	var cells := {}  # "side|line|k" -> {door, side, line, k, n, room, other, span}
	for t: Vector2i in rof:
		var room: String = rof[t]
		for e in [["nw", t + Vector2i(-1, 0), Vector2(-1, 0)], ["ne", t + Vector2i(0, -1), Vector2(0, -1)]]:
			var other: String = rof.get(e[1], "")
			if other == "" or other == room or open_pairs.has("%s|%s" % [room, other]):
				continue
			if rooms[room].get("annex", false) or rooms[other].get("annex", false):
				continue
			var c := tile_pos(f, t)
			var along: float = c.z if e[0] == "nw" else c.x
			var span := float(sh.d) if e[0] == "nw" else float(sh.w)
			var k := clampi(floori((along + span / 2.0) / 2.0), 0, int(span / 2.0) - 1)
			var line: int = t.x if e[0] == "nw" else t.y
			var key := "%s|%d|%d" % [e[0], line, k]
			if not cells.has(key):
				cells[key] = {"door": false, "side": e[0], "line": line, "k": k, "n": e[2], "room": room, "other": other, "span": span}
			if is_door(f, t, e[0]):
				cells[key].door = true
	var groups := {}
	for key in cells:
		var c: Dictionary = cells[key]
		var gk := "%s|%d" % [c.side, c.line]
		if not groups.has(gk):
			var g := Node3D.new()
			g.name = "Partition_%s_%d" % [c.side, c.line]
			g.set_meta("wall_group", true)
			level.add_child(g)
			groups[gk] = {"node": g, "floor": f, "normal": c.n, "kind": "inner", "room": c.room, "other": c.other, "low": false, "fade": 0.0}
			wall_groups.append(groups[gk])
		var mid := -float(c.span) / 2.0 + 1.0 + 2.0 * int(c.k)
		# the kit wall is 0.41 m thick, off its line (-0.31 .. +0.09 along its local z): centre it on the tile edge
		var at := Vector3(origin.x + int(c.line) * TILE + 0.111, f * FLOOR_H, mid)
		var rot := 90.0
		if c.side == "ne":
			at = Vector3(mid, f * FLOOR_H, origin.y + int(c.line) * TILE + 0.111)
			rot = 0.0
		_inst("Wall_Plaster_Door_Flat" if c.door else "Wall_Plaster_Straight", groups[gk].node, at, rot)
	for gk in groups:
		_wallify(groups[gk].node)
	dbg("floor %d: %d partition cells in %d runs" % [f, cells.size(), groups.size()])


## A flight of stairs given by its foot and its top (tile units): the kit's open stair, shortened and narrowed to fit
## (a steep miller's stair: the kit's is 4.6 m long and 1.7 m wide, a third of a 6 x 6 m floor).
func _stair_run(s: Dictionary) -> void:
	var f := int(s.floor)
	var tf := int(s.to_floor)
	var foot := pos_at(f, Vector2(s.foot[0], s.foot[1]))
	var top := pos_at(tf, Vector2(s.top[0], s.top[1]))
	var run := Vector2(top.x - foot.x, top.z - foot.z)
	var holder := Node3D.new()
	holder.name = "stairs"
	level_node(f).add_child(holder)
	holder.position = foot
	holder.rotation.y = atan2(-run.x, -run.y)  # the kit stair climbs toward its local -z
	var st: Dictionary = muebles().get(String(s.get("prop", "")), {}).get("stair", {})
	if st.is_empty():  # the kit's open stair, shortened and narrowed
		holder.scale = Vector3(float(s.get("width", 0.95)) / 1.676, (top.y - foot.y) / 3.035, run.length() / 4.585)
		_inst("v:Stair_Interior_Simple", holder, Vector3.ZERO)
	else:  # a stair of ours at real size (escalera_empinada, escalera_mano), stretched to the flight
		# "mirror": the rail on the other side (a flight against the right wall that climbs to the back, or against the left one to the front)
		holder.scale = Vector3((-1.0 if s.get("mirror", false) else 1.0) * float(s.get("width", st.width)) / float(st.width), (top.y - foot.y) / float(st.rise), run.length() / float(st.run))
		_inst("m:" + String(s.prop), holder, Vector3.ZERO)
	stair_runs.append({"floor": f, "to_floor": tf, "from": Vector2i(s.from[0], s.from[1]), "to": Vector2i(s.to[0], s.to[1]),
		"foot": foot, "top": top})
	dbg("stair %s: %.2f m long, %.0f degrees" % [s.get("id", ""), run.length(), rad_to_deg(atan2(top.y - foot.y, run.length()))])


func _aabb_of(n: Node, ref: Node3D, box: Array) -> void:
	if n is MeshInstance3D and n.mesh:
		var b: AABB = _rel(n, ref) * (n.mesh as Mesh).get_aabb()
		box[0] = b if box[1] == 0 else (box[0] as AABB).merge(b)
		box[1] = 1
	for c in n.get_children():
		_aabb_of(c, ref, box)


## Compact interiors: the tiles each piece really covers (more than BLOCK_SHARE of the tile) are blocked; the tile
## where the worker of a station stands is never blocked. Prints the plan of each floor.
func _block_real() -> void:
	var keep := {}
	for z in zones:
		keep["%d|%s" % [zones[z].floor, zones[z].stand]] = true
	for h in _holders:
		_block_holder(h, keep)
	_plan_log()


func _blocks(p: Dictionary) -> bool:
	## the piece takes the tiles it stands on
	var pr: Dictionary = cat.get(p.id, {})
	var mb: Dictionary = muebles().get(p.id, {})
	if pr.get("walkable", false) or pr.get("hangs", false) or p.has("lift") or p.has("y") or p.get("seat", false) or pr.get("category", "") == "small" or p.id == "tongs":
		return false
	return not (mb.get("hang", false) or mb.get("small", false) or (mb.has("blocks") and not mb.blocks) or p.get("walk", false))


func _block_holder(h: Array, keep: Dictionary) -> void:
	var p: Dictionary = h[0]
	var mb: Dictionary = muebles().get(p.id, {})
	var f := int(p.floor)
	if not _wall_used.has(f):
		_wall_used[f] = []
	var box := [AABB(), 0]
	_aabb_of(h[1], root, box)
	if box[1] == 0:
		return
	var b: AABB = box[0]
	var rc := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
	if mb.get("hang", false) or mb.get("tall", false) or b.size.y > 1.5:
		_wall_used[f].append(rc)
	if not _blocks(p):
		return
	obstacles[f].append(rc)
	p["rect"] = rc
	for t: Vector2i in _tiles_under(rc):
		if not keep.has("%d|%s" % [f, t]):
			blocked[f][t] = true


func _tiles_under(rc: Rect2) -> Array:
	## the tiles a plan rectangle takes (more than BLOCK_SHARE of each)
	var out := []
	var t0 := world_to_tile(Vector3(rc.position.x, 0, rc.position.y))
	var t1 := world_to_tile(Vector3(rc.end.x, 0, rc.end.y))
	for c in range(t0.x, t1.x + 1):
		for r in range(t0.y, t1.y + 1):
			var tile := Rect2(origin.x + c * TILE, origin.y + r * TILE, TILE, TILE)
			if tile.intersection(rc).get_area() / (TILE * TILE) > BLOCK_SHARE:
				out.append(Vector2i(c, r))
	return out


func _plan_log() -> void:
	if OS.is_debug_build():
		for f in floors:
			var stands := {}
			for z in zones:
				if zones[z].floor == f:
					stands[zones[z].stand] = String(z).substr(0, 1).to_upper()
			var free := 0
			var rows := []
			for r in H:
				var line := ""
				for c in W:
					var t := Vector2i(c, r)
					if not room_of[f].has(t):
						line += " "
					elif blocked[f].has(t):
						line += "#"
					else:
						free += 1
						line += stands.get(t, ".")
				rows.append(line)
			dbg("floor %d plan (%d free tiles of %d; # piece, letter = where a station's worker stands):\n  %s" % [f, free, room_of[f].size(), "\n  ".join(rows)])


# ------------------------------------------------------------------ light
## lights.json: mode add = a warm glow (alpha = strength) -> an OmniLight of that colour; mode mul = shade
## (alpha = how dark) -> a negative OmniLight that takes light away from the room.
func _room_lights(level: Node3D, f: int) -> void:
	for id in rooms:
		var room: Dictionary = rooms[id]
		if int(room.floor) != f or not lights_def.has(room.get("light", "")):
			continue
		var ld: Dictionary = lights_def[room.light]
		# centre of the room's largest rect
		var best: Array = room.rects[0]
		for rc in room.rects:
			if (rc[2] - rc[0] + 1) * (rc[3] - rc[1] + 1) > (best[2] - best[0] + 1) * (best[3] - best[1] + 1):
				best = rc
		var cx := origin.x + (float(best[0]) + float(best[2]) + 1.0) * TILE / 2.0
		var cz := origin.y + (float(best[1]) + float(best[3]) + 1.0) * TILE / 2.0
		var radius := maxf(float(best[2] - best[0] + 1), float(best[3] - best[1] + 1)) * TILE * 0.75
		var l := OmniLight3D.new()
		l.name = "Light_" + id
		l.light_color = Color.html(ld.color)
		l.light_negative = ld.mode == "mul"
		l.omni_range = maxf(radius, 3.5)
		l.omni_attenuation = 0.8
		l.position = Vector3(cx, f * FLOOR_H + 2.5, cz)
		l.shadow_enabled = false
		level.add_child(l)
		room_lights.append({"light": l, "room": id, "def": ld})


# ------------------------------------------------------------------ merging
## Floors and props of a level merge into a few meshes (one per material); wall groups merge each into one
## node so the cutaway still hides them run by run.
func _merge_static() -> void:
	for f in floors:
		var level := level_node(f)
		var floor_src := []
		var prop_src := []
		for c in level.get_children():
			if c.has_meta("floor_piece"):
				floor_src.append(c)
			elif c is Node3D and not c is Light3D and not c.has_meta("wall_group") and not c.is_in_group("station_piece") and not c.is_in_group("loose_piece"):
				prop_src.append(c)
		_merge(floor_src, level, "FloorMesh")
		_merge(prop_src, level, "PropsMesh")
		for c in floor_src + prop_src:
			c.free()
	for g in wall_groups:
		var node: Node3D = g.node
		var kids := node.get_children()
		var leaf := []
		for k in kids:
			if k.has_meta("door_leaf") or k.has_meta("hung"):
				leaf.append(k)
		var mi := _merge(kids.filter(func(k): return not leaf.has(k)), node, "merged")
		for k in kids:
			if not leaf.has(k):
				k.free()
		g.meshes = [mi] if mi else []
		for lf in leaf:
			if lf.has_meta("door_leaf"):
				_wallify(lf)
				_collect_mis(lf, g.meshes)


func _collect_mis(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_mis(c, out)


func _rel(n: Node3D, ref: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != ref:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _gather(n: Node, ref: Node3D, tools: Dictionary, mats: Dictionary) -> void:
	if n is MeshInstance3D and n.mesh and n.visible:
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
		_gather(c, ref, tools, mats)


func _merge(sources: Array, owner: Node3D, name: String) -> MeshInstance3D:
	var tools := {}
	var mats := {}
	for s in sources:
		_gather(s, owner, tools, mats)
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


# ------------------------------------------------------------------ cutaway
## cam_dir: plan direction from the scene toward the camera (x, z). mode: "down" (every camera-facing wall
## low: exterior walls on the camera sides and all inner walls), "cut" (GDD 4.6.5.3: exterior camera-facing
## walls low, inner walls whole but see-through when `focus_room` is behind them), "off" (everything up).
## top: highest floor shown.
## the highest point (y, in the parent's space of `n`) of the meshes under n
static func _top_of(n: Node3D) -> float:
	var best := -INF
	var stack := [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var a: AABB = (n.transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if n.is_inside_tree() else mi.transform * mi.get_aabb()
			best = maxf(best, a.end.y)
		for ch in c.get_children():
			stack.append(ch)
	return best if best > -INF else n.position.y


func set_cutaway(cam_dir: Vector2, mode: String, top: int, focus_room := "") -> void:
	for f in floors:
		level_node(f).visible = f <= top
	for h in hung:
		# what hangs on an outer wall goes down with it when the house lowers that wall (the floor in view, walls facing
		# the camera): it slides down the wall so its top sits at the stub's height and stays in view, instead of
		# vanishing (the first pass hid it, and the kitchen of the well-off house lost its pots and hams at yaw 225)
		var n := h.node as Node3D
		if not h.has("base"):
			h.base = n.position.y
			h.top = _top_of(n) - n.position.y
		var lowered: bool = mode != "off" and int(h.floor) == top and (h.normal as Vector2).dot(cam_dir) > 0.1
		n.position.y = h.base - maxf(0.0, h.base + float(h.top) - HANG_LOW) if lowered else h.base
		n.visible = true
	for g in wall_groups:
		if g.kind == "post":
			continue
		var faces: bool = (g.normal as Vector2).dot(cam_dir) > 0.1
		var low := false
		var fade := 0.0
		if mode != "off":
			if g.kind == "ext":
				low = faces
			elif mode == "down":
				low = true
			elif focus_room != "":
				# the room behind this inner wall, seen from the camera
				var behind: String = g.room if faces else g.other
				if behind == focus_room:
					fade = 0.72
		g.low = low
		g.fade = fade
	for g in wall_groups:
		if g.kind == "post":
			var any_up := false
			var fd := 1.0
			for o in g.of:
				any_up = any_up or not o.low
				fd = minf(fd, o.fade)
			g.low = not any_up
			g.fade = fd
	for g in wall_groups:
		for h in g.get("hung", []):
			(h as Node3D).visible = not g.low and g.fade < 0.5
		var cut: float = int(g.floor) * FLOOR_H + (LOW_H if g.low else 100.0)
		for mi in g.get("meshes", []):
			(mi as GeometryInstance3D).set_instance_shader_parameter("cut_y", root.global_position.y + cut)
			(mi as GeometryInstance3D).set_instance_shader_parameter("fade", g.fade)



# ------------------------------------------------------------------ upgrades
## The data's "upgrades": {<interior node of GuildMaster>: [entries]} says what each upgrade is inside this building, and
## "upgrade_ids": {<the sim's upgrade id>: <node>} which node each upgrade of the sim's trees shows. With a list of
## finished upgrades (opts.upgrades: ids of the sim or nodes) only those are shown. An entry is one of:
##   {id, floor, tile | pos, snap...}          a piece at that place (as a prop)
##   {id, floor, auto: "wall" | "floor", near}  a piece whose place is found here: the free place against an outer wall
##                                             (or on the floor) nearest to `near` (a zone, a named piece or [c, r]) that
##                                             leaves every tile reachable. Every auto piece of the building gets its
##                                             place whether bought or not, so nothing moves when another one is bought
##   {zone, id, ...}                           the same, and it is a new station (its worker's tile is found beside it)
##   {swap: <name or zone>, id}                the named base piece becomes that one
##   {on: <name or zone>, id, off, y}          a small piece on top of the named one
##   {base: <name or zone>}                    a base piece stands for the upgrade: with a list given, it waits for it
##   {needs: "anexo" | "patio" | "planta" | "sótano" | "nivel" | "fuera", note}   not inside this house: an extension
##   {none: "<why>"}                           it has no place, not even extending
## An auto entry may carry or_needs / or_note: if it finds no place here, the upgrade asks for that extension instead.
func _upgrades(show_all: bool) -> void:
	var ups: Dictionary = d.get("upgrades", {})
	var ids: Dictionary = d.get("upgrade_ids", {})
	var done := {}
	for u in done_upgrades:
		done[String(ids.get(u, u))] = true
	var legacy := not upgrades_given and not show_all  # no list: the building as it was drawn before the upgrades were data
	for node in ups:
		if not ups[node] is Array:
			continue
		var on: bool = show_all or done.has(node)
		var st := {"status": "placed" if on else "fits", "where": [], "note": ""}
		for e in ups[node]:
			if not e is Dictionary:
				continue
			if e.has("needs"):
				st.status = "needs"
				st.note = "%s%s" % [e.needs, (": " + String(e.note)) if e.has("note") else ""]
			elif e.has("none"):
				st.status = "none"
				st.note = String(e.none)
			elif e.has("built"):
				st.status = "base"  # this level's house already has it
				st.note = String(e.built)
			elif e.has("base"):
				st.note = "pieza base"
				if not on and not legacy:
					_drop_base(String(e.base))
					st.status = "fits"
				elif legacy:
					st.status = "base"
			elif e.has("swap"):
				if on:
					_swap_base(String(e.swap), e)
			elif e.has("on"):
				if on:
					_ons.append({"node": node, "e": e})
			elif e.has("auto"):
				_autos.append({"node": node, "e": e, "done": on})
			elif e.has("zone") and (e.has("tile") or e.has("pos")):
				var zs: Dictionary = (e as Dictionary).duplicate()
				if zs.has("id") and not zs.has("prop"):
					zs["prop"] = zs.id
				if on:
					d.stations[String(e.zone)] = zs
					_up_zones[String(e.zone)] = true
				else:
					_ghost({"id": zs.get("prop", ""), "floor": zs.get("floor", 0), "tile": zs.get("tile", [0, 0]), "pos": zs.get("pos", zs.get("tile", [0, 0])), "rot": zs.get("rot", 0.0)})
					if zs.has("stand"):
						_ghost_tiles.append([int(zs.get("floor", 0)), Vector2i(zs.stand[0], zs.stand[1])])
				var zt: Array = e.get("tile", e.get("pos"))
				st.where.append([int(e.get("floor", 0)), zt[0], zt[1]])
			elif e.has("id") and (e.has("tile") or e.has("pos")):
				if on:
					var p: Dictionary = (e as Dictionary).duplicate()
					p["_upg"] = node
					if not d.has("props"):
						d["props"] = []
					d.props.append(p)
				else:
					_ghost(e)
				var at: Array = e.get("tile", e.get("pos"))
				st.where.append([int(e.get("floor", 0)), at[0], at[1]])
		upgrade_state[node] = st


func _drop_base(name: String) -> void:
	## a base piece that stands for an upgrade not bought yet: gone, its place kept for it
	if d.get("stations", {}).has(name):
		var s: Dictionary = d.stations[name]
		if s.has("prop"):
			var g := {"id": s.prop, "floor": s.floor, "tile": s.tile}
			for k in ["pos", "rot", "snap", "gap"]:
				if s.has(k):
					g[k] = s[k]
			_ghost(g)
		_ghost_tiles.append([int(s.floor), Vector2i(s.stand[0], s.stand[1])] if s.has("stand") else [int(s.floor), Vector2i(s.tile[0], s.tile[1])])
		d.stations.erase(name)
		return
	for p: Dictionary in d.get("props", []):
		if String(p.get("name", "")) == name:
			_ghost(p)
	d["props"] = (d.get("props", []) as Array).filter(func(p): return String(p.get("name", "")) != name)


func _ghost(e: Dictionary) -> void:
	## the place of a piece that is not there (an upgrade not bought): kept out of the search for auto places
	if not compact or not (e.has("tile") or e.has("pos")):
		return
	var p: Dictionary = e.duplicate()
	resolve_prop(p, d)
	var id := String(p.get("id", ""))
	var f := int(p.get("floor", 0))
	var at := pos_at(f, Vector2(p.pos[0], p.pos[1]))
	var tb := turned_box(id, float(p.get("rot", 0.0)))
	var mb: Dictionary = muebles().get(id, {})
	_ghosts.append({"floor": f, "rect": Rect2(at.x + tb.position.x, at.z + tb.position.y, tb.size.x, tb.size.y),
		"tall": mb.get("hang", false) or mb.get("tall", false), "blocks": _blocks({"id": id})})


func _swap_base(name: String, e: Dictionary) -> void:
	var target := {}
	if d.get("stations", {}).has(name):
		target = d.stations[name]
		target["prop"] = e.id
	else:
		for p: Dictionary in d.get("props", []):
			if String(p.get("name", "")) == name:
				target = p
				p["id"] = e.id
	for k in ["pos", "tile", "rot", "snap", "gap"]:
		if e.has(k) and not target.is_empty():
			target[k] = e[k]


func _near_point(f: int, near) -> Vector3:
	if near is Array:
		return pos_at(f, Vector2(near[0], near[1]))
	if near is String and zones.has(near):
		return tile_pos(f, zones[near].stand)
	if near is String and named.has(near):
		return named[near].pos
	if near is String and near == "door" and d.has("entrance"):
		return tile_pos(f, Vector2i(d.entrance.tile[0], d.entrance.tile[1]))
	# the middle of the floor
	var c := Vector3.ZERO
	var n := 0
	for t: Vector2i in room_of.get(f, {}):
		if not rooms[room_of[f][t]].get("annex", false):
			c += tile_pos(f, t)
			n += 1
	return c / maxf(n, 1)


func _no_go(f: int) -> Dictionary:
	## tiles of floor f that must stay free: the door, the stairs' ends, where each worker stands, where customers go
	var out := {}
	if f == 0 and d.has("entrance"):
		out[Vector2i(d.entrance.tile[0], d.entrance.tile[1])] = true
	for z in zones:
		if int(zones[z].floor) == f:
			out[zones[z].stand] = true
	for r: Dictionary in stair_runs:
		if int(r.floor) == f:
			out[r.from] = true
		if int(r.to_floor) == f:
			out[r.to] = true
	for k in ["counter", "queue"]:
		for e: Dictionary in d.get("customers", {}).get(k, []):
			out[Vector2i(e.tile[0], e.tile[1])] = true
	for z in zones:  # in front of a counter (the bar, the grille) where the customers stand
		var prop := String(d.stations.get(z, {}).get("prop", ""))
		if int(zones[z].floor) == f and muebles().get(prop, {}).get("counter", false) and named.has(z):
			var face := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(float(named[z].rot)))
			out[world_to_tile((named[z].pos as Vector3) + face * 0.75)] = true
	for t: Vector2i in _res_tiles.get(f, {}):
		out[t] = true
	for t: Vector2i in _res_stands.get(f, {}):
		out[t] = true
	return out


func _stands_alone(f: int, extra: Dictionary) -> Dictionary:
	## the places of floor f (where the worker of each station stands, and those kept for the stations of the upgrades)
	## that can be walked to from the door or the landing without stepping on another place, with `extra` taken too
	var base := Vector2i(-99, -99)
	if f == 0 and d.has("entrance"):
		base = Vector2i(d.entrance.tile[0], d.entrance.tile[1])
	for r: Dictionary in stair_runs:
		if int(r.to_floor) == f and base == Vector2i(-99, -99):
			base = r.to
	var out := {}
	if base == Vector2i(-99, -99):
		return out
	var stands := {}
	for z in zones:
		if int(zones[z].floor) == f and room_of[f].has(zones[z].stand):
			stands[zones[z].stand] = true
	for t: Vector2i in _res_stands.get(f, {}):
		stands[t] = true
	for st: Vector2i in stands:
		var block := extra.duplicate()
		for o: Vector2i in stands:
			if o != st and o != base:
				block[o] = true
		if st == base or not path(f, base, st, block).is_empty():
			out[st] = true
	return out


func _connected(f: int, extra: Dictionary) -> bool:
	## with the tiles of `extra` taken too, every free tile of floor f (the reserved ones as well) can still be walked to
	var free := []
	for t: Vector2i in room_of[f]:
		if not blocked[f].has(t) and not extra.has(t):
			free.append(t)
	if free.is_empty():
		return false
	var seen := {free[0]: true}
	var q := [free[0]]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		for nb in [cur + Vector2i(1, 0), cur + Vector2i(-1, 0), cur + Vector2i(0, 1), cur + Vector2i(0, -1)]:
			if not seen.has(nb) and passable(f, cur, nb, extra):
				seen[nb] = true
				q.append(nb)
	for t in free:
		if not seen.has(t):
			return false
	return true


func _wall_sides(t: Vector2i) -> Array:
	## the outer walls of the house a tile touches
	if not in_situ:
		return []
	var c := tile_pos(0, t)
	var hw := float(d.shell.w) / 2.0
	var hd := float(d.shell.d) / 2.0
	var out := []
	if c.z < -hd + 1.01:
		out.append("back")
	if c.x < -hw + 1.01:
		out.append("left")
	if c.x > hw - 1.01:
		out.append("right")
	if c.z > hd - 1.01:
		out.append("front")
	return out


## the place of an auto piece: {pos: [c, r], rot, snap, rect, tiles: [Vector2i], stand: Vector2i} or {} if there is none
func _find_slot(e: Dictionary, quiet := false) -> Dictionary:
	var f := int(e.get("floor", 0))
	if not room_of.has(f):
		return {}
	var id := String(e.get("id", e.get("prop", "")))
	var mb: Dictionary = muebles().get(id, {})
	var blocks := _blocks({"id": id, "walk": e.get("walk", false)})
	var hang: bool = mb.get("hang", false)
	var tall: bool = mb.get("tall", false) or hang
	var mode := String(e.auto) if e.auto is String else "wall"
	var near := _near_point(f, e.get("near", ""))
	var nogo := _no_go(f)
	var best := {}
	var best_score := 1e9
	var why := {"clash": 0, "tiles": 0, "stand": 0, "cut": 0, "through": 0}
	var alone := _stands_alone(f, {})  # the places reached today without walking through another one
	for t: Vector2i in room_of[f]:
		if rooms[room_of[f][t]].get("annex", false):
			continue
		if e.has("room") and room_of[f][t] != String(e.room):
			continue
		if (blocked[f].has(t) or nogo.has(t)) and not hang:
			continue  # what hangs may hang over a chest or a bench, and over where somebody stands
		var sides: Array = _wall_sides(t) if mode == "wall" else [""]
		for side: String in sides:
			if side == "front" and f == 0 and (t.x == int(d.entrance.tile[0]) or _shop_tile(t)):
				continue
			var p := {"id": id, "floor": f, "tile": [t.x, t.y]}
			if side != "":
				p["snap"] = side
			if e.has("gap"):
				p["gap"] = e.gap
			resolve_prop(p, d)
			var rot := float(p.get("rot", e.get("rot", 0.0)))
			var at := pos_at(f, Vector2(p.pos[0], p.pos[1]))
			var tb := turned_box(id, rot)
			var rc := Rect2(at.x + tb.position.x, at.z + tb.position.y, tb.size.x, tb.size.y)
			var clash := false
			var others: Array = _wall_used.get(f, []) if tall else []
			if blocks:
				others = others + obstacles[f]
			for o: Rect2 in others:
				# they overlap by more than 4 cm on both axes
				if minf(o.end.x, rc.end.x) - maxf(o.position.x, rc.position.x) > 0.04 and minf(o.end.y, rc.end.y) - maxf(o.position.y, rc.position.y) > 0.04:
					clash = true
					break
			if clash:
				why.clash += 1
				continue
			var tiles := _tiles_under(rc) if blocks else []
			var ok := true
			var extra := {}
			for bt: Vector2i in tiles:
				if not room_of[f].has(bt):
					continue  # the strip under the wall, beyond the tiles
				if blocked[f].has(bt) or nogo.has(bt):
					ok = false
					break
				extra[bt] = true
			if not ok:
				why.tiles += 1
				continue
			var stand := Vector2i(-99, -99)
			if e.has("zone"):
				# where its worker stands: the free tile in front of it, else beside it
				var front := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(rot))
				var want := world_to_tile(at + front * maxf(tb.size.x, tb.size.y) * 0.5 + front * 0.6)
				var cands := [want] + [t + Vector2i(1, 0), t + Vector2i(-1, 0), t + Vector2i(0, 1), t + Vector2i(0, -1)]
				for sc: Vector2i in cands:
					if room_of[f].has(sc) and not blocked[f].has(sc) and not extra.has(sc) and not _res_tiles.get(f, {}).has(sc) and not nogo.has(sc):
						stand = sc
						break
				if stand == Vector2i(-99, -99):
					why.stand += 1
					continue
			if not blocks and mode == "floor" and not e.get("walk", false):
				extra[t] = true  # a stool or a basket on the floor: not in the way either, though one can step past it
			if blocks or extra.has(t):
				for rt: Vector2i in _res_tiles.get(f, {}):
					extra[rt] = true
				if not _connected(f, extra):
					why.cut += 1
					continue
				# nor does it leave a place reached only through where somebody else works
				var still := _stands_alone(f, extra)
				var lost := false
				for st: Vector2i in alone:
					if not still.has(st):
						lost = true
				if lost:
					why.through += 1
					continue
			var score := Vector2(at.x - near.x, at.z - near.z).length() + (0.6 if side == "front" else 0.0)
			if score < best_score - 0.001:
				best_score = score
				best = {"pos": p.pos, "rot": rot, "snap": side, "rect": rc, "tiles": tiles, "stand": stand, "tile": t}
	if best.is_empty() and not quiet:
		dbg("no place for %s on floor %d: %s" % [id, f, why])
	return best


func _shop_tile(t: Vector2i) -> bool:
	## the tile behind a fold-down shop counter (a station whose tile is on the wall line in front of it)
	for z in zones:
		if int(zones[z].floor) == 0 and zones[z].stand == t and not room_of[0].has(zones[z].tile):
			return true
	return false


static var _order_cache := {}  # data file (and mirror) -> the order of its auto pieces (indices into _autos)


func _auto_order() -> Array:
	## the auto pieces in the order their places are looked for. Several fixed orders are tried with nothing bought
	## (the data's, the biggest first, and a few shuffles with fixed seeds) and the one that places most wins (a new
	## station counts as three pieces). The same for a building whatever is bought: each piece keeps its place.
	if _autos.size() < 2:
		return _autos.duplicate()
	var key := "%s|%s|%d" % [_src_path, d.get("_mirror", false), _autos.size()]
	if not _order_cache.has(key):
		var t0 := Time.get_ticks_usec()
		var keyed := []
		for i in _autos.size():
			var e: Dictionary = _autos[i].e
			var id := String(e.get("id", e.get("prop", "")))
			var tb := turned_box(id, 0.0)
			var blocks := _blocks({"id": id, "walk": e.get("walk", false)})
			keyed.append([0 if e.has("zone") else 1, int(e.get("prio", 0)), 0 if blocks else 1, -snappedf(tb.size.x * tb.size.y, 0.01), i])
		keyed.sort()
		var data_order := range(_autos.size())
		var tries: Array = [data_order, keyed.map(func(k): return k[-1])]
		var rng := RandomNumberGenerator.new()
		for sd in 10:
			rng.seed = 1000 + sd
			var o: Array = data_order.duplicate()
			for n in range(o.size() - 1, 0, -1):  # Fisher-Yates with its own generator: the same every run
				var m := rng.randi_range(0, n)
				var tmp = o[n]
				o[n] = o[m]
				o[m] = tmp
			# the low-priority pieces ("prio") still go last
			o.sort_custom(func(a, b): return int(_autos[a].e.get("prio", 0)) < int(_autos[b].e.get("prio", 0)))
			tries.append(o)
		var best: Array = data_order
		var best_score := -1
		for o: Array in tries:
			var sc := _try_order(o)
			if sc > best_score:
				best_score = sc
				best = o
		_order_cache[key] = best
		dbg("order of the %d upgrade pieces: %s (score %d of %d tried orders, %.0f ms)" % [_autos.size(), best, best_score, tries.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	return (_order_cache[key] as Array).map(func(i): return _autos[i])


func _try_order(o: Array) -> int:
	## how many auto pieces find a place in that order with none bought (state put back after)
	var keep_res := _res_tiles.duplicate(true)
	var keep_wall := _wall_used.duplicate(true)
	var keep_st := _res_stands.duplicate(true)
	var score := 0
	for i in o:
		var e: Dictionary = _autos[i].e
		var slot := _find_slot(e, true)
		if slot.is_empty():
			continue
		score += 3 if e.has("zone") else 1
		var f := int(e.get("floor", 0))
		for t: Vector2i in slot.tiles:
			_res_tiles[f][t] = true
		var mb: Dictionary = muebles().get(String(e.get("id", "")), {})
		if mb.get("hang", false) or mb.get("tall", false):
			_wall_used[f].append(slot.rect)
		if e.has("zone") and slot.stand != Vector2i(-99, -99):
			_res_stands[f][slot.stand] = true
	_res_tiles = keep_res
	_wall_used = keep_wall
	_res_stands = keep_st
	return score


func _auto_upgrades() -> void:
	## the places of the auto pieces, all of them in the order of the data (so each keeps its place whatever else is
	## bought), and the pieces of the finished ones
	var keep := {}
	for z in zones:
		keep["%d|%s" % [zones[z].floor, zones[z].stand]] = true
	for f in floors:
		if not _res_tiles.has(f):
			_res_tiles[f] = {}
		if not _res_stands.has(f):
			_res_stands[f] = {}
		if not _wall_used.has(f):
			_wall_used[f] = []
	for r: Dictionary in stair_runs:  # nothing hangs over a flight of stairs, nor where it comes up
		var a := Vector2(r.foot.x, r.foot.z)
		var b := Vector2(r.top.x, r.top.z)
		var rc := Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x), absf(b.y - a.y)).grow(0.5)
		_wall_used[int(r.floor)].append(rc)
		_wall_used[int(r.to_floor)].append(rc)
	for g: Dictionary in _ghosts:
		if not room_of.has(int(g.floor)):
			continue
		if g.blocks:
			for t: Vector2i in _tiles_under(g.rect):
				_res_tiles[int(g.floor)][t] = true
		if g.tall:
			_wall_used[int(g.floor)].append(g.rect)
	for gt in _ghost_tiles:
		if _res_stands.has(int(gt[0])):
			_res_stands[int(gt[0])][gt[1]] = true
	for a: Dictionary in _auto_order():
		var e: Dictionary = a.e
		var st: Dictionary = upgrade_state[a.node]
		var slot := _find_slot(e)
		if slot.is_empty():
			if e.has("or_needs") and st.status != "none":
				st.status = "needs"  # no room in this house: it comes with the extension the data names
				st.note = "%s%s" % [e.or_needs, (": " + String(e.or_note)) if e.has("or_note") else ""]
			elif st.status != "needs" and st.status != "none":
				st.status = "no_room"
				st.note = "sin sitio para %s" % String(e.get("id", e.get("prop", "")))
			continue
		var f := int(e.get("floor", 0))
		st.where.append([f, (slot.tile as Vector2i).x, (slot.tile as Vector2i).y])
		if not _res_tiles.has(f):
			_res_tiles[f] = {}
		if not _wall_used.has(f):
			_wall_used[f] = []
		if a.done:
			var p: Dictionary = e.duplicate()
			p.erase("auto")
			p["id"] = String(e.get("id", e.get("prop", "")))
			p["pos"] = slot.pos
			p["rot"] = slot.rot
			p["_upg"] = a.node
			if slot.snap != "":
				p["wall"] = slot.snap
			if e.has("zone"):
				d.stations[String(e.zone)] = {"floor": f, "tile": [(slot.tile as Vector2i).x, (slot.tile as Vector2i).y], "stand": [(slot.stand as Vector2i).x, (slot.stand as Vector2i).y],
					"prop": p.id, "name": String(e.get("name", e.zone)), "kind": String(e.get("kind", "craft"))}
				zones[String(e.zone)] = {"tiles": [slot.tile, slot.stand], "floor": f, "stand": slot.stand, "tile": slot.tile}
				keep["%d|%s" % [f, slot.stand]] = true
				_up_zones[String(e.zone)] = true
			_place(p)
			_block_holder(_holders[-1], keep)
		else:
			# not bought: its place waits for it
			for t: Vector2i in slot.tiles:
				_res_tiles[f][t] = true
			var mb: Dictionary = muebles().get(String(e.get("id", "")), {})
			if mb.get("hang", false) or mb.get("tall", false):
				_wall_used[f].append(slot.rect)
		if e.has("zone") and slot.stand != Vector2i(-99, -99):
			_res_stands[f][slot.stand] = true
	for o: Dictionary in _ons:
		var e: Dictionary = o.e
		var names: Array = e.on if e.on is Array else [e.on]
		var base := {}
		for nm in names:
			if named.has(String(nm)):
				base = named[String(nm)]
				break
		if base.is_empty():
			upgrade_state[o.node].status = "no_room"
			upgrade_state[o.node].note = "falta la pieza sobre la que va (%s)" % [names]
			continue
		var off: Array = e.get("off", [0, 0])
		var at: Vector3 = (base.pos as Vector3) + Vector3(float(off[0]), 0, float(off[1])).rotated(Vector3.UP, deg_to_rad(float(base.rot)))
		var top := float(e.get("y", muebles().get(String(base.id), {}).get("top_h", 0.8)))
		var f := int(base.floor)
		var cr := Vector2((at.x - origin.x) / TILE - 0.5, (at.z - origin.y) / TILE - 0.5)
		_place({"id": String(e.id), "floor": f, "pos": [cr.x, cr.y], "y": top, "rot": float(base.rot) + float(e.get("rot", 0.0)), "_upg": o.node})
		upgrade_state[o.node].where.append([f, floori(cr.x + 0.5), floori(cr.y + 0.5)])
	if not _autos.is_empty() or not _ons.is_empty():
		_plan_log()
	if OS.is_debug_build() and not upgrade_state.is_empty():
		var lines := []
		for node in upgrade_state:
			lines.append("%s: %s %s %s" % [node, upgrade_state[node].status, upgrade_state[node].where, upgrade_state[node].note])
		dbg("upgrades (%s):\n  %s" % ["list given: %s" % [done_upgrades] if upgrades_given else "no list: base look", "\n  ".join(lines)])
