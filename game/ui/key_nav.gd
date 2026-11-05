class_name KeyNav
extends Node
## The keyboard in menus, panels and cards (verificación C13, the manager's decision): every button, check, picker,
## field and slider of the interface takes the focus (it shows the gold ring of the theme); Tab with nothing focused
## enters what is on top (a modal, a menu screen, a game, a card, the open management panel, else the HUD's bar);
## Tab / Shift+Tab and the arrows move between controls (Godot's own neighbours), Enter or Space press the focused
## one, Esc closes as always. The map stays the mouse's: the town's and the rooms' clicks have no keyboard path. A
## mouse click does not leave the focus behind (Space keeps pausing). While something is focused the arrows do not
## move the camera (WorldCamera asks focused()). Installed once by the HUD; works without a window too.

static var _node: KeyNav = null


static func install(tree: SceneTree) -> void:
	if _node != null and is_instance_valid(_node):
		return
	_node = KeyNav.new()
	_node.name = "KeyNav"
	tree.root.add_child.call_deferred(_node)
	tree.node_added.connect(_on_added)
	for n: Node in tree.root.find_children("*", "Control", true, false):
		_on_added(n)


static func _on_added(n: Node) -> void:
	if n is BaseButton or n is LineEdit or n is Range and not n is ProgressBar:
		_apply.call_deferred(n)   # after the code that made it has set its focus_mode


static func _apply(n: Node) -> void:
	if not is_instance_valid(n) or not n is Control or _in_world(n):
		return
	var c := n as Control
	if c is SpinBox:   # its field takes the keys (a number and Enter), not the box
		c.focus_mode = Control.FOCUS_NONE
		(c as SpinBox).get_line_edit().focus_mode = Control.FOCUS_ALL
		return
	if c.focus_mode == Control.FOCUS_NONE:
		c.focus_mode = Control.FOCUS_ALL
	if c is BaseButton and not c.has_meta("key_nav"):
		c.set_meta("key_nav", true)
		c.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb != null and not mb.pressed and c.has_focus():
				c.release_focus.call_deferred())   # a click leaves no focus: Space keeps pausing


## A control of the town or a room (under a Node2D): not the interface.
static func _in_world(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is Node2D:
			return true
		if p is CanvasLayer:
			return false
		p = p.get_parent()
	return false


## Something of the interface has the keyboard focus now.
static func focused(vp: Viewport) -> bool:
	return vp != null and vp.gui_get_focus_owner() != null


## _input, not _unhandled_input: with nothing focused the GUI swallows Tab before the unhandled pass. The tutorial's
## Tab (skip the step) goes first while one of its steps or hints is on screen.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_F6:
		next_zone((event as InputEventKey).shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if not (event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")):
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	var tut := get_tree().root.get_node_or_null("App/Tutorial")
	if tut != null and (str(tut.get("phase")) != "" or not (tut.get("hint") as Dictionary).is_empty()):
		return
	var top := top_container()
	if top == null:
		return
	var first := MenuKit.first_focusable(top)
	if first != null:
		first.grab_focus()
		get_viewport().set_input_as_handled()
		if OS.is_debug_build():
			print("[KeyNav] Tab enters %s: %s" % [top.name, first.name])


## What the keyboard enters first: the topmost thing open.
func top_container() -> Control:
	var root := get_tree().root
	var tries: Array = ["App/Hud/Root/ConfirmModal"]
	for p: String in tries:
		var n := root.get_node_or_null(p) as Control
		if n != null and n.is_visible_in_tree():
			return n
	var screens := root.get_node_or_null("App/ScreensLayer")
	if screens != null:
		for i: int in range(screens.get_child_count() - 1, -1, -1):
			var s := screens.get_child(i) as Control
			if s != null and s.visible:
				return s
	for layer: String in ["App/GamesLayer", "App/CardsLayer/DuelLayer", "App/DuelLayer"]:
		var l := root.get_node_or_null(layer)
		if l != null:
			for c: Node in l.get_children():
				if c is Control and (c as Control).is_visible_in_tree():
					return c as Control
	var cards := root.get_node_or_null("App/CardsLayer")
	if cards != null:   # a modal card or the duel's screen; the docked cards are reached with F6
		for i: int in range(cards.get_child_count() - 1, -1, -1):
			var c := cards.get_child(i) as Control
			if c != null and c.is_visible_in_tree() and not (c is PageCard and (c as PageCard).docked) and MenuKit.first_focusable(c) != null:
				return c
	for p: String in ["App/Hud/Root/HelpPanel", "App/Hud/Root/ModalZone"]:
		var n := root.get_node_or_null(p) as Control
		if n != null and n.is_visible_in_tree():
			if n.name == "HelpPanel":
				return n
			for c: Node in n.get_children():   # the big modal shown, if any
				if c is Control and (c as Control).visible:
					return c as Control
	var open := ManageSlot.open_panel(get_tree())
	if open != null and open.is_visible_in_tree():
		return open
	var bar := root.get_node_or_null("App/InteriorView/Ui/Root/BuildingBar") as Control
	if bar != null and bar.is_visible_in_tree():
		return bar
	return root.get_node_or_null("App/Hud/Root/StatusBar") as Control


func _ready() -> void:
	if OS.is_debug_build():
		print("[KeyNav] ready (%s)" % get_path())



## The zones F6 goes through, in order: what is on top (top_container), the docked cards, the open management
## panel, the building's bar, the HUD's bar, the column's cards (a microevent).
func zones() -> Array:
	var out: Array = []
	var root := get_tree().root
	var top := top_container()
	if top != null:
		out.append(top)
	for c: Variant in PageCard.stack():
		if not out.has(c):
			out.append(c)
	for p: String in ["App/InteriorView/Ui/Root/BuildingBar", "App/Hud/Root/StatusBar", "App/Hud/Root/Column"]:
		var n := root.get_node_or_null(p) as Control
		if n != null and n.is_visible_in_tree() and not out.has(n):
			out.append(n)
	var open := ManageSlot.open_panel(get_tree())
	if open != null and open.is_visible_in_tree() and not out.has(open):
		out.insert(mini(1, out.size()), open)
	return out.filter(func(z: Control) -> bool: return MenuKit.first_focusable(z) != null)


## F6 / Shift+F6: the focus jumps to the first control of the next (previous) zone.
func next_zone(back: bool = false) -> void:
	var zs := zones()
	if zs.is_empty():
		return
	var f := get_viewport().gui_get_focus_owner()
	var i := -1
	for k: int in zs.size():
		if f != null and (zs[k] as Control).is_ancestor_of(f):
			i = k
			break
	var j := (i + (-1 if back else 1) + zs.size()) % zs.size() if i >= 0 else 0
	var first := MenuKit.first_focusable(zs[j])
	if first != null:
		first.grab_focus()
		if OS.is_debug_build():
			print("[KeyNav] F6 -> %s: %s" % [(zs[j] as Control).name, first.name])
