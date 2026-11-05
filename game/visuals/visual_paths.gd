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
## The illustrated parchment of a region (data/world/region.json id; tools/art/fal_region.py): null if missing.
static func region_map(region_id: String) -> Texture2D:
	var p := "%s/region/%s_map.png" % [ART_ROOT, region_id]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## Viajes: the art of the region (assets/inventario.json). Each returns the file when it is there and else a visible
## placeholder (a flat box of the given colour with a dark border), so a missing piece still shows.
##   city_art(id): the illustration of a settlement's page, 240×135 (illus_city_<id>:
##     assets/art/illustrations/city_<id>.png)
##   region_token(variant): the family's token on the region map, 24×44, feet at the bottom centre; its cloth is keyed
##     for identity_swap.gdshader (ui_region_family_token: assets/art/region/family_token.png, the banner by default;
##     «shield»: family_token_shield.png)
##   region_caravan(variant): a caravan on the region map, facing east (mirrored to go west) (ui_region_caravan:
##     assets/art/region/caravan.png, 56×34, the ox cart by default; «cart»: caravan_cart.png, 48×24)
##   region_icon(id): tariff | treaty | caravan | city_reputation (ui_icon_<id>: assets/art/ui/icons/icon_<id>.png,
##     32×32; small: its small/ 16×16)
const REGION_ICONS: Dictionary = {"tariff": "#c8a84e", "treaty": "#8a2a1e", "caravan": "#7a5230",
	"city_reputation": "#4a6a8a"}
static var _placeholders: Dictionary = {}


const TOKEN_FILES: Dictionary = {"banner": "family_token", "shield": "family_token_shield"}
const CARAVAN_FILES: Dictionary = {"ox": "caravan", "cart": "caravan_cart"}


static func city_art(id: String) -> Texture2D:
	return _art_or("%s/illustrations/city_%s.png" % [ART_ROOT, id], Vector2i(240, 135), Color("#a08a64"))


static func region_token(variant: String = "banner") -> Texture2D:
	return _art_or("%s/region/%s.png" % [ART_ROOT, str(TOKEN_FILES.get(variant, "family_token"))], Vector2i(24, 44),
		Color("#c8a84e"))


static func region_caravan(variant: String = "ox") -> Texture2D:
	return _art_or("%s/region/%s.png" % [ART_ROOT, str(CARAVAN_FILES.get(variant, "caravan"))], Vector2i(56, 34),
		Color("#7a5230"))


static func region_icon(id: String, small: bool = true) -> Texture2D:
	var size := 16 if small else 32
	return _art_or("%s/ui/icons/%sicon_%s.png" % [ART_ROOT, "small/" if small else "", id], Vector2i(size, size),
		Color(str(REGION_ICONS.get(id, "#888888"))))


## Whether `tex` is one of these placeholders (the view then writes what it stands for over it).
static func is_placeholder(tex: Texture2D) -> bool:
	return tex != null and tex.has_meta("placeholder")


