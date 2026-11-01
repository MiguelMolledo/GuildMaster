@tool
class_name KitWall
extends Node2D
## Interior kit piece (GDD 4.6.4): one wall segment standing on a back edge of a floor tile. side "ne" = the edge from
## the tile's top corner to its right corner (back-right wall), "nw" = from its left corner to its top corner
## (back-left wall). The origin is the tile's centre. With `door`, the segment has the door opening drawn in it.

@export_enum("ne", "nw") var side: String = "ne":
	set(v):
		side = v
		queue_redraw()
@export var height: float = 36.0:
	set(v):
		height = v
		queue_redraw()
@export var color: Color = Color(0.35, 0.29, 0.24):
	set(v):
		color = v
		queue_redraw()
@export var door: bool = false:
	set(v):
		door = v
		queue_redraw()
@export var door_color: Color = Color(0.78, 0.63, 0.31):
	set(v):
		door_color = v
		queue_redraw()


## The two ends of the segment on the floor.
func ends() -> PackedVector2Array:
	var top := Vector2(0, -Iso.TILE_H / 2.0)
	if side == "ne":
		return PackedVector2Array([top, Vector2(Iso.TILE_W / 2.0, 0)])
	return PackedVector2Array([Vector2(-Iso.TILE_W / 2.0, 0), top])


func _draw() -> void:
	var e := ends()
	var up := Vector2(0, -height)
	var c := color if side == "ne" else color.lightened(0.08)
	draw_colored_polygon(PackedVector2Array([e[0], e[1], e[1] + up, e[0] + up]), c)
	draw_line(e[0] + up, e[1] + up, c.lightened(0.25), 2.0)
	if door:
		var a := e[0].lerp(e[1], 0.2)
		var b := e[0].lerp(e[1], 0.8)
		var dh := Vector2(0, -height * 0.8)
		var hole := PackedVector2Array([a, b, b + dh, a + dh])
		draw_colored_polygon(hole, Color(0.08, 0.06, 0.05))
		draw_polyline(hole + PackedVector2Array([hole[0]]), door_color, 2.0)
