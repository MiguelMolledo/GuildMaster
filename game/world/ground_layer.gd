class_name GroundLayer
extends Node2D
## Greybox ground of the town (H1): one flat 64×32 diamond per tile, coloured by its kind (data/tiles.json "color"),
## with a faint checker so the grid reads. Drawn once; redrawn only when the map changes.

var _tiles: Array = []  # [[Vector2i, Color]]


## Rows of the map (rows[row][col]) + the catalog's tile kinds.
func build(rows: Array, catalog: Catalog) -> void:
	_tiles.clear()
	var by_char := {}
	for kind: String in catalog.tiles:
		var t: Dictionary = catalog.tiles[kind]
		by_char[str(t.get("char", ""))] = ViewConfig.color(str(t.get("color", "#ff00ff")))
	for r: int in rows.size():
		var row := str(rows[r])
		for c: int in row.length():
			var col: Color = by_char.get(row[c], Color.MAGENTA)
			if (c + r) % 2 == 1:
				col = col.darkened(0.05)
			_tiles.append([Vector2i(c, r), col])
	queue_redraw()


func _draw() -> void:
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	for t: Array in _tiles:
		var p := Iso.tile_to_world(t[0])
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -hh), p + Vector2(hw, 0), p + Vector2(0, hh),
			p + Vector2(-hw, 0)]), t[1])
