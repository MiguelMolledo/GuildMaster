class_name VisualPaths
extends RefCounted
## The ONLY place that turns an id into a file path (docs/protocolos/editar-a-mano.md). data/ keeps ids and figures,
## never paths: every visible thing has its scene at game/visuals/<kind>/<id>.tscn (with the greybox inside until the
## art arrives), and art and audio files are named after their id in snake_case (docs/ASSETS.md).
##
## Kinds: buildings (exterior of a building type), interiors (inside of a building type: kit, a Marker2D per station
## under Stations, upgrade visuals under Upgrades), stations (one station of an interior, by zone id), props (things
## standing on a map tile: by tile kind, stalls by "stall_<stall id>"; H7: the plaza's bench and dice_table),
## characters (by visual id, see character_id) and, H7, bubbles (over a head: the social activity's bubble or an
## emotion icon, ids of data/town.json). A missing scene falls back to <kind>/_generic.tscn (a visible placeholder) and says so in debug.
##
## Every visual scene has a Marker2D "Feet" (the point that rests on the anchor: a tile centre, the centre of a
## footprint, a walker's feet) and may have a Marker2D "Top" (how high it stands: where the sign, the bar or the name
## goes, and the height of its click area). Buildings and filler houses also have a Marker2D "Door" on the threshold
## of the drawn door, with its metadata (door_of; docs/protocolos/generar-ciudad.md §Puertas).

const ROOT: String = "res://game/visuals"
const KINDS: Array[String] = ["buildings", "interiors", "stations", "props", "characters", "bubbles"]
const GENERIC: String = "_generic"
const ART_ROOT: String = "res://assets/art"
const AUDIO_ROOT: String = "res://assets/audio"
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "wav"]

static var _cache: Dictionary = {}       # path -> PackedScene (or null when it does not exist)
static var _warned: Dictionary = {}      # "kind/id" -> true (the fallback is reported once)
static var _doors: Dictionary = {}       # "kind/id" -> door_of() (scenes do not change while the game runs)


## res://game/visuals/<kind>/<id>.tscn (whether it exists or not).
static func scene_path(kind: String, id: String) -> String:
	return "%s/%s/%s.tscn" % [ROOT, kind, id]


## Whether <kind>/<id>.tscn exists (no fallback).
static func has_scene(kind: String, id: String) -> bool:
	return _load(scene_path(kind, id)) != null


## The scene of `id`, else the generic one of its kind (reported once in debug), else null.
static func scene(kind: String, id: String) -> PackedScene:
	var ps := _load(scene_path(kind, id))
	if ps != null:
		return ps
	var key := "%s/%s" % [kind, id]
	if not _warned.has(key):
		_warned[key] = true
		if OS.is_debug_build():
			print("[Visuals] no scene for %s: using %s/%s.tscn" % [key, kind, GENERIC])
	return _load(scene_path(kind, GENERIC))


## A new instance of the visual of `id` (the generic one if it has none). Never null: an empty Node2D at worst.
static func instantiate(kind: String, id: String) -> Node2D:
	var ps := scene(kind, id)
	var n: Node2D = ps.instantiate() as Node2D if ps != null else null
	if n == null:
		n = Node2D.new()
		n.name = id.to_pascal_case()
	return n


## Places `visual` so its Feet marker lands on `anchor` (in its parent's coordinates).
static func place(visual: Node2D, anchor: Vector2) -> void:
	visual.position = anchor - feet(visual)


## The Feet marker's position inside the visual (ZERO without one).
static func feet(visual: Node) -> Vector2:
	var m := visual.get_node_or_null("Feet") as Node2D
	return m.position if m != null else Vector2.ZERO


## How high the visual stands above its feet, in pixels (its Top marker), or `default` without one.
static func top_height(visual: Node, default: float) -> float:
	var t := visual.get_node_or_null("Top") as Node2D
	if t == null:
		return default
	return feet(visual).y - t.position.y


## The visual id of a character: <role>_<m|f>, role = worker (has a job), artisan (the human family or a rival
## family with an AI profile) or townsfolk (everybody else). Matches the ids of assets/inventario.json
## (chr_artisan_m, npc_worker_f, npc_townsfolk_m...).
static func character_id(ch: Dictionary, family: Dictionary) -> String:
	var role := "townsfolk"
	if ch.get("job") is Dictionary:
		role = "worker"
	elif str(ch.get("controlled_by", "")) == "human" or str(family.get("ai_profile", "")) != "":
		role = "artisan"
	return "%s_%s" % [role, "f" if bool(ch.get("female", false)) else "m"]


## Población: the texture of the pool's portrait `id` (assets/art/portraits/index.json v1, its README; the id the
## person keeps, Cast.pick_portrait): its face (32) for `size` 32, its bust (64) for 64. null if the index has no such
## id (the greybox stays).
static func portrait_file(id: String, size: int = 32) -> Texture2D:
	var e: Dictionary = (portrait_index().get("_ids", {}) as Dictionary).get(id, {})
	if e.is_empty():
		return null
	var path := PORTRAIT_DIR.path_join(str(e.get("face" if size <= 32 else "file", e.get("file", ""))))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## A portrait for somebody who has no id yet (a game from before v14 until its next year change): the candidates of
