class_name RelationBar
extends Control
## A bipolar bar −100..+100 with the zero marked in the middle (docs/ui/mecanicas/_social.md, «barra bipolar»): the
## filled part goes from the zero to the value, gold-dark towards hostile and light gold towards friendly (both
## warm: the word next to it says good or bad, never the colour alone). Drawn by code: it is dynamic.

const TRACK: Color = Color(0.101961, 0.0705882, 0.0352941)   # hueco
const EDGE: Color = Color(0.243137, 0.156863, 0.0784314)     # madera_oscura
const ZERO: Color = Color(0.784314, 0.658824, 0.305882)      # oro
const PLUS: Color = Color(0.94902, 0.847059, 0.501961)       # oro_claro
const MINUS: Color = Color(0.784314, 0.313725, 0.313725)     # negativo

var value: int = 0:
	set(v):
		value = clampi(v, -100, 100)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(160, 7)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-0.0)
	draw_rect(r, EDGE)
	var inner := r.grow(-1.0)
	draw_rect(inner, TRACK)
	var mid := floorf(inner.position.x + inner.size.x / 2.0)
	var half := inner.size.x / 2.0
	var w := roundf(absf(value) / 100.0 * half)
	if value > 0:
		draw_rect(Rect2(mid + 1, inner.position.y + 1, w, inner.size.y - 2), PLUS)
	elif value < 0:
		draw_rect(Rect2(mid - w, inner.position.y + 1, w, inner.size.y - 2), MINUS)
	draw_rect(Rect2(mid, r.position.y, 1, r.size.y), ZERO)
