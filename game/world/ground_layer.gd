class_name GroundLayer
extends Node2D
## Ground of the town (H1): one flat 64×32 diamond per tile. A tile kind with art (assets/art/tiles/<kind>.png, see
## VisualPaths.tile) draws its texture; the rest keep their greybox colour (data/tiles.json "color") with a faint
## checker so the grid reads. Edges (data/view.json "ground_edges": kind -> the neighbour kinds it borders): where a
## tile of that kind touches one of them, assets/art/tiles/<kind>_edge_<ne|se|sw|nw>.png is drawn over that side (the
## river's bank, the bridge's curb). Map border (data/view.json "map_border"): a ring of `tiles` tiles around the map,
## outside the playable grid and purely visual: `ground` everywhere, except the kinds of `extend` that reach the map's
## edge (streets, the river), which carry on outwards; from `fade_from` tiles out it darkens towards `fade_to` (the
## background), so the town blends into the dark. WorldView puts the border's trees (border_cells). Drawn once;
## redrawn only when the map changes.
## Ground shader (data/view.json "ground_shader", ciudad-2d): when enabled, the tiles and corners are not drawn one by
## one; a quad behind this node (game/world/ground.gdshader) paints every pixel from a map of the tile kinds and an
## atlas of materials: world materials repeat every `period` tiles with no tile grid (assets/art/tiles/ground/, made
## by tools/art/suelos_materiales.py), soft kinds blend with ragged borders and paved ones get a curb. The edges (river
## bank, bridge curb) are still drawn on top. The data the tests read (texture_at, corner_count...) is the same.

const SIDES: Dictionary = {"ne": Vector2i(0, -1), "se": Vector2i(1, 0), "sw": Vector2i(0, 1), "nw": Vector2i(-1, 0)}

var _tiles: Array = []   # [[Vector2i, Color, Texture2D or null, Color modulate, kind]]
var _season: String = ""
var _base_tex: Dictionary = {}  # kind -> its plain texture (assets/art/tiles/<kind>.png), for the seasonal kinds
var _edges: Array = []   # [[Vector2i, Texture2D, Color modulate, kind]], drawn after every tile
var _border: Array = []  # [[Vector2i, kind, Color modulate, distance]] (border_cells)
var _corners: Array = []  # [[PackedVector2Array triangle, Texture2D or null, Color, Vector2 tile top-left]] (ground_corners)
var _quad: Polygon2D = null   # the shader ground (ground_shader), behind this node
var _shader_mat: ShaderMaterial = null
var _seasonal_mat: Dictionary = {}  # material index -> {season -> Vector4 atlas rect, "" -> base rect}
var _mat_rects: PackedVector4Array = PackedVector4Array()
var _decals: Array = []  # [[Vector2 world top-left, Texture2D, Color modulate]] (ground_shader.decals)

static var _atlas_cache: Dictionary = {}  # "ok" -> true, "tex", "rects": {entry -> Vector4}