## sex + band + type, then the index's fallback and commoner, the one of `seed` (stable, the id number of the person).
static func portrait(type: String, stage: String, female: bool, seed: int, size: int = 32) -> Texture2D:
	var idx := portrait_index()
	if idx.is_empty():
		return null
	var sex := "f" if female else "m"
	var fb: Variant = (idx.get("fallback", {}) as Dictionary).get(type, {})
	for t: String in [type, str(fb.get(stage, "")) if fb is Dictionary else "", "commoner"]:
		var found: Array = (idx["_by"] as Dictionary).get("%s|%s|%s" % [sex, stage, t], [])
		if not found.is_empty():
			return portrait_file(str(found[posmod(seed, found.size())]["id"]), size)
	return null


const PORTRAIT_DIR: String = "res://assets/art/portraits"
static var _portrait_index: Dictionary = {}


## The pool's index.json ({} without one), with "_by" {"sex|age|type": [entries sorted by id]} and "_ids" {id: entry}.
static func portrait_index() -> Dictionary:
	if not _portrait_index.is_empty():
		return _portrait_index
	var out := {"_none": true}
	var path := PORTRAIT_DIR.path_join("index.json")
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and int((d as Dictionary).get("version", 0)) == 1:
			out = d
			var by := {}
			var ids := {}
			for e: Variant in out.get("portraits", []):
				if e is Dictionary:
					ids[str(e.get("id", ""))] = e
					var k := "%s|%s|%s" % [e.get("sex", ""), e.get("age", ""), e.get("type", "")]
					if not by.has(k):
						by[k] = []
					(by[k] as Array).append(e)
			for k: String in by:
				(by[k] as Array).sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["id"]) < str(y["id"]))
			out["_by"] = by
			out["_ids"] = ids
		elif OS.is_debug_build():
			print("[Visuals] %s: not an index of version 1" % path)
	_portrait_index = out
	return {} if out.has("_none") else out


## The icon of an item: assets/art/icons/<item_id>.png (null until it exists).
static func icon(item_id: String) -> Texture2D:
	var p := "%s/icons/%s.png" % [ART_ROOT, item_id]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## The small icon of an item for the UI lists (10 px font): assets/art/icons/small/<item_id>.png, 16×16, made from
## the 32×32 one by tools/art/derivar_guild.py (null until it exists).
static func icon_small(item_id: String) -> Texture2D:
	var p := "%s/icons/small/%s.png" % [ART_ROOT, item_id]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## The illustration of a narrative page (docs/ui/04_kit_de_pagina.md): assets/art/illustrations/<kind>/<id>.png
## (240×135, cards) or <id>_192.png (192×108, notices), from the art branch; until it arrives, the pilot copy of the
## page kit assets/art/ui/page_kit/piloto/<kind singular>_<id>[_192].png. null = no illustration (the card goes
## without it).
static func illustration(kind: String, id: String, small: bool = false) -> Texture2D:
	var suffix := "_192" if small else ""
	for p: String in ["%s/illustrations/%s/%s%s.png" % [ART_ROOT, kind, id, suffix],
			"%s/ui/page_kit/piloto/%s_%s%s.png" % [ART_ROOT, kind.trim_suffix("s"), id, suffix]]:
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


## The ground texture of a tile kind (data/tiles.json): assets/art/tiles/<kind>.png (null until it exists: the ground
## keeps the kind's greybox colour).
static func tile(kind: String) -> Texture2D:
	var p := "%s/tiles/%s.png" % [ART_ROOT, kind]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## The audio files of a sound id: assets/audio/<folder>/<id>.<ogg|wav>, or its variants <id>_01, <id>_02... when
## there is no plain file. [] = no file yet (the game stays silent).
static func audio_files(folder: String, id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for ext: String in AUDIO_EXTENSIONS:
		var p := "%s/%s/%s.%s" % [AUDIO_ROOT, folder, id, ext]
		if ResourceLoader.exists(p):
			out.append(p)
			return out
	for i: int in range(1, 100):
		var found := false
		for ext: String in AUDIO_EXTENSIONS:
			var p := "%s/%s/%s_%02d.%s" % [AUDIO_ROOT, folder, id, i, ext]
			if ResourceLoader.exists(p):
				out.append(p)
				found = true
				break
		if not found:
			break
	return out


static func _load(path: String) -> PackedScene:
	if _cache.has(path):
		return _cache[path]
	var ps: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	_cache[path] = ps
	return ps



## The drawn door of <kind>/<id>.tscn, from its Marker2D "Door" (tools/city/marcar_puertas.py; exported for the town
## tools to data/building_sprites.json): {side: "SW"|"SE"|"NE"|"NW" (the face of the footprint: SW looks to +row, SE
## to +col, NE to -row, NW to -col), tile: Vector2i (the door's tile from the footprint's origin), footprint:
## Vector2i, mirror: bool (may be mirrored), back / front: the scene id seen from the other side ("" if none),
## position: Vector2 (the threshold from Feet)}, or {} without a marker.
static func door_of(kind: String, id: String) -> Dictionary:
	var key := "%s/%s" % [kind, id]
	if _doors.has(key):
		return _doors[key]
	var out := {}
	if has_scene(kind, id):
		var n := instantiate(kind, id)
		var m := n.get_node_or_null("Door") as Marker2D
		if m != null:
			out = {"side": str(m.get_meta("side", "")), "tile": m.get_meta("tile", Vector2i.ZERO),
				"footprint": m.get_meta("footprint", Vector2i.ONE), "mirror": bool(m.get_meta("mirror", false)),
				"back": str(m.get_meta("back", "")), "front": str(m.get_meta("front", "")), "position": m.position}
		n.free()
	_doors[key] = out
	return out