static func _art_or(path: String, size: Vector2i, color: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var key := "%s|%s|%s" % [path, size, color.to_html()]
	if not _placeholders.has(key):
		var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(color)
		var edge := Color("#2a1f14")
		for x: int in size.x:
			img.set_pixel(x, 0, edge)
			img.set_pixel(x, size.y - 1, edge)
		for y: int in size.y:
			img.set_pixel(0, y, edge)
			img.set_pixel(size.x - 1, y, edge)
		var tex := ImageTexture.create_from_image(img)
		tex.set_meta("placeholder", path)
		_placeholders[key] = tex
	return _placeholders[key]


static func illustration(kind: String, id: String, small: bool = false) -> Texture2D:
	var suffix := "_192" if small else ""
	var art := str(EVENT_ILLUSTRATION_ALIAS.get(id, id)) if kind == "events" else id
	for p: String in ["%s/illustrations/%s/%s%s.png" % [ART_ROOT, kind, art, suffix],
			"%s/illustrations/%s/%s%s.png" % [ART_ROOT, kind, id, suffix],
			"%s/ui/page_kit/piloto/%s_%s%s.png" % [ART_ROOT, kind.trim_suffix("s"), id, suffix]]:
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


## The names the art uses for the ids of the festivals (fiestas, 4.25) and the incidents (vida, 4.24.5): arte-fal-2
## kept its Spanish names (ids illus_<name> in assets/inventario.json), assets/art/illustrations/events/<name>[_192].png.
## The only alias table of the event illustrations: illustration("events", id) applies it (FestivalPage, IncidentPage).
## The art's rescate.png and ladron.png have no id of the sim yet.
const EVENT_ILLUSTRATION_ALIAS: Dictionary = {"holy_week": "semana_santa", "mayday_corpus": "mayos_corpus",
	"st_john": "san_juan", "harvest_fair": "siega_feria", "st_michael": "san_miguel", "all_saints_matanza": "matanza",
	"christmas": "navidad", "carnival": "carnaval", "altercation": "altercado", "bandit_raid": "asalto_bandidos",
	"kidnapping": "secuestro"}


## Fiestas (04f 4.28.3): the illustration of `id`, or a visible provisional greybox (240×135, 192×108 small) that
## says what it stands for (meta «label»; PageCard writes it on it) until the art is at
## assets/art/illustrations/<kind>/<id>[_192].png.
static func illustration_or_greybox(kind: String, id: String, small: bool = false) -> Texture2D:
	var t := illustration(kind, id, small)
	if t != null:
		return t
	var size := Vector2i(192, 108) if small else Vector2i(240, 135)
	var g := _art_or("%s/illustrations/%s/%s%s.png" % [ART_ROOT, kind, id, "_192" if small else ""], size, Color("#7a6a4a"))
	g.set_meta("label", id)
	return g


## Fiestas (04f 4.25.3): the names the art uses for the festival props of data/festivals.json view decor (arte-fal-2,
## ids prop_fiesta_<name> in assets/inventario.json): game/visuals/props/fiesta/<name>.tscn. A prop with no art yet
## (the animals) keeps its id and falls to the labelled greybox (FestivalLayer).
const FESTIVAL_PROP_ALIAS: Dictionary = {"bunting": "banderola", "banner": "pendon", "lanterns": "farolillo",
	"maypole": "mayo", "garland": "guirnalda", "cart_ring": "cerco_carros", "bonfire": "hoguera",
	"fair_stall": "puesto_feria", "pen": "corral", "long_tables": "mesa_larga", "nativity": "belen",
	"triumphal_arch": "arco_triunfal", "stage": "tablado", "tilt_yard": "liza"}


## The scene id (under props/) of festival prop `id`: fiesta/<the art's name>.
static func festival_prop(id: String) -> String:
	return "fiesta/" + str(FESTIVAL_PROP_ALIAS.get(id, id))


## Duelo (docs/ui/mecanicas/combate.md §8): the names the art uses for the duel's ids (the art keeps its names, as in
## assets/inventario.json): icons icon_<name>.png, illustrations <name>[_192].png.
const DUEL_ICON_ALIAS: Dictionary = {"yield": "surrender"}
const DUEL_ILLUSTRATION_ALIAS: Dictionary = {"won": "victory", "win": "victory", "lost": "defeat", "lose": "defeat"}


## Duelo: a duel effect (strike, parry, feint, hit) from assets/art/vfx/duel_<kind>/: the strip duel_<kind>.png and its
## duel_<kind>.json (frames, frame_w, frame_h, fps, loop, start_frame, offset {x, y}: the frame's top-left from the
## feet of who does it, facing: the side it looks to; the other side is drawn mirrored). {frames: [Texture2D], fps,
## loop, offset: Vector2, facing} or {} until it exists (the arena draws its provisional effect by code). Without the
## .json, square frames of the strip's height centred over the feet.
static func duel_vfx(kind: String) -> Dictionary:
	var dir := "%s/vfx/duel_%s" % [ART_ROOT, kind]
	var strip := "%s/duel_%s.png" % [dir, kind]
	if not ResourceLoader.exists(strip):
		return {}
	var t := load(strip) as Texture2D
	var meta: Dictionary = {}
	var jp := "%s/duel_%s.json" % [dir, kind]
	if FileAccess.file_exists(jp):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if j is Dictionary:
			meta = j
	var fh := int(meta.get("frame_h", t.get_height()))
	var fw := int(meta.get("frame_w", fh))
	var n := int(meta.get("frames", maxi(1, t.get_width() / maxi(1, fw))))
	var frames: Array[Texture2D] = []
	for i: int in range(int(meta.get("start_frame", 0)), n):
		var a := AtlasTexture.new()
		a.atlas = t
		a.region = Rect2(i * fw, 0, fw, fh)
		frames.append(a)
	var off: Dictionary = meta.get("offset", {"x": -fw / 2, "y": -fh})
	return {"frames": frames, "fps": float(meta.get("fps", 12)), "loop": bool(meta.get("loop", false)),
		"offset": Vector2(float(off.get("x", 0)), float(off.get("y", 0))), "size": Vector2(fw, fh),
		"facing": str(meta.get("facing", "e"))}


## Duelo: the icon of a duel action or figure (strike, parry, feint, yield, auto, breath, touch, challenge):
## assets/art/ui/icons/duel/icon_<name>.png (32) or small/icon_<name>.png (16). null until it exists.
static func duel_icon(id: String, small: bool = false) -> Texture2D:
	var name := str(DUEL_ICON_ALIAS.get(id, id))
	for f: String in ["icon_" + name, name]:
		var p := "%s/ui/icons/duel/%s%s.png" % [ART_ROOT, "small/" if small else "", f]
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


## Duelo: the illustration of a duel card (won/victory, lost/defeat, draw, challenge): 240×135 for cards, `small`
## 192×108 (<name>_192) for notices. The page kit's place (assets/art/illustrations/duel/, illustration()) or the one
## assets/inventario.json reserves (assets/art/ui/illustrations/duel/). null = the card goes without it.
static func duel_illustration(id: String, small: bool = false) -> Texture2D:
	var name := str(DUEL_ILLUSTRATION_ALIAS.get(id, id))
	var t := illustration("duel", name, small)
	if t != null:
		return t
	var p := "%s/ui/illustrations/duel/%s%s.png" % [ART_ROOT, name, "_192" if small else ""]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## Juegos (04f §4.26, §4.28.3): a piece of a game's screen, assets/art/ui/games/<game>/<id>.png (the dice, the table,
## the cards, the lists, the horses...). null until the art arrives: the board draws its greybox with a label.
## Kept here: a texture loaded inside a _draw and dropped right after is freed before the canvas draws it (it comes
## out white), so the boards' pieces stay referenced.
static var _game_art: Dictionary = {}


static func game_art(game: String, id: String) -> Texture2D:
	var key := "%s/%s" % [game, id]
	if _game_art.has(key):
		return _game_art[key]
	var t := _game_art_load(key, id)
	_game_art[key] = t
	return t


static func _game_art_load(key: String, id: String) -> Texture2D:
	var alias := str(GAME_ART_ALIAS.get(key, ""))
	if alias == "" and key.begins_with("dice/die_"):
		alias = "dados/d" + id.substr(4)
	for rel: String in ([alias] if alias != "" else []) + [key]:
		var p := "%s/ui/games/%s.png" % [ART_ROOT, rel]
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


## Juegos: the names the art uses for the boards' pieces (assets/inventario.json ui_game_mesa, ui_game_dados,
## ui_game_naipes; the art keeps its names): the tavern table is the board of the dice, the cards and the pulso.
const GAME_ART_ALIAS: Dictionary = {"dice/table": "mesa/mesa", "naipes/table": "mesa/mesa", "pulso/table": "mesa/mesa",
	"dice/shadow": "dados/shadow", "dice/cup": "dados/cup"}


## Juegos: the icon of a game (assets/art/ui/icons/game_<game>.png, `small` from small/), null until it exists.
static func game_icon(game: String, small: bool = false) -> Texture2D:
	var p := "%s/ui/icons/%sgame_%s.png" % [ART_ROOT, "small/" if small else "", game]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## Juegos: the illustration of a game's result or of a competition (assets/art/illustrations/events/<id>.png, 240×135;
## `small`: <id>_192.png, 192×108), shared with the fiestas' cards. null until it exists.
static func game_illustration(id: String, small: bool = false) -> Texture2D:
	return illustration("events", id, small)


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


## Forja viva (docs/gdd/03b_diversion_y_ritmo.md §3b.2; inventory ui_forge_live, ui_icon_forge_traits): the art of the
## screen in assets/art/ui/forge/: iron_cold and iron_<colour> (64×64), hearth (64×64), strike_<kind> with anvil
## (80×96) and hammer (32), quench_<medium> (64×64), trait_<trait> (32×32; `small`: small/, 16×16). A visible
## placeholder of `size` and `color` until a file arrives (a trait without art, e.g. hard or soft, keeps it).
static func forge_art(id: String, size: Vector2i, color: Color, small: bool = false) -> Texture2D:
	return _art_or("%s/ui/forge/%s%s.png" % [ART_ROOT, "small/" if small else "", id], size, color)
