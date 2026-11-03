class_name MenuScreen
extends Control
## Base of the screens of docs/ui/02_menu_inicial.md (title, new game, load / save, options, credits, pause, ending,
## the confirmations): full screen over the town, keyboard first (arrows or Tab move the focus, Enter accepts, Esc
## goes back) and the first useful button focused on opening. While shown, no key reaches the town or the HUD below.
## Screens stack in ScreensLayer: the last one in the tree is drawn on top and gets the keys first.

signal back_requested

## Esc goes back (emits back_requested). The ending turns it off: there you have to choose.
@export var esc_goes_back: bool = true


func open() -> void:
	visible = true
	_refresh()
	focus_default.call_deferred()
	ViewConfig.info("Menu", "open %s" % name)


func close() -> void:
	if visible:
		ViewConfig.info("Menu", "close %s" % name)
	visible = false


## Fills the screen when it opens (screens override it).
func _refresh() -> void:
	pass


## The focus on the first useful control (default_focus).
func focus_default() -> void:
	if not visible or not is_inside_tree():
		return
	var c := default_focus()
	if c != null and c.is_inside_tree():
		c.grab_focus()


## The control that gets the focus on opening (screens override it): the first visible, enabled one.
func default_focus() -> Control:
	return MenuKit.first_focusable(self)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if esc_goes_back:
			back_requested.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.is_pressed() and not event.is_echo():
			_key(event as InputEventKey)
		get_viewport().set_input_as_handled()


## A key the screen uses itself (F5 / F9 in the pause menu). True if it was used.
func _key(_event: InputEventKey) -> bool:
	return false
