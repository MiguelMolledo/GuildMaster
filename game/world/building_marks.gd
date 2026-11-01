class_name BuildingMarks
extends RefCounted
## The greybox marks of a building of state.buildings on the map (H2): its door and a sign with its name. Both go
## over the blocks (the door may be on the side the camera does not see). The blocks themselves are BlockViews in
## the objects layer (Y-sort).


## Mark of the door tile: a coloured diamond outline with a small door.
class DoorMark:
	extends Node2D
	var color: Color = Color(0.78, 0.63, 0.31)

	func _draw() -> void:
		var d := PackedVector2Array([Vector2(0, -14), Vector2(28, 0), Vector2(0, 14), Vector2(-28, 0)])
		draw_colored_polygon(d, Color(color, 0.25))
		draw_polyline(d + PackedVector2Array([d[0]]), color, 2.0)
		draw_rect(Rect2(-5, -12, 10, 14), color.darkened(0.45))
		draw_rect(Rect2(-5, -12, 10, 14), color, false, 1.0)


## The sign over the building: its name on a small board (and a highlight when the building is picked).
class Sign:
	extends Node2D
	var color: Color = Color(0.88, 0.56, 0.23)
	var text: String = ""
	var highlighted: bool = false:
		set(v):
			highlighted = v
			queue_redraw()
	var _label: Label

	func setup(t: String, c: Color) -> void:
		text = t
		color = c
		_label = Label.new()
		_label.text = t
		_label.add_theme_font_size_override("font_size", 10)
		_label.add_theme_color_override("font_color", Color(0.12, 0.08, 0.05))
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size = Vector2(64, 14)
		_label.position = Vector2(-32, -7)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(-30, -8, 60, 16)
		draw_line(Vector2(0, 8), Vector2(0, 18), Color(0.25, 0.17, 0.10), 2.0)
		draw_rect(r, color)
		draw_rect(r, Color(1.0, 0.92, 0.6) if highlighted else Color(0.25, 0.17, 0.10), false, 2.0 if highlighted else 1.0)
