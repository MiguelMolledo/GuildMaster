class_name UiFeel
extends RefCounted
## How the UI feels under the mouse (docs/ui/00_lenguaje_visual.md §8-9): the kit's cursors (the arrow by default, the
## hand over what can be clicked, the hourglass while a game loads or saves) and the shake of a disabled button that is
## pressed anyway (its "no" sound is the AudioDirector's, ui.denied). The cursor is not scaled with the viewport, so the ×2 images are used
## (assets/art/ui/cursor/*_x2.png). Buttons get the hand by themselves (`hook`); the world sets it while the mouse is
## over a building, a person or a station (`set_hand`). The menus call `wait(true/false)` around loading and saving.

const ARROW: String = "res://assets/art/ui/cursor/cursor_arrow_x2.png"
const HAND: String = "res://assets/art/ui/cursor/cursor_hand_x2.png"
const WAIT: String = "res://assets/art/ui/cursor/cursor_wait_x2.png"
const HAND_HOTSPOT: Vector2 = Vector2(8, 0)   # the fingertip
const WAIT_HOTSPOT: Vector2 = Vector2(9, 9)   # the middle of the hourglass

static var _installed: bool = false
static var _hand: bool = false


## Sets the three cursors once (display servers without a cursor, as headless, ignore it).
static func install(tree: SceneTree) -> void:
	if _installed or DisplayServer.get_name() == "headless":
		return
	_installed = true
	Input.set_custom_mouse_cursor(load(ARROW), Input.CURSOR_ARROW, Vector2.ZERO)
	Input.set_custom_mouse_cursor(load(HAND), Input.CURSOR_POINTING_HAND, HAND_HOTSPOT)
	Input.set_custom_mouse_cursor(load(WAIT), Input.CURSOR_BUSY, WAIT_HOTSPOT)
	Input.set_custom_mouse_cursor(load(WAIT), Input.CURSOR_WAIT, WAIT_HOTSPOT)
	if not tree.node_added.is_connected(hook):
		tree.node_added.connect(hook)
	for n: Node in tree.root.find_children("*", "BaseButton", true, false):
		hook(n)
	if OS.is_debug_build():
		print("[UiFeel] cursors installed (arrow, hand, wait)")


## Back to the system cursors (on quit: the custom cursor textures are freed before the renderer goes).
static func uninstall() -> void:
	if not _installed:
		return
	_installed = false
	for shape: int in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_BUSY, Input.CURSOR_WAIT]:
		Input.set_custom_mouse_cursor(null, shape)


## A button shows the hand while the mouse is over it, and shakes when it is pressed while disabled.
static func hook(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not b.has_meta("ui_feel"):
			b.set_meta("ui_feel", true)
			b.gui_input.connect(_on_button_input.bind(b))


static func _on_button_input(event: InputEvent, b: BaseButton) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and b.disabled:
		shake(b)


## 1 px to the left and right twice (0.15 s), the "no" of a disabled button. Containers put it back on the next layout.
static func shake(c: Control) -> void:
	if not c.is_inside_tree() or c.has_meta("ui_shaking"):
		return
	c.set_meta("ui_shaking", true)
	var x := c.position.x
	var t := c.create_tween()
	for dx: float in [-1.0, 1.0, -1.0, 1.0, 0.0]:
		t.tween_callback(func() -> void: c.position.x = x + dx)
		t.tween_interval(0.03)
	t.tween_callback(func() -> void: c.remove_meta("ui_shaking"))
	if OS.is_debug_build():
		print("[UiFeel] denied: %s" % c.name)


## The hand over the world (true while the mouse is over something that can be clicked), else the arrow.
static func set_hand(on: bool) -> void:
	if on == _hand:
		return
	_hand = on
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if on else Input.CURSOR_ARROW)


## The hourglass while a game loads or saves (the menus call it around the work).
static func wait(on: bool) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_WAIT if on else (Input.CURSOR_POINTING_HAND if _hand else Input.CURSOR_ARROW))
