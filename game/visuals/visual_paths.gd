class_name VisualPaths
extends RefCounted
## The ONLY place that turns an id into a file path (docs/protocolos/editar-a-mano.md). data/ keeps ids and figures,
## never paths: every visible thing has its scene at game/visuals/<kind>/<id>.tscn (with the greybox inside until the
## art arrives), and art and audio files are named after their id in snake_case (docs/ASSETS.md).
##
## Kinds: buildings (exterior of a building type), interiors (inside of a building type: kit, a Marker2D per station
## under Stations, upgrade visuals under Upgrades), stations (one station of an interior, by zone id), props (things
## standing on a map tile: by tile kind, stalls by "stall_<stall id>") and characters (by visual id, see
## character_id). A missing scene falls back to <kind>/_generic.tscn (a visible placeholder) and says so in debug.
##
## Every visual scene has a Marker2D "Feet" (the point that rests on the anchor: a tile centre, the centre of a
## footprint, a walker's feet) and may have a Marker2D "Top" (how high it stands: where the sign, the bar or the name
## goes, and the height of its click area).

const ROOT: String = "res://game/visuals"
const KINDS: Array[String] = ["buildings", "interiors", "stations", "props", "characters"]
const GENERIC: String = "_generic"
const ART_ROOT: String = "res://assets/art"
const AUDIO_ROOT: String = "res://assets/audio"
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "wav"]

static var _cache: Dictionary = {}       # path -> PackedScene (or null when it does not exist)
static var _warned: Dictionary = {}      # "kind/id" -> true (the fallback is reported once)


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


## The icon of an item: assets/art/icons/<item_id>.png (null until it exists).
static func icon(item_id: String) -> Texture2D:
	var p := "%s/icons/%s.png" % [ART_ROOT, item_id]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


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
