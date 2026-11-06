class_name InteriorWall
extends Node2D
## One wall segment of an interior built from data (docs/gdd/04g_interiores.md 4.6.5.3): an inner wall or door
## between two rooms, which turns almost transparent (with its outline) while the person selected, or the mouse, is
## in the room behind it; or a low front wall (a plinth). The node stands where it sorts with the people (between the
## tile behind and the tile in front); the texture is drawn from the tile's centre (`tile_origin`, relative), like
## KitWall: 32 px wide, its bottom edge on the tile's edge.

@export_enum("ne", "nw", "sw", "se") var side: String = "nw"
@export var kind: String = "inner"      # inner | door | low
@export var texture: Texture2D
@export var height: float = 64.0         # the face's height (the texture is 16 + height)
var behind: String = ""                  # the room behind it ("" for a low front wall)
var front: String = ""                   # the room in front
var level: int = 0
var tile_origin: Vector2 = Vector2.ZERO  # the tile's centre, relative to this node
var faded: bool = false:
	set(v):
		if v == faded:
			return
		faded = v
		queue_redraw()

const FADED_ALPHA: float = 0.25
const OUTLINE: Color = Color(0.95, 0.85, 0.55, 0.9)


## The two ends of the segment on the floor, relative to the tile's centre.
func ends() -> PackedVector2Array:
	match side:
		"ne":
			return PackedVector2Array([Vector2(0, -16), Vector2(32, 0)])
		"nw":
			return PackedVector2Array([Vector2(-32, 0), Vector2(0, -16)])
		"sw":
			return PackedVector2Array([Vector2(-32, 0), Vector2(0, 16)])
	return PackedVector2Array([Vector2(0, 16), Vector2(32, 0)])


func _draw() -> void:
	var e := ends()
	var left := minf(e[0].x, e[1].x)
	var top := minf(e[0].y, e[1].y) - height
	if texture != null:
		draw_texture_rect(texture, Rect2(tile_origin + Vector2(left, top), Vector2(32, 16 + height)), false,
			Color(1, 1, 1, FADED_ALPHA if faded else 1.0))
	if faded:
		var up := Vector2(0, -height)
		var poly := PackedVector2Array([e[0], e[1], e[1] + up, e[0] + up, e[0]])
		for i: int in poly.size():
			poly[i] += tile_origin
		draw_polyline(poly, OUTLINE, 1.0)
