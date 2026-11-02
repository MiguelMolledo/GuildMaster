class_name GroundLayer
extends Node2D
## Ground of the town (H1): one flat 64×32 diamond per tile. A tile kind with art (assets/art/tiles/<kind>.png, see
## VisualPaths.tile) draws its texture; the rest keep their greybox colour (data/tiles.json "color") with a faint
## checker so the grid reads. Edges (data/view.json "ground_edges": kind -> the neighbour kinds it borders): where a
## tile of that kind touches one of them, assets/art/tiles/<kind>_edge_<ne|se|sw|nw>.png is drawn over that side (the
## river's bank, the bridge's curb). Drawn once; redrawn only when the map changes.

const SIDES: Dictionary = {"ne": Vector2i(0, -1), "se": Vector2i(1, 0), "sw": Vector2i(0, 1), "nw": Vector2i(-1, 0)}

var _tiles: Array = []  # [[Vector2i, Color, Texture2D or null]]
var _edges: Array = []  # [[Vector2i, Texture2D]], drawn after every tile


## Rows of the map (rows[row][col]) + the catalog's tile kinds.
func build(rows: Array, catalog: Catalog) -> void:
	_tiles.clear()
	_edges.clear()
	var by_char := {}
	var tex_by_char := {}
	var kind_by_char := {}
	for kind: String in catalog.tiles:
		var t: Dictionary = catalog.tiles[kind]
		var ch := str(t.get("char", ""))
		by_char[ch] = ViewConfig.color(str(t.get("color", "#ff00ff")))
		kind_by_char[ch] = kind
		var tex := VisualPaths.tile(kind)
		if tex != null:
			tex_by_char[ch] = tex
	var borders: Dictionary = ViewConfig.value("ground_edges", {})
	var edge_tex := {}  # "kind|side" -> Texture2D
	for kind: String in borders:
		if kind.begins_with("_"):
			continue
		for side: String in SIDES:
			var tex := VisualPaths.tile("%s_edge_%s" % [kind, side])
			if tex != null:
				edge_tex["%s|%s" % [kind, side]] = tex
	for r: int in rows.size():
		var row := str(rows[r])
		for c: int in row.length():
			var col: Color = by_char.get(row[c], Color.MAGENTA)
			if (c + r) % 2 == 1:
				col = col.darkened(0.05)
			_tiles.append([Vector2i(c, r), col, tex_by_char.get(row[c], null)])
			var kind := str(kind_by_char.get(row[c], ""))
			var against: Array = borders.get(kind, []) if borders.get(kind) is Array else []
			if against.is_empty():
				continue
			for side: String in SIDES:
				var n: Vector2i = Vector2i(c, r) + SIDES[side]
				if n.y < 0 or n.y >= rows.size() or n.x < 0 or n.x >= str(rows[n.y]).length():
					continue
				var other := str(kind_by_char.get(str(rows[n.y])[n.x], ""))
				var key := "%s|%s" % [kind, side]
				if against.has(other) and edge_tex.has(key):
					_edges.append([Vector2i(c, r), edge_tex[key]])
	ViewConfig.info("GroundLayer", "build: %d tiles, %d kinds with art (%s), %d edges" % [_tiles.size(),
		tex_by_char.size(), ", ".join(PackedStringArray(tex_by_char.keys())), _edges.size()])
	queue_redraw()


## How many edge pieces the ground draws (the tests count them).
func edge_count() -> int:
	return _edges.size()


func _draw() -> void:
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	for t: Array in _tiles:
		var p := Iso.tile_to_world(t[0])
		var tex: Texture2D = t[2]
		if tex != null:
			draw_texture(tex, p - Vector2(hw, hh))
			continue
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -hh), p + Vector2(hw, 0), p + Vector2(0, hh),
			p + Vector2(-hw, 0)]), t[1])
	for e: Array in _edges:
		draw_texture(e[1], Iso.tile_to_world(e[0]) - Vector2(hw, hh))
