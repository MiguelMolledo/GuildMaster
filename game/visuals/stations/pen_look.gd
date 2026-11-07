class_name PenLook
extends Node2D
## H12 Patrón (docs/gdd/04d_otras_clases.md 4.22.4.2, 4.22.4.8): the look of the farm's pen. A wooden fence around
## the pen's ground and its animals (greybox figures: sheep white and woolly, pigs pink), as many as the storage holds,
## in fixed spots (the winter feed left goes in the station's caption, InteriorStage). InteriorStage feeds it
## Herds.view every half second (show_herd). Greybox until the animals of the PixelLab cycle (4.22.9 #4).

const W: float = 150.0
const H: float = 75.0

var herd: Dictionary = {}     # animal -> count
var capacity: int = 8
var feed_days: int = -1       # winter feed left in days (-1: they eat nothing in winter)
var need_today: int = 0


func show_herd(v: Dictionary) -> void:
	var h: Dictionary = v.get("herd", {})
	var fd := int(v.get("winter_feed_days", -1))
	var cap := int(v.get("capacity", 8))
	if h == herd and fd == feed_days and cap == capacity:
		return
	herd = h.duplicate()
	feed_days = fd
	capacity = cap
	queue_redraw()


func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * W / 2.0, (x + y) * H / 2.0) * 0.5


func _draw() -> void:
	var corners := [_iso(-1, -1), _iso(1, -1), _iso(1, 1), _iso(-1, 1)]
	draw_colored_polygon(PackedVector2Array(corners), Color(0.42, 0.36, 0.22, 0.55))
	var wood := Color(0.45, 0.3, 0.16)
	for i: int in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for k: int in 5:
			var p := a.lerp(b, k / 4.0)
			draw_line(p, p + Vector2(0, -12), wood.darkened(0.2), 2.0)
		draw_line(a + Vector2(0, -9), b + Vector2(0, -9), wood, 2.0)
		draw_line(a + Vector2(0, -4), b + Vector2(0, -4), wood, 2.0)
	var spots := [Vector2(-0.5, -0.5), Vector2(0.2, -0.6), Vector2(0.6, 0.0), Vector2(-0.6, 0.2), Vector2(0.0, 0.0),
		Vector2(0.3, 0.55), Vector2(-0.2, 0.6), Vector2(0.65, -0.55), Vector2(-0.65, -0.1), Vector2(0.1, 0.3),
		Vector2(-0.35, 0.35), Vector2(0.45, 0.3)]
	var i := 0
	for a: String in ["sheep", "pig"]:
		for n: int in int(herd.get(a, 0)):
			if i >= spots.size():
				break
			var s: Vector2 = spots[i]
			_animal(_iso(s.x, s.y), a)
			i += 1


func _animal(at: Vector2, kind: String) -> void:
	var body := Color(0.93, 0.92, 0.86) if kind == "sheep" else Color(0.93, 0.66, 0.66)
	var head := Color(0.25, 0.22, 0.2) if kind == "sheep" else Color(0.88, 0.55, 0.56)
	draw_circle(at + Vector2(0, 2), 6.0, Color(0, 0, 0, 0.25))
	draw_circle(at + Vector2(-2, -4), 5.5, body)
	draw_circle(at + Vector2(3, -4), 5.0, body)
	if kind == "sheep":
		draw_circle(at + Vector2(-1, -8), 3.5, body)
	draw_circle(at + Vector2(7, -6), 3.0, head)
	draw_line(at + Vector2(-3, -1), at + Vector2(-3, 2), head.darkened(0.3), 1.5)
	draw_line(at + Vector2(4, -1), at + Vector2(4, 2), head.darkened(0.3), 1.5)