## Rows of the map (rows[row][col]) + the catalog's tile kinds.
func build(rows: Array, catalog: Catalog) -> void:
	_tiles.clear()
	_edges.clear()
	_border.clear()
	_corners.clear()
	_decals.clear()
	var fades := {}  # Vector2i -> border fade factor (0 inside the map)
	var colour := {}   # kind -> greybox colour
	var tex := {}      # kind -> Texture2D
	var kind_by_char := {}
	for kind: String in catalog.tiles:
		var t: Dictionary = catalog.tiles[kind]
		kind_by_char[str(t.get("char", ""))] = kind
		colour[kind] = ViewConfig.color(str(t.get("color", "#ff00ff")))
		var tx := VisualPaths.tile(kind)
		if tx != null:
			tex[kind] = tx
	var h := rows.size()
	var w := str(rows[0]).length() if h > 0 else 0
	var bcfg: Dictionary = ViewConfig.value("map_border", {})
	var ring := int(bcfg.get("tiles", 0)) if h > 0 else 0
	var ground := str(bcfg.get("ground", "grass"))
	var extend: Array = bcfg.get("extend", [])
	var fade_from := float(bcfg.get("fade_from", 2))
	var fade_to := ViewConfig.color(str(bcfg.get("fade_to", "#2b221b")))
	# the kind of any tile, inside the map or in its border ("" = nothing there)
	var kind_at := func(c: int, r: int) -> String:
		if r >= 0 and r < h and c >= 0 and c < str(rows[r]).length():
			return str(kind_by_char.get(str(rows[r])[c], ""))
		var outside_c := c < 0 or c >= w
		var outside_r := r < 0 or r >= h
		if maxi(maxi(-c, c - (w - 1)), maxi(-r, r - (h - 1))) > ring:
			return ""
		if outside_c != outside_r:  # straight out of one edge: what reaches that edge carries on
			var edge_kind := str(kind_by_char.get(str(rows[clampi(r, 0, h - 1)])[clampi(c, 0, w - 1)], ""))
			if extend.has(edge_kind):
				return edge_kind
		return ground
	var borders: Dictionary = ViewConfig.value("ground_edges", {})
	var edge_tex := {}  # "kind|side" -> Texture2D
	for kind: String in borders:
		if kind.begins_with("_"):
			continue
		for side: String in SIDES:
			var tx := VisualPaths.tile("%s_edge_%s" % [kind, side])
			if tx != null:
				edge_tex["%s|%s" % [kind, side]] = tx
	for r: int in range(-ring, h + ring):
		for c: int in range(-ring, w + ring):
			var kind: String = kind_at.call(c, r)
			if kind == "":
				continue
			var d := maxi(maxi(-c, c - (w - 1)), maxi(-r, r - (h - 1)))  # tiles outside the map (<= 0 inside)
			var mod := Color.WHITE
			if d > 0:
				# a little jitter per tile so the rings do not read as stripes
				var jitter := float(absi((c * 73856093) ^ (r * 19349663)) % 100) / 100.0 - 0.5
				var k := clampf((float(d) + jitter * 0.9 - fade_from) / maxf(1.0, float(ring) - fade_from), 0.0, 1.0)
				var fk := k * k * (3.0 - 2.0 * k) * 0.92
				mod = Color.WHITE.lerp(fade_to, fk)
				fades[Vector2i(c, r)] = fk
				_border.append([Vector2i(c, r), kind, mod, d])
			var col: Color = colour.get(kind, Color.MAGENTA)
			if (c + r) % 2 == 1:
				col = col.darkened(0.05)
			_tiles.append([Vector2i(c, r), col, tex.get(kind, null), mod, kind])
			var against: Array = borders.get(kind, []) if borders.get(kind) is Array else []
			for side: String in SIDES:
				if against.is_empty():
					break
				var n: Vector2i = Vector2i(c, r) + SIDES[side]
				var other: String = kind_at.call(n.x, n.y)
				var key := "%s|%s" % [kind, side]
				if other != "" and against.has(other) and edge_tex.has(key):
					_edges.append([Vector2i(c, r), edge_tex[key], mod, kind])
	_build_corners(h, w, kind_at, colour, tex)
	_build_shader(h, w, ring, kind_at, colour, fades, fade_to, catalog)
	ViewConfig.info("GroundLayer", "build: %d tiles (%d in the border ring of %d), %d kinds with art (%s), %d edges, %d corners" % [
		_tiles.size(), _border.size(), ring, tex.size(), ", ".join(PackedStringArray(tex.keys())), _edges.size(),
		_corners.size()])
	var keep := _season
	_season = ""
	if keep != "":
		set_season(keep)
	queue_redraw()


## Corners (data/view.json "ground_corners"): on a tile of a kind of `kinds[over]` whose neighbours on two
## sides that meet at a corner are both of kind `over` (a street going round it, a diagonal street drawn as a stair
## of tiles), a triangle of `over` is painted over that corner, `fill` of the way along its two sides: the stair
## reads as one smooth diagonal ribbon. Purely visual (the grid and the paths do not change).
func _build_corners(h: int, w: int, kind_at: Callable, colour: Dictionary, tex: Dictionary) -> void:
	var cfg: Dictionary = ViewConfig.value("ground_corners", {})
	var kinds: Dictionary = cfg.get("kinds", {})
	if kinds.is_empty() or h == 0:
		return
	var f := float(cfg.get("fill", 0.75))
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	# the four corners of a tile's diamond, each between two sides: [corner, side a, side b, vertex a, vertex b]
	var top := Vector2(0, -hh)
	var right := Vector2(hw, 0)
	var bottom := Vector2(0, hh)
	var left := Vector2(-hw, 0)
	var corners := [[right, SIDES["ne"], SIDES["se"], top, bottom], [bottom, SIDES["se"], SIDES["sw"], right, left],
		[left, SIDES["sw"], SIDES["nw"], bottom, top], [top, SIDES["nw"], SIDES["ne"], left, right]]
	for r: int in h:
		for c: int in w:
			var here: String = kind_at.call(c, r)
			for over: String in kinds:
				if over.begins_with("_") or not (kinds[over] as Array).has(here):
					continue
				for k: Array in corners:
					var a: Vector2i = Vector2i(c, r) + (k[1] as Vector2i)
					var b: Vector2i = Vector2i(c, r) + (k[2] as Vector2i)
					if kind_at.call(a.x, a.y) != over or kind_at.call(b.x, b.y) != over:
						continue
					var p := Iso.tile_to_world(Vector2i(c, r))
					var corner: Vector2 = k[0]
					var tri := PackedVector2Array([p + corner, p + corner + ((k[3] as Vector2) - corner) * f,
						p + corner + ((k[4] as Vector2) - corner) * f])
					_corners.append([tri, tex.get(over, null), colour.get(over, Color.MAGENTA), p - Vector2(hw, hh)])


