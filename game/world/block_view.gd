class_name BlockView
extends Node2D
## Greybox volume of one blocked tile (a building block or a tree), so the street reads (H1). Its origin is the
## centre of its tile, which is what the Y-sort of the objects layer compares with the walkers.

var shape: String = "block"
var height: float = 40.0
var color: Color = Color.GRAY


func _draw() -> void:
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	var up := Vector2(0, -height)
	if shape == "tree":
		draw_rect(Rect2(-2, -10, 4, 10), Color(0.30, 0.20, 0.12))
		draw_circle(Vector2(0, -height * 0.6), 12.0, color)
		draw_circle(Vector2(-3, -height * 0.6 - 4), 6.0, color.lightened(0.12))
		return
	var top := Vector2(0, -hh)
	var right := Vector2(hw, 0)
	var bottom := Vector2(0, hh)
	var left := Vector2(-hw, 0)
	draw_colored_polygon(PackedVector2Array([left, bottom, bottom + up, left + up]), color.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([bottom, right, right + up, bottom + up]), color.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([top + up, right + up, bottom + up, left + up]), color.lightened(0.15))
