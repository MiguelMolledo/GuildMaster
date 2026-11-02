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

const SIDES: Dictionary = {"ne": Vector2i(0, -1), "se": Vector2i(1, 0), "sw": Vector2i(0, 1), "nw": Vector2i(-1, 0)}

var _tiles: Array = []   # [[Vector2i, Color, Texture2D or null, Color modulate, kind]]
var _season: String = ""
var _base_tex: Dictionary = {}  # kind -> its plain texture (assets/art/tiles/<kind>.png), for the seasonal kinds
var _edges: Array = []   # [[Vector2i, Texture2D, Color modulate]], drawn after every tile
var _border: Array = []  # [[Vector2i, kind, Color modulate, distance]] (border_cells)


## Rows of the map (rows[row][col]) + the catalog's tile kinds.
func build(rows: Array, catalog: Catalog) -> void:
	_tiles.clear()
	_edges.clear()
	_border.clear()
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
				mod = Color.WHITE.lerp(fade_to, k * k * (3.0 - 2.0 * k) * 0.92)
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
					_edges.append([Vector2i(c, r), edge_tex[key], mod])
	ViewConfig.info("GroundLayer", "build: %d tiles (%d in the border ring of %d), %d kinds with art (%s), %d edges" % [
		_tiles.size(), _border.size(), ring, tex.size(), ", ".join(PackedStringArray(tex.keys())), _edges.size()])
	var keep := _season
	_season = ""
	if keep != "":
		set_season(keep)
	queue_redraw()


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
	for t: Array in _tiles:
		var p := Iso.tile_to_world(t[0])
		var tx: Texture2D = t[2]
		var mod: Color = t[3]
		if tx != null:
			draw_texture(tx, p - Vector2(hw, hh), mod)
			continue
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -hh), p + Vector2(hw, 0), p + Vector2(0, hh),
			p + Vector2(-hw, 0)]), (t[1] as Color) * mod)
	for e: Array in _edges:
		draw_texture(e[1], Iso.tile_to_world(e[0]) - Vector2(hw, hh), e[2])
