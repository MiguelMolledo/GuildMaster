class_name GroundLayer
extends Node2D
## Ground of the town (H1): one flat 64×32 diamond per tile. A tile kind with art (assets/art/tiles/<kind>.png, see
## VisualPaths.tile) draws its texture; the rest keep their greybox colour (data/tiles.json "color") with a faint
## checker so the grid reads. Drawn once; redrawn only when the map changes.

var _tiles: Array = []  # [[Vector2i, Color, Texture2D or null]]


## Rows of the map (rows[row][col]) + the catalog's tile kinds.
func build(rows: Array, catalog: Catalog) -> void:
	_tiles.clear()
	var by_char := {}
	var tex_by_char := {}
	for kind: String in catalog.tiles:
		var t: Dictionary = catalog.tiles[kind]
		var ch := str(t.get("char", ""))
		by_char[ch] = ViewConfig.color(str(t.get("color", "#ff00ff")))
		var tex := VisualPaths.tile(kind)
		if tex != null:
			tex_by_char[ch] = tex
	for r: int in rows.size():
		var row := str(rows[r])
		for c: int in row.length():
			var col: Color = by_char.get(row[c], Color.MAGENTA)
			if (c + r) % 2 == 1:
				col = col.darkened(0.05)
			_tiles.append([Vector2i(c, r), col, tex_by_char.get(row[c], null)])
	ViewConfig.info("GroundLayer", "build: %d tiles, %d kinds with art (%s)" % [_tiles.size(), tex_by_char.size(),
		", ".join(PackedStringArray(tex_by_char.keys()))])
	queue_redraw()


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
