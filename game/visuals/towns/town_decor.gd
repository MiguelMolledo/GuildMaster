@tool
class_name TownDecor
extends Node2D
## Hand-placed decoration of a town: game/visuals/towns/<map id>.tscn (docs/protocolos/editar-a-mano.md). Each child
## is a prop scene (game/visuals/props/barrel.tscn, bench, cart...) placed in world pixels: drag it in the editor. In
## the game WorldView moves the children into its objects layer, so they sort with the walkers; they are purely
## visual (they do not block the way): put them on grass or against walls, not in the street.
## In the editor this node draws the map underneath (ground by tile kind, data/tiles.json colours) so you can see
## where things go; nothing of it is drawn in the game.

@export var map_id: String = "town_e":
	set(v):
		map_id = v
		_preview.clear()
		queue_redraw()
@export var show_map: bool = true:
	set(v):
		show_map = v
		queue_redraw()

var _preview: Array = []  # [[Vector2i, Color]]


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_map:
		return
	if _preview.is_empty():
		_build_preview()
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	for t: Array in _preview:
		var p := Iso.tile_to_world(t[0])
		var d := PackedVector2Array([p + Vector2(0, -hh), p + Vector2(hw, 0), p + Vector2(0, hh), p + Vector2(-hw, 0)])
		draw_colored_polygon(d, t[1])
		draw_polyline(d + PackedVector2Array([d[0]]), Color(0, 0, 0, 0.15), 1.0)


func _build_preview() -> void:
	var cat := Catalog.load_from("res://data")
	var by_char := {}
	for kind: String in cat.tiles:
		var t: Dictionary = cat.tiles[kind]
		by_char[str(t.get("char", ""))] = Color.from_string(str(t.get("color", "#ff00ff")), Color.MAGENTA)
	var rows: Array = cat.maps().get(map_id, {}).get("rows", [])
	for r: int in rows.size():
		var row := str(rows[r])
		for c: int in row.length():
			var col: Color = by_char.get(row[c], Color.MAGENTA)
			_preview.append([Vector2i(c, r), Color(col, 0.55)])
