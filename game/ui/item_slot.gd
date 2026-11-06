class_name ItemSlot
extends PanelContainer
## One square of an inventory (docs/ui/mecanicas/almacen_y_personaje.md §4.1, kit piece "casilla de inventario"):
## 30×30, the sunken field of the kit with the item's 16 px icon, the quantity at the bottom right and a quality dot
## at the top right (none = normal, silver = good, gold = excellent). States: empty (the hole colour), with an item,
## locked (an upgrade would open it: the lock) and reserved (an errand on its way: dashed edge). A left click and a right
## click are signals: the panel that owns it decides the order. The tooltip is the item's full name, quantity, weight
## and today's price (set by the panel).

signal clicked(slot: ItemSlot, right: bool)

const SIZE: Vector2 = Vector2(30, 30)
const QUALITY_DOTS: Array[Color] = [Color(0, 0, 0, 0), Color(0.78, 0.8, 0.84), Color(0.95, 0.85, 0.5)]

var item: String = ""
var quality: int = 0
var qty: int = 0
var state: String = "empty"   # empty | item | locked | reserved

var _icon: TextureRect
var _qty: Label


func _init() -> void:
	custom_minimum_size = SIZE
	theme_type_variation = &"KeyCap"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL   # the keyboard reaches the stacks too (verificación C13)
	_icon = TextureRect.new()
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_qty = Label.new()
	_qty.theme_type_variation = &"SmallLabel"
	_qty.add_theme_color_override("font_color", Color.html("#ece4d2"))
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_qty)


## Shows `item_id` × `n` at `q` (n 0 = only the icon, as an equipment slot), or empty with "".
func show_item(item_id: String, q: int = 0, n: int = 0, icon: Texture2D = null) -> void:
	item = item_id
	quality = q
	qty = n
	state = "item" if item_id != "" else "empty"
	_icon.texture = icon if icon != null else (VisualPaths.icon_small(item_id) if item_id != "" else null)
	_qty.text = str(n) if n > 1 or (n == 1 and item_id != "") else ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if item_id != "" else Control.CURSOR_ARROW
	queue_redraw()


## An empty square with a silhouette (an equipment slot with nothing: slot_empty_<slot>).
func show_empty(silhouette: Texture2D = null) -> void:
	show_item("")
	_icon.texture = silhouette
	_icon.modulate = Color(1, 1, 1, 0.45)


func set_locked() -> void:
	show_item("")
	state = "locked"
	_icon.texture = UiIcons.lock()
	_icon.modulate = Color(1, 1, 1, 0.6)
	modulate = Color(0.7, 0.7, 0.7)


func set_reserved(item_id: String, n: int) -> void:
	show_item(item_id, 0, n)
	state = "reserved"
	_icon.modulate = Color(1, 1, 1, 0.5)


func _draw() -> void:
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1), Color("#f2d880"), false, 1.0)
	if state == "item" and quality > 0 and quality < QUALITY_DOTS.size():
		draw_rect(Rect2(size.x - 6, 3, 3, 3), QUALITY_DOTS[quality])
	if state == "reserved":
		for x: int in range(1, int(size.x) - 1, 3):
			draw_rect(Rect2(x, 1, 1, 1), Color.html("#c8a84e"))
			draw_rect(Rect2(x, size.y - 2, 1, 1), Color.html("#c8a84e"))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		clicked.emit(self, mb.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()
	elif item != "" and event.is_action_pressed("ui_accept"):   # the keyboard: Enter moves the stack, like a click
		clicked.emit(self, false)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()
