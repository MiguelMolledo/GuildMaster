class_name WorldCamera
extends Camera2D
## Camera of the town view: WASD/arrows pan (cam_left/right/up/down), wheel zoom (cam_zoom_in/out) between the
## zoom_levels of data/view.json (whole numbers only, D2), middle-button drag (cam_drag). The centre is clamped to
## the map bounds and the drawn position is rounded to whole world pixels so nothing shimmers or deforms.

const FALLBACK_VIEWPORT: Vector2 = Vector2(960, 540)

var bounds: Rect2 = Rect2()        # world rect the centre may visit (empty = anywhere)
var zoom_levels: Array[int] = [1, 2]
var zoom_index: int = 0
var speed: float = 480.0           # screen pixels per second
var _center: Vector2 = Vector2.ZERO
var _dragging: bool = false


func _init() -> void:
	position_smoothing_enabled = false
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	var levels: Array = ViewConfig.value("zoom_levels", [1, 2])
	zoom_levels.clear()
	for z: Variant in levels:
		zoom_levels.append(maxi(1, int(z)))
	speed = float(ViewConfig.value("camera_speed", 480))
	_apply()


func set_bounds(r: Rect2) -> void:
	bounds = r
	_apply()


func center_on(p: Vector2) -> void:
	_center = p
	_apply()


func current_zoom() -> int:
	return zoom_levels[zoom_index]


## Moves the zoom one level (dir +1 closer, -1 farther), keeping the world point under `anchor` (screen) still.
func zoom_step(dir: int, anchor: Vector2) -> void:
	var i := clampi(zoom_index + dir, 0, zoom_levels.size() - 1)
	if i == zoom_index:
		return
	var before := screen_to_world(anchor)
	zoom_index = i
	_apply()
	_center += before - screen_to_world(anchor)
	_apply()
	ViewConfig.info("Camera", "zoom x%d (centre=%s)" % [current_zoom(), position])


## Pans by `screen_delta` screen pixels.
func pan(screen_delta: Vector2) -> void:
	_center += screen_delta / float(current_zoom())
	_apply()


func viewport_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else FALLBACK_VIEWPORT


## Screen (viewport) pixel -> world pixel, with the position and zoom actually drawn.
func screen_to_world(screen: Vector2) -> Vector2:
	return position + (screen - viewport_size() / 2.0) / float(current_zoom())


func world_to_screen(world: Vector2) -> Vector2:
	return (world - position) * float(current_zoom()) + viewport_size() / 2.0


func _process(delta: float) -> void:
	var dir := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if dir != Vector2.ZERO and KeyNav.focused(get_viewport()):
		dir = Vector2.ZERO   # the arrows move the focus of a panel, not the town
	if dir != Vector2.ZERO:
		pan(dir * speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


## The camera's share of the input (wheel, middle drag). True if it used the event.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if event.is_action_pressed("cam_zoom_in"):
			zoom_step(1, mb.position)
			return true
		if event.is_action_pressed("cam_zoom_out"):
			zoom_step(-1, mb.position)
			return true
		if event.is_action("cam_drag"):
			_dragging = mb.pressed
			return true
	elif event is InputEventMouseMotion and _dragging:
		pan(-(event as InputEventMouseMotion).relative)
		return true
	return false


func _apply() -> void:
	if bounds.has_area():
		_center = _center.clamp(bounds.position, bounds.end)
	zoom = Vector2.ONE * float(current_zoom())
	position = _center.round()
