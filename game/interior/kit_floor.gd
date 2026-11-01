@tool
class_name KitFloor
extends Node2D
## Interior kit piece (GDD 4.6.4): one floor tile, a flat 64×32 diamond. Same piece for every interior (GreyboxKit).

@export var color: Color = Color(0.54, 0.46, 0.38):
	set(v):
		color = v
		queue_redraw()


func _draw() -> void:
	var d := PackedVector2Array([Vector2(0, -Iso.TILE_H / 2.0), Vector2(Iso.TILE_W / 2.0, 0), Vector2(0, Iso.TILE_H / 2.0),
		Vector2(-Iso.TILE_W / 2.0, 0)])
	draw_colored_polygon(d, color)
	draw_polyline(d + PackedVector2Array([d[0]]), color.darkened(0.12), 1.0)
