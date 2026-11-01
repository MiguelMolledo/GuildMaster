class_name SunMoon
extends Control
## HUD clock icon (GDD 4.15): a sun for dawn, day and dusk (warmer at the edges of the day), a moon at night.

var phase: String = "day":
	set(v):
		if v != phase:
			phase = v
			queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 3.0
	if phase == "night":
		draw_circle(c, r, Color(0.92, 0.92, 0.80))
		draw_circle(c + Vector2(r * 0.45, -r * 0.3), r * 0.85, Color(0.13, 0.11, 0.10))
		return
	var col := Color(1.0, 0.85, 0.3) if phase == "day" else Color(1.0, 0.6, 0.3)
	for i: int in 8:
		var a := TAU * i / 8.0
		draw_line(c + Vector2.from_angle(a) * (r * 0.75), c + Vector2.from_angle(a) * (r + 2.0), col, 2.0)
	draw_circle(c, r * 0.6, col)