## How many corner pieces the ground draws (the tests count them).
func corner_count() -> int:
	return _corners.size()


## How many edge pieces the ground draws (the tests count them).
func edge_count() -> int:
	return _edges.size()


## The season the ground shows (Clock.season id): the kinds of data/view.json "seasonal_tiles".kinds draw
## assets/art/tiles/<kind>_<season>.png when it exists, else their plain texture. Redraws only when it changes.
func set_season(season: String) -> void:
	if season == _season:
		return
	_season = season
	var kinds: Array = (ViewConfig.value("seasonal_tiles", {}) as Dictionary).get("kinds", [])
	if kinds.is_empty():
		return
	var pick := {}
	for kind: Variant in kinds:
		var k := str(kind)
		if not _base_tex.has(k):
			_base_tex[k] = VisualPaths.tile(k)
		var seasonal := VisualPaths.tile("%s_%s" % [k, season])
		pick[k] = seasonal if seasonal != null else _base_tex[k]
	for t: Array in _tiles:
		if pick.has(t[4]):
			t[2] = pick[t[4]]
	_apply_season_to_shader()
	ViewConfig.info("GroundLayer", "season %s: %s" % [season, ", ".join(PackedStringArray(pick.keys()))])
	queue_redraw()


## The season the ground shows ("" before the first set_season).
func season() -> String:
	return _season


## The texture a tile of the map draws now (null = greybox colour), for the tests.
func texture_at(tile: Vector2i) -> Texture2D:
	for t: Array in _tiles:
		if t[0] == tile:
			return t[2]
	return null


## The tiles of the map border: [[Vector2i tile, kind, Color modulate, distance out of the map in tiles]].
func border_cells() -> Array:
	return _border


func _draw() -> void:
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	if shader_on():
		for d: Array in _decals:
			draw_texture(d[1], d[0], d[2])
		var skip: Array = (ViewConfig.value("ground_shader", {}) as Dictionary).get("skip_edges", [])
		for e: Array in _edges:
			if not skip.has(e[3]):
				draw_texture(e[1], Iso.tile_to_world(e[0]) - Vector2(hw, hh), e[2])
		return
	for t: Array in _tiles:
		var p := Iso.tile_to_world(t[0])
		var tx: Texture2D = t[2]
		var mod: Color = t[3]
		if tx != null:
			draw_texture(tx, p - Vector2(hw, hh), mod)
			continue
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -hh), p + Vector2(hw, 0), p + Vector2(0, hh),
			p + Vector2(-hw, 0)]), (t[1] as Color) * mod)
	for cn: Array in _corners:
		var tri: PackedVector2Array = cn[0]
		var tx: Texture2D = cn[1]
		if tx == null:
			draw_colored_polygon(tri, cn[2])
			continue
		var o: Vector2 = cn[3]
		var size := Vector2(tx.get_width(), tx.get_height())
		var uvs := PackedVector2Array()
		for q: Vector2 in tri:
			uvs.append((q - o) / size)
		draw_polygon(tri, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), uvs, tx)
	for e: Array in _edges:
		draw_texture(e[1], Iso.tile_to_world(e[0]) - Vector2(hw, hh), e[2])


## Whether the ground is painted by the shader quad (data/view.json "ground_shader".enabled and its art present).
func shader_on() -> bool:
	return _quad != null and _quad.visible


## How many detail decals (puddles, stones, weeds...) the shader ground scatters (the tests count them).
func decal_count() -> int:
	return _decals.size()


