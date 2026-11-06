class_name BuildingMarks
extends RefCounted
## The greybox marks of a building of state.buildings on the map (H2): its door and a sign with its name; H4: the
## idle icon (employees with nothing to do, GDD 4.7.4). They go over the blocks (the door may be on the side the camera does not see). The blocks themselves are BlockViews in
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
	var half_w: float = 30.0  # half the board's width: grows with the text (H3: "Forja de Ferrer")
	var _label: Label

	func setup(t: String, c: Color) -> void:
		text = t
		color = c
		_label = Label.new()
		_label.text = t
		WorldLabels.style(_label, "sign")
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		WorldLabels.keep_size(self)   # the whole board keeps its size on screen at ×2
		_fit()

	## The board's width follows the text as the label measures it (the project font, once in the tree).
	func _fit() -> void:
		var w := maxf(60.0, ceilf(_label.get_minimum_size().x) + 8.0)
		half_w = ceilf(w / 2.0)
		_label.size = Vector2(half_w * 2.0, 16)
		_label.position = Vector2(-half_w, -9)
		queue_redraw()

	func _ready() -> void:
		if _label != null:
			_fit()

	func _draw() -> void:
		var r := Rect2(-half_w, -8, half_w * 2.0, 16)
		draw_line(Vector2(0, 8), Vector2(0, 18), Color(0.25, 0.17, 0.10), 2.0)
		draw_rect(r, color)
		draw_rect(r, Color(1.0, 0.92, 0.6) if highlighted else Color(0.25, 0.17, 0.10), false, 2.0 if highlighted else 1.0)


## The idle icon over a building (H4, GDD 4.7.4): a speech bubble with "z z" (employees at work with nothing to do).
class IdleMark:
	extends Node2D
	var color: Color = Color(0.95, 0.92, 0.82)
	var ink: Color = Color(0.25, 0.17, 0.10)

	func _draw() -> void:
		var r := Rect2(-11, -9, 22, 13)
		draw_rect(r, color)
		draw_rect(r, ink, false, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-3, 4), Vector2(3, 4), Vector2(0, 8)]), color)
		draw_polyline(PackedVector2Array([Vector2(-3, 4), Vector2(0, 8), Vector2(3, 4)]), ink, 1.0)
		# "z z": two little zigzags
		for x: float in [-7.0, 1.0]:
			draw_polyline(PackedVector2Array([Vector2(x, -6), Vector2(x + 5, -6), Vector2(x, -1), Vector2(x + 5, -1)]), ink, 1.0)


## H5: the works bar over a building under construction (GDD 4.8): progress of the works and the time left. Colours
## and width from data/view.json upgrades.works. The scaffold itself is the node Works of the building's scene.
class WorksBar:
	extends Node2D
	var progress: float = 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			queue_redraw()
	var back: Color = Color(0.16, 0.13, 0.09)
	var fill: Color = Color(0.94, 0.75, 0.25)
	var width: float = 44.0
	var _label: Label

	func setup(cfg: Dictionary) -> void:
		back = ViewConfig.color(str(cfg.get("back", "#2a2018")))
		fill = ViewConfig.color(str(cfg.get("fill", "#f0c040")))
		width = float(cfg.get("width", 44))
		_label = Label.new()
		_label.name = "Left"
		WorldLabels.style(_label, "small", ViewConfig.color(str(cfg.get("text", "#f6ecd0"))))
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.size = Vector2(width + 40.0, 10)
		_label.position = Vector2(-(width + 40.0) / 2.0, -14)
		add_child(_label)

	## The time left, as the HUD writes it ("12 h").
	func set_text(t: String) -> void:
		if _label != null:
			_label.text = t

	func text() -> String:
		return _label.text if _label != null else ""

	func _draw() -> void:
		var r := Rect2(-width / 2.0, -2, width, 5)
		draw_rect(r.grow(1.0), back)
		draw_rect(Rect2(r.position, Vector2(width * progress, r.size.y)), fill)
