class_name TargetMarker
extends Node2D
## A brief diamond on the tile a move order points at: feedback of the click, nothing more.

var _left: float = 0.0
var _seconds: float = 1.0


func show_at(tile: Vector2i, seconds: float) -> void:
	position = Iso.tile_to_world(tile)
	_seconds = maxf(0.1, seconds)
	_left = _seconds
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
	queue_redraw()


func _draw() -> void:
	var a := clampf(_left / _seconds, 0.0, 1.0)
	var d := PackedVector2Array([Vector2(0, -14), Vector2(28, 0), Vector2(0, 14), Vector2(-28, 0), Vector2(0, -14)])
	draw_polyline(d, Color(1.0, 0.85, 0.3, a), 2.0)