## The shader ground (ground_shader): the kind map, the material atlas and the quad. Off (the per-tile drawing) when
## the block is missing, disabled, or a world material's texture is not there.
func _build_shader(h: int, w: int, ring: int, kind_at: Callable, colour: Dictionary, fades: Dictionary,
		fade_to: Color, catalog: Catalog) -> void:
	var cfg: Dictionary = ViewConfig.value("ground_shader", {})
	if _quad != null:
		_quad.visible = false
	if not bool(cfg.get("enabled", false)) or h == 0:
		return
	var mats: Dictionary = cfg.get("materials", {})
	var kinds: Dictionary = cfg.get("kinds", {})
	var atlas := _atlas(mats, catalog)
	if atlas.is_empty():
		ViewConfig.info("GroundLayer", "shader off: a material texture is missing")
		return
	var rects: Dictionary = atlas["rects"]
	# materials: the configured ones first, then a flat one per unlisted tile kind (its greybox colour, hard)
	var names: Array = []
	for m: String in mats:
		if not m.begins_with("_"):
			names.append(m)
	var index := {}
	for i: int in names.size():
		index[names[i]] = i
	var kind_mat := {}
	for kind: String in catalog.tiles:
		if kinds.has(kind) and index.has(str(kinds[kind])):
			kind_mat[kind] = index[str(kinds[kind])]
		else:
			index["_flat_" + kind] = names.size()
			names.append("_flat_" + kind)
			kind_mat[kind] = index["_flat_" + kind]
	if names.size() > 32:
		push_warning("[GroundLayer] more than 32 ground materials: shader off")
		return
	_mat_rects = PackedVector4Array()
	var infos := PackedVector4Array()
	var extras := PackedVector4Array()
	var cols := PackedColorArray()
	_seasonal_mat.clear()
	for n: String in names:
		var m: Dictionary = mats.get(n, {})
		var rect := Vector4.ZERO
		var mode := 2.0
		var col: Color = colour.get(n.trim_prefix("_flat_"), Color.MAGENTA)
		if m.has("texture") and rects.has("tex:" + str(m["texture"])):
			rect = rects["tex:" + str(m["texture"])]
			mode = 0.0
		elif m.has("tile") and rects.has("tile:" + str(m["tile"])):
			rect = rects["tile:" + str(m["tile"])]
			mode = 1.0
			if bool(m.get("seasonal", false)):
				var by := {"": rect}
				for season: String in ["spring", "summer", "autumn", "winter"]:
					var key := "tile:%s_%s" % [m["tile"], season]
					if rects.has(key):
						by[season] = rects[key]
				_seasonal_mat[_mat_rects.size()] = by
		var hard := 1.0 if (bool(m.get("hard", false)) or mode == 2.0) else 0.0
		_mat_rects.append(rect)
		infos.append(Vector4(mode, float(m.get("priority", 0.0)), hard, float(m.get("curb", 0.0))))
		extras.append(Vector4(float(m.get("drift", 0.0)), 1.0 if bool(m.get("water", false)) else 0.0, 0, 0))
		cols.append(col)
	# the kind map: one texel per tile of the map and its border ring
	var size := Vector2i(w + 2 * ring, h + 2 * ring)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))  # r = 255: nothing
	var n_soft := 0
	for r: int in range(-ring, h + ring):
		for c: int in range(-ring, w + ring):
			var kind: String = kind_at.call(c, r)
			if kind == "":
				continue
			var mi: int = kind_mat.get(kind, 255)
			if infos[mi].z < 0.5:
				n_soft += 1
			img.set_pixel(c + ring, r + ring, Color(float(mi) / 255.0, float(fades.get(Vector2i(c, r), 0.0)), 0, 1))
	if _quad == null:
		_quad = Polygon2D.new()
		_quad.name = "ShaderGround"
		_quad.show_behind_parent = true
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = load("res://game/world/ground.gdshader")
		_quad.material = _shader_mat
		add_child(_quad)
	_quad.visible = true
	_quad.polygon = PackedVector2Array([Iso.tilef_to_world(Vector2(-ring - 0.5, -ring - 0.5)),
		Iso.tilef_to_world(Vector2(w + ring - 0.5, -ring - 0.5)),
		Iso.tilef_to_world(Vector2(w + ring - 0.5, h + ring - 0.5)),
		Iso.tilef_to_world(Vector2(-ring - 0.5, h + ring - 0.5))])
	_shader_mat.set_shader_parameter("kind_map", ImageTexture.create_from_image(img))
	_shader_mat.set_shader_parameter("map_origin", Vector2i(-ring, -ring))
	_shader_mat.set_shader_parameter("map_size", size)
	_shader_mat.set_shader_parameter("atlas", atlas["tex"])
	_shader_mat.set_shader_parameter("noise_tex", atlas["noise"])
	_shader_mat.set_shader_parameter("mat_rect", _mat_rects)
	_shader_mat.set_shader_parameter("mat_info", infos)
	_shader_mat.set_shader_parameter("mat_color", cols)
	_shader_mat.set_shader_parameter("mat_extra", extras)
	var bank := PackedColorArray()
	for c: Variant in cfg.get("bank_colors", ["#5d4330", "#4a3424", "#22303a", "#7fb0c4"]):
		bank.append(ViewConfig.color(str(c)))
	_shader_mat.set_shader_parameter("bank_colors", bank)
	_shader_mat.set_shader_parameter("fade_to", fade_to)
	_shader_mat.set_shader_parameter("edge_noise", float(cfg.get("edge_noise", 0.16)))
	_shader_mat.set_shader_parameter("noise_tiles", float(cfg.get("noise_tiles", 3.0)))
	_apply_season_to_shader()
	_build_decals(h, w, kind_at, cfg.get("decals", {}))
	ViewConfig.info("GroundLayer", "shader ground: %d materials (%s), %d soft tiles, %d decals, map %s" % [
		names.size(), ", ".join(PackedStringArray(names)), n_soft, _decals.size(), size])


