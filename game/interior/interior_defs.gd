class_name InteriorDefs
extends RefCounted
## The data of the interiors (docs/gdd/04g_interiores.md 4.6.5.2), read by the view only: data/interiors/<building
## type>.json (rooms, walls and doors, levels, stairs, stations, customer and idle spots, props and the props the rules
## placed, upgrades), data/interiors/lights.json and the prop library data/props/interior.json. Edited by hand and
## checked by tools/interiors/interiores.py (validar, reglas, vista). Cached; the sim never reads them.

const DIR: String = "res://data/interiors"
const CATALOG: String = "res://data/props/interior.json"
const LIGHTS: String = "res://data/interiors/lights.json"
const STEP_PX: float = 8.0   # one step of a pit or a dais, in px on screen

static var _defs: Dictionary = {}
static var _catalog: Dictionary = {}
static var _lights: Dictionary = {}


## The interior of building type `type`, or {} if it has no data (then its hand-made scene is used).
static func def_of(type: String) -> Dictionary:
	if not _defs.has(type):
		var d: Variant = _read("%s/%s.json" % [DIR, type])
		_defs[type] = d if d is Dictionary else {}
	return _defs[type]


static func has_def(type: String) -> bool:
	return not def_of(type).is_empty()


## A prop of the library: {category, footprint, size, feet, height, walkable, wall, on_top, hangs, mirror, trades,
## style}, or {}.
static func prop(id: String) -> Dictionary:
	if _catalog.is_empty():
		var c: Variant = _read(CATALOG)
		_catalog = (c as Dictionary).get("props", {}) if c is Dictionary else {}
	return _catalog.get(id, {})


## The light of a room by id ({color, mode, alpha}), or {}.
static func light(id: String) -> Dictionary:
	if _lights.is_empty():
		var l: Variant = _read(LIGHTS)
		_lights = (l as Dictionary).get("lights", {}) if l is Dictionary else {}
	return _lights.get(id, {})


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	if v == null and OS.is_debug_build():
		print("[InteriorDefs] JSON no válido: %s" % path)
	return v


## Drops the cache (the tests, after editing a file).
static func clear() -> void:
	_defs.clear()
	_catalog.clear()
	_lights.clear()


# --- geometry, the same as tools/interiors/interiores.py --------------------------------------------------------

static func tiles_of(p: Dictionary) -> Array[Vector2i]:
	var pr := prop(str(p.get("id", "")))
	var fp: Array = pr.get("footprint", [1, 1])
	var a := int(fp[0])
	var b := int(fp[1])
	var t: Array = p.get("tile", [0, 0])
	var c := int(t[0])
	var r := int(t[1])
	var out: Array[Vector2i] = []
	if bool(p.get("flip", false)):
		for i: int in a:
			for j: int in b:
				out.append(Vector2i(c - i, r - j))
	else:
		for i: int in a:
			for j: int in b:
				out.append(Vector2i(c - j, r - i))
	return out


## Where a placed prop stands (its feet), in world px of its floor (no floor or step offset).
static func feet_world(p: Dictionary) -> Vector2:
	var ts := tiles_of(p)
	var s := Vector2.ZERO
	for t: Vector2i in ts:
		s += Iso.tile_to_world(t)
	return s / float(maxi(1, ts.size()))


## The screen offset of floor `level` (the upper floor drawn floor_height px higher).
static func floor_offset(d: Dictionary, level: int) -> Vector2:
	return Vector2(0, -float(level) * float(d.get("floor_height", 80)))


## level → {Vector2i tile: room id}.
static func room_map(d: Dictionary) -> Dictionary:
	var out := {}
	for room: Dictionary in d.get("rooms", []):
		var f := int(room.get("floor", 0))
		if not out.has(f):
			out[f] = {}
		for rc: Array in room.get("rects", []):
			for r: int in range(int(rc[1]), int(rc[3]) + 1):
				for c: int in range(int(rc[0]), int(rc[2]) + 1):
					out[f][Vector2i(c, r)] = str(room["id"])
	return out


## The step of a tile (−1 pit, +1 dais, 0 flat).
static func step_of(d: Dictionary, level: int, t: Vector2i) -> int:
	for lv: Dictionary in d.get("levels", []):
		if int(lv.get("floor", 0)) != level:
			continue
		var rc: Array = lv["rect"]
		if t.x >= int(rc[0]) and t.x <= int(rc[2]) and t.y >= int(rc[1]) and t.y <= int(rc[3]):
			return int(lv.get("step", 0))
	return 0


## World position of a spot (floor, tile, fractional tile) with its floor and step offsets.
static func spot_world(d: Dictionary, level: int, tile: Vector2) -> Vector2:
	var t := Vector2i(roundi(tile.x), roundi(tile.y))
	return Iso.tilef_to_world(tile) + floor_offset(d, level) + Vector2(0, -float(step_of(d, level, t)) * STEP_PX)
