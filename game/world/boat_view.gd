@tool
class_name BoatView
extends Node2D
## Greybox of a moored boat or a rowboat (data/maps "boats", tools/city/organic.py): a low hull over its footprint
## on the water and, on a ship, a mast with a furled sail. Purely cosmetic: the sim never reads the boats. Its origin
## is the footprint's centre (the scene's Feet). Delete it when the boat's sprite arrives.

@export var footprint: Vector2i = Vector2i(4, 2):
	set(v):
		footprint = Vector2i(maxi(1, v.x), maxi(1, v.y))
		queue_redraw()
@export var color: Color = Color(0.42, 0.29, 0.16):
	set(v):
		color = v
		queue_redraw()
@export var height: float = 10.0:
	set(v):
		height = v
		queue_redraw()
@export var mast: bool = true:
	set(v):
		mast = v
		queue_redraw()


## The game's footprint of this boat (the decor item's size).
func apply_footprint(f: Vector2i) -> void:
	footprint = f


func _draw() -> void:
	# the hull: the footprint's diamond shrunk a little, raised by `height`, with pointed ends along its long side
	var half := Vector2(footprint.x, footprint.y) / 2.0 - Vector2(0.15, 0.15)
	var long_x := footprint.x >= footprint.y
	var pts: Array[Vector2] = []
	var tip := 0.45
	if long_x:
		pts = [Vector2(-half.x - tip, 0), Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x + tip, 0),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	else:
		pts = [Vector2(0, -half.y - tip), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(0, half.y + tip),
			Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]
	var base := PackedVector2Array()
	var deck := PackedVector2Array()
	for p: Vector2 in pts:
		var w := Iso.tilef_to_world(p) - Iso.tilef_to_world(Vector2.ZERO)
		base.append(w)
		deck.append(w + Vector2(0, -height))
	for i: int in base.size():
		var a := base[i]
		var b := base[(i + 1) % base.size()]
		draw_colored_polygon(PackedVector2Array([a, b, deck[(i + 1) % base.size()], deck[i]]), color.darkened(0.3))
	draw_colored_polygon(deck, color.lightened(0.12))
	if mast and footprint.x * footprint.y >= 4:
		var top := Vector2(0, -height - 46)
		draw_line(Vector2(0, -height), top, Color(0.25, 0.17, 0.1), 2.0)
		draw_colored_polygon(PackedVector2Array([top + Vector2(2, 4), top + Vector2(20, 26), top + Vector2(2, 30)]),
			Color(0.9, 0.86, 0.76))