## The material atlas (built once): every world texture of ground_shader.materials, every tile texture (and the
## seasonal variants) stacked in one image, and the edge noise. {} if a world texture is missing.
func _atlas(mats: Dictionary, catalog: Catalog) -> Dictionary:
	if bool(_atlas_cache.get("ok", false)):
		return _atlas_cache
	var entries := {}  # key -> Image
	for n: String in mats:
		if n.begins_with("_"):
			continue
		var m: Dictionary = mats[n]
		if m.has("texture"):
			var p := "%s/tiles/%s.png" % [VisualPaths.ART_ROOT, m["texture"]]
			if not ResourceLoader.exists(p):
				return {}
			entries["tex:" + str(m["texture"])] = (load(p) as Texture2D).get_image()
		elif m.has("tile"):
			var names: Array = [str(m["tile"])]
			if bool(m.get("seasonal", false)):
				for season: String in ["spring", "summer", "autumn", "winter"]:
					names.append("%s_%s" % [m["tile"], season])
			for tn: String in names:
				var tx := VisualPaths.tile(tn)
				if tx != null:
					entries["tile:" + tn] = tx.get_image()
	var width := 1
	var height := 0
	for k: String in entries:
		var im: Image = entries[k]
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		width = maxi(width, im.get_width())
		height += im.get_height()
	var atlas := Image.create(width, maxi(1, height), false, Image.FORMAT_RGBA8)
	var rects := {}
	var y := 0
	for k: String in entries:
		var im: Image = entries[k]
		atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(0, y))
		rects[k] = Vector4(0, y, im.get_width(), im.get_height())
		y += im.get_height()
	var noise_p := "%s/tiles/ground/noise.png" % VisualPaths.ART_ROOT
	if not ResourceLoader.exists(noise_p):
		return {}
	_atlas_cache = {"ok": true, "tex": ImageTexture.create_from_image(atlas), "rects": rects,
		"noise": load(noise_p) as Texture2D}
	ViewConfig.info("GroundLayer", "material atlas %dx%d (%d entries)" % [width, height, entries.size()])
	return _atlas_cache


## The field's texture follows the season (seasonal_tiles), in the shader too.
func _apply_season_to_shader() -> void:
	if _shader_mat == null or _seasonal_mat.is_empty():
		return
	for mi: int in _seasonal_mat:
		var by: Dictionary = _seasonal_mat[mi]
		_mat_rects[mi] = by.get(_season, by[""])
	_shader_mat.set_shader_parameter("mat_rect", _mat_rects)


## Loose detail on the ground (ground_shader.decals: kind -> [{art, chance}]): puddles, stones, weeds, ruts. A tile
## of that kind gets one with that chance, picked by a hash of the tile (the same every run), at a small offset
## inside the tile. Purely visual.
func _build_decals(h: int, w: int, kind_at: Callable, cfg: Dictionary) -> void:
	for r: int in h:
		for c: int in w:
			var kind: String = kind_at.call(c, r)
			var list: Array = cfg.get(kind, [])
			if list.is_empty():
				continue
			var hsh := absi((c * 73856093) ^ (r * 19349663) ^ 83492791)
			var roll := float(hsh % 1000) / 1000.0
			var acc := 0.0
			for d: Dictionary in list:
				acc += float(d.get("chance", 0.0))
				if roll >= acc:
					continue
				var tx := VisualPaths.tile("ground/decals/" + str(d.get("art", "")))
				if tx == null:
					break
				var off := Vector2(float((hsh / 1000) % 17) - 8.0, float((hsh / 17000) % 9) - 4.0)
				var p := Iso.tile_to_world(Vector2i(c, r)) + off - Vector2(tx.get_width(), tx.get_height()) / 2.0
				_decals.append([p.round(), tx, Color.WHITE])
				break
