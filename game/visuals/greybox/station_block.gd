@tool
class_name StationBlock
extends Node2D
## Greybox of one station of an interior (H2): a low block (3/4 of a tile) in the station's colour. While the
## master-touch window is open the StationView that wraps it sets `highlight` (0-1) and it blinks towards
## `highlight_color`. Delete it when the station's sprite arrives (the StationView then blinks the sprite).

@export var color: Color = Color(0.478431, 0.415686, 0.313725):
	set(v):
		color = v
		queue_redraw()
@export var height: float = 20.0:
	set(v):
		height = v
		queue_redraw()
var highlight: float = 0.0:
	set(v):
		if v != highlight:
			highlight = v
			queue_redraw()
var highlight_color: Color = Color(1.0, 0.94, 0.63)


func _draw() -> void:
	var hw := Iso.TILE_W / 2.0 * 0.75
	var hh := Iso.TILE_H / 2.0 * 0.75
	var up := Vector2(0, -height)
	var top := Vector2(0, -hh)
	var right := Vector2(hw, 0)
	var bottom := Vector2(0, hh)
	var left := Vector2(-hw, 0)
	var c := color.lerp(highlight_color, highlight) if highlight > 0.0 else color
	draw_colored_polygon(PackedVector2Array([left, bottom, bottom + up, left + up]), c.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([bottom, right, right + up, bottom + up]), c.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([top + up, right + up, bottom + up, left + up]), c.lightened(0.15))
