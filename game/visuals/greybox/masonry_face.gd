@tool
class_name MasonryFace
extends Node2D
## One tile of a GreyboxMasonry: the stones on the left (south-west) or right (south-east) face of a building block,
## drawn from the tile's centre (+1 px). Staggered rows; each stone a shade lighter or darker so the wall reads.

var side: String = "left"
var index: int = 0       # position along the face (staggers the joints between tiles)
var height: float = 40.0
var stone_color: Color = Color(0.784, 0.725, 0.596)
var mortar_color: Color = Color(0.353, 0.306, 0.251)
var course: float = 8.0


func _draw() -> void:
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	var a := Vector2(-hw, -1.0) if side == "left" else Vector2(0, hh - 1.0)   # the face's bottom edge, a → b
	var b := Vector2(0, hh - 1.0) if side == "left" else Vector2(hw, -1.0)
	var shade := 0.12 if side == "left" else 0.3
	var base := stone_color.darkened(shade)
	var up := Vector2(0, -height)
	draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), mortar_color)
	var rows := maxi(1, int(ceil(height / course)))
	var per_row := 2   # stones per tile and row
	for k: int in rows:
		var v0 := k * course
		var v1 := minf(height, (k + 1) * course)
		var stagger := 0.5 if (k + index) % 2 == 1 else 0.0
		for s: int in range(-1, per_row):
			var u0 := clampf((float(s) + stagger) / per_row, 0.0, 1.0)
			var u1 := clampf((float(s) + 1.0 + stagger) / per_row, 0.0, 1.0)
			if u1 - u0 < 0.05:
				continue
			var pad := 1.0 / (hw)   # ~1 px of mortar between stones
			var p0 := a.lerp(b, u0 + (pad if u0 > 0.0 else 0.0))
			var p1 := a.lerp(b, u1 - (pad if u1 < 1.0 else 0.0))
			var tone := 0.06 if (k * 3 + s + index) % 3 == 0 else (-0.05 if (k + s + index) % 2 == 0 else 0.0)
			var c := base.lightened(tone) if tone > 0.0 else base.darkened(-tone)
			draw_colored_polygon(PackedVector2Array([p0 + Vector2(0, -v0 - 1.0), p1 + Vector2(0, -v0 - 1.0),
				p1 + Vector2(0, -v1), p0 + Vector2(0, -v1)]), c)
	# coping: a light band along the top
	draw_line(a + up, b + up, stone_color.lightened(0.2), 2.0)
