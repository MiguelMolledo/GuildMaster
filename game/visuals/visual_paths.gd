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
## goes, and the height of its click area).

const ROOT: String = "res://game/visuals"
const KINDS: Array[String] = ["buildings", "interiors", "stations", "props", "characters", "bubbles"]
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


## Población: the base portrait of a person from the pool's index (assets/art/portraits/index.json v1, its README):
## the candidates of `sex` + `age` (band) + `type`; without any, the index's fallback[type][age], then the types of
## data/view.json portraits.fallback (commoner exists in every band and sex). Of them, the one numbered `nn` (the id
## <sex>_<age>_<type>_<nn>, kept by the person for life); if the pool has no such number yet, a guaranteed one (1..4),
## else the candidates in id order. `size` 32 = the face, 64 = the bust. While the production pool is not in main,
## the fal pilot's index (assets/art/portraits_pilot/index.json) stands in. null without any: the greybox.
static func portrait(type: String, stage: String, female: bool, nn: int, size: int = 32) -> Texture2D:
	for dir: String in PORTRAIT_DIRS:
		var idx := portrait_index(dir)
		if idx.is_empty():
			continue
		var sex := "f" if female else "m"
		var types: Array = [type]
		var fb: Variant = (idx.get("fallback", {}) as Dictionary).get(type, {})
		if fb is Dictionary and (fb as Dictionary).has(stage):
			types.append(str(fb[stage]))
		for t: Variant in (ViewConfig.value("portraits", {}) as Dictionary).get("fallback", ["commoner"]):
			if not str(t) in types:
				types.append(str(t))
		for t: String in types:
			var found: Array = (idx["_by"] as Dictionary).get("%s|%s|%s" % [sex, stage, t], [])
			if found.is_empty():
				continue
			var pick: Dictionary = found[posmod(nn - 1, found.size())]
			for want: int in [nn, (posmod(nn - 1, 4)) + 1]:
				var id := "%s_%s_%s_%02d" % [sex, stage, t, want]
				for e: Dictionary in found:
					if str(e.get("id", "")) == id:
						pick = e
						break
				if str(pick.get("id", "")) == id:
					break
			var rel := str(pick.get("face" if size <= 32 else "file", pick.get("file", "")))
			var path := dir.path_join(rel)
			if ResourceLoader.exists(path):
				return load(path) as Texture2D
	return null


const PORTRAIT_DIRS: Array[String] = ["res://assets/art/portraits", "res://assets/art/portraits_pilot"]
static var _portrait_index: Dictionary = {}  # dir -> the index with "_by": {"sex|age|type": [entries sorted by id]}


## The pool's index.json of `dir` ({} without one), with its entries grouped by sex, age band and type.
static func portrait_index(dir: String) -> Dictionary:
	if _portrait_index.has(dir):
		return _portrait_index[dir]
	var out := {}
	var path := dir.path_join("index.json")
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and int((d as Dictionary).get("version", 0)) == 1:
			out = d
			var by := {}
			for e: Variant in out.get("portraits", []):
				if e is Dictionary:
					var k := "%s|%s|%s" % [e.get("sex", ""), e.get("age", ""), e.get("type", "")]
					if not by.has(k):
						by[k] = []
					(by[k] as Array).append(e)
			for k: String in by:
				(by[k] as Array).sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["id"]) < str(y["id"]))
			out["_by"] = by
		elif OS.is_debug_build():
			print("[Visuals] %s: not an index of version 1" % path)
	_portrait_index[dir] = out
	return out


## The icon of an item: assets/art/icons/<item_id>.png (null until it exists).
static func icon(item_id: String) -> Texture2D:
	var p := "%s/icons/%s.png" % [ART_ROOT, item_id]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## The small icon of an item for the UI lists (10 px font): assets/art/icons/small/<item_id>.png, 16×16, made from
## the 32×32 one by tools/art/derivar_guild.py (null until it exists).
static func icon_small(item_id: String) -> Texture2D:
	var p := "%s/icons/small/%s.png" % [ART_ROOT, item_id]
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
