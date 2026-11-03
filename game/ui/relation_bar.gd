class_name RelationBar
extends Control
## A bipolar bar −100..+100 with the zero marked in the middle (docs/ui/mecanicas/_social.md, «barra bipolar»): the
## filled part goes from the zero to the value, gold-dark towards hostile and light gold towards friendly (both
## warm: the word next to it says good or bad, never the colour alone). Drawn by code: it is dynamic.

## Its colours: the theme type RelationBar (track, edge, zero, plus, minus) of greybox_theme.tres.

var value: int = 0:
	set(v):
		value = clampi(v, -100, 100)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(160, 7)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _c(n: StringName) -> Color:
	return SocialKit.theme_color(&"RelationBar", n)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-0.0)
	draw_rect(r, _c(&"edge"))
	var inner := r.grow(-1.0)
	draw_rect(inner, _c(&"track"))
	var mid := floorf(inner.position.x + inner.size.x / 2.0)
	var half := inner.size.x / 2.0
	var w := roundf(absf(value) / 100.0 * half)
	if value > 0:
		draw_rect(Rect2(mid + 1, inner.position.y + 1, w, inner.size.y - 2), _c(&"plus"))
	elif value < 0:
		draw_rect(Rect2(mid - w, inner.position.y + 1, w, inner.size.y - 2), _c(&"minus"))
	draw_rect(Rect2(mid, r.position.y, 1, r.size.y), _c(&"zero"))
