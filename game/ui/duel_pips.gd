class_name DuelPips
extends Control
## A row of pips for the duel screen (docs/ui/mecanicas/combate.md §3): the touches given (gold) or the breath left
## (blue), `value` of `max_value` filled. Drawn by code: it changes every lance. `mirror` fills from the right (the
## rival's column). View only.

@export var max_value: int = 3:
	set(v):
		max_value = maxi(v, 0)
		_resize()
@export var value: int = 0:
	set(v):
		value = v
		queue_redraw()
@export var fill: Color = Color(0.85, 0.68, 0.24)
@export var empty: Color = Color(0.18, 0.14, 0.11)
@export var edge: Color = Color(0.07, 0.05, 0.04)
@export var pip: int = 8
@export var gap: int = 2
@export var mirror: bool = false
## A 16 px icon before the pips (after them when mirrored): VisualPaths.duel_icon("touch" / "breath", true).
var icon: Texture2D = null:
	set(v):
		icon = v
		_resize()


func _ready() -> void:
	_resize()


func _resize() -> void:
	var w := maxi(max_value, 1) * (pip + gap) - gap
	if icon != null:
		w += int(icon.get_width()) + gap * 2
	custom_minimum_size = Vector2(w, maxi(pip, int(icon.get_height())) if icon != null else pip)
	queue_redraw()


func _draw() -> void:
	var x0 := 0
	var y0 := 0
	if icon != null:
		var iw := int(icon.get_width())
		var ih := int(icon.get_height())
		y0 = maxi(0, (ih - pip) / 2)
		var pips_w := maxi(max_value, 1) * (pip + gap) - gap
		draw_texture(icon, Vector2(pips_w + gap * 2 if mirror else 0, 0))
		if not mirror:
			x0 = iw + gap * 2
		if ih < pip:
			y0 = 0
	for i: int in max_value:
		var x := x0 + ((max_value - 1 - i) * (pip + gap) if mirror else i * (pip + gap))
		var r := Rect2(x, y0, pip, pip)
		draw_rect(r, edge)
		draw_rect(r.grow(-1), fill if i < value else empty)
