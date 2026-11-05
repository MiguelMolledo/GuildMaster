class_name UiDriver
extends RefCounted
## Plays the game like a person (docs/gdd/07_testing.md §7.4): only mouse and keyboard events go in, through
## Input.parse_input_event (the same road as the OS: the input map, the GUI, _unhandled_input, the camera's polling).
## It finds a control by its node name, by its text or with a panel's own locator (row_of, cell_of, tab_button...),
## moves the mouse there in a few steps, checks that the control is the one under the pointer and clicks. A control
## that does not take the click (hidden, disabled, off screen or covered by another) is a failure with its reason.
## Coordinates: every position here is in the 960×540 viewport; the events carry window coordinates (×2).

var tree: SceneTree
var root: Window
var mouse: Vector2 = Vector2(480, 270)   # where the pointer is (viewport coordinates)
var last_input: String = ""             # "mouse" | "key": what the last order came from (coverage)
var history: Array = []                 # [{kind, detail}] of this step (the flow runner clears it)
var notes: Array = []                   # UX findings that did not stop the step (a panel that rebuilds its buttons)
var _shift: bool = false


func _init(t: SceneTree) -> void:
	tree = t
	root = t.root if t != null else null


## Hands the event to Input as the OS would, and flushes at once: the events go in the order they were made.
func _send(e: InputEvent) -> void:
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _log(kind: String, detail: String) -> void:
	history.append({"kind": kind, "detail": detail})
	if OS.is_debug_build():
		print("[UiDriver] %s: %s" % [kind, detail])


# --- raw input ------------------------------------------------------------------------------------------------------

func _motion(to: Vector2, mask: int = 0) -> void:
	var e := InputEventMouseMotion.new()
	var w := _to_window(to)
	e.position = w
	e.global_position = w
	e.relative = _to_window(to) - _to_window(mouse)
	e.button_mask = mask
	e.shift_pressed = _shift
	mouse = to
	_send(e)


## The pointer goes to `to` in `steps` motions (one per frame), as a hand would: hover and tooltips see it pass.
func move_to(to: Vector2, steps: int = 3) -> void:
	var from := mouse
	for i: int in steps:
		_motion(from.lerp(to, float(i + 1) / steps))
		await tree.process_frame
	await tree.process_frame
	if root.get_mouse_position().distance_to(to) > 1.0:
		print("[UiDriver] mouse lag: sent %s, the game sees %s" % [to, root.get_mouse_position()])


func _button(at: Vector2, index: MouseButton, pressed: bool, double: bool = false) -> void:
	var e := InputEventMouseButton.new()
	var w := _to_window(at)
	e.position = w
	e.global_position = w
	e.button_index = index
	e.pressed = pressed
	e.double_click = double and pressed
	e.shift_pressed = _shift
	e.button_mask = (1 << (index - 1)) if pressed else 0
	_send(e)


## A click at `at` (viewport coordinates): move there, press, release. `double` sends a second press marked double.
func click_at(at: Vector2, button: String = "left", double: bool = false, shift: bool = false) -> void:
	var index := MOUSE_BUTTON_RIGHT if button == "right" else MOUSE_BUTTON_LEFT
	_shift = shift
	await move_to(at)
	last_input = "mouse"
	_button(at, index, true)
	await tree.process_frame
	_button(at, index, false)
	if double:
		await tree.process_frame
		_button(at, index, true, true)
		await tree.process_frame
		_button(at, index, false)
	await tree.process_frame
	await tree.process_frame
	_shift = false
	last_input = "mouse"
	_log("click", "%s%s%s at %s" % [button, " double" if double else "", " +shift" if shift else "", at.round()])


## The mouse wheel at `at`: `up` zooms in (cam_zoom_in).
func wheel_at(at: Vector2, up: bool, times: int = 1) -> void:
	await move_to(at)
	last_input = "mouse"
	for i: int in times:
		var idx := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		_button(at, idx, true)
		_button(at, idx, false)
		await tree.process_frame
	last_input = "mouse"
	_log("wheel", "%s x%d at %s" % ["up" if up else "down", times, at.round()])


## Drag with the left button from `a` to `b` (inventory slots, the camera's middle drag with `button` = "middle").
func drag(a: Vector2, b: Vector2, button: String = "left") -> void:
	var index := MOUSE_BUTTON_MIDDLE if button == "middle" else MOUSE_BUTTON_LEFT
	await move_to(a)
	_button(a, index, true)
	await tree.process_frame
	for i: int in 6:
		_motion(a.lerp(b, (i + 1) / 6.0), 1 << (index - 1))
		await tree.process_frame
	_button(b, index, false)
	await tree.process_frame
	await tree.process_frame
	last_input = "mouse"
	_log("drag", "%s from %s to %s" % [button, a.round(), b.round()])


## A key press and release. `key` is a name ("L", "Escape", "F1", "Space", "Enter", "Tab", "1"...) or an action of
## the input map ("@ledger": its first key, with its modifiers).
func key(name: String, shift: bool = false, hold_frames: int = 1) -> String:
	var e := InputEventKey.new()
	if name.begins_with("@"):
		var ev := _action_key(name.substr(1))
		if ev == null:
			_log("key", "action %s has no key" % name)
			return "la acción %s no tiene tecla" % name.substr(1)
		e = ev.duplicate() as InputEventKey
		shift = shift or e.shift_pressed
	else:
		var code := OS.find_keycode_from_string(name)
		if code == KEY_NONE:
			return "tecla desconocida: %s" % name
		e.keycode = code
		e.physical_keycode = code
	if e.keycode == KEY_NONE:
		e.keycode = e.physical_keycode
	if e.physical_keycode == KEY_NONE:
		e.physical_keycode = e.keycode
	e.shift_pressed = shift
	var label := OS.get_keycode_string(e.keycode)
	if label.length() == 1:
		e.unicode = label.to_lower().unicode_at(0) if not shift else label.unicode_at(0)
	if shift:
		var s := InputEventKey.new()
		s.keycode = KEY_SHIFT
		s.physical_keycode = KEY_SHIFT
		s.pressed = true
		_send(s)
	e.pressed = true
	last_input = "key"
	_send(e)
	for i: int in hold_frames:
		await tree.process_frame
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	_send(up)
	if shift:
		var s2 := InputEventKey.new()
		s2.keycode = KEY_SHIFT
		s2.physical_keycode = KEY_SHIFT
		s2.pressed = false
		_send(s2)
	await tree.process_frame
	await tree.process_frame
	last_input = "key"
	_log("key", "%s%s" % ["Shift+" if shift else "", name])
	return ""


## Writes `text` in the focused field, one key per character.
func type_text(text: String) -> void:
	for ch: String in text:
		var e := InputEventKey.new()
		e.unicode = ch.unicode_at(0)
		e.keycode = OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE
		e.pressed = true
		_send(e)
		var up := e.duplicate() as InputEventKey
		up.pressed = false
		_send(up)
		await tree.process_frame
	last_input = "key"
	_log("type", text)


func _action_key(action: String) -> InputEventKey:
	if not InputMap.has_action(action):
		return null
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev as InputEventKey
	return null


# --- finding --------------------------------------------------------------------------------------------------------

## Every node of the tree (depth first, in drawing order within a canvas layer).
func all_controls(from: Node = null) -> Array:
	var out: Array = []
	_collect(from if from != null else root, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is Control:
		out.append(n)
	for c: Node in n.get_children():
		_collect(c, out)


## The shown text of a control ("" if it has none).
static func text_of(c: Control) -> String:
	if c is Button:
		return c.atr((c as Button).text)   # what is drawn: a .tscn text that is a key is translated on screen
	if c is Label:
		return c.atr((c as Label).text)
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is LineEdit:
		return (c as LineEdit).text
	return ""


static func _matches(have: String, want: String, exact: bool) -> bool:
	if want == "":
		return true
	var a := have.strip_edges().to_lower()
	var b := want.strip_edges().to_lower()
	return a == b if exact else a.contains(b)


## Finds the control of `spec`; returns {"node": Control} or {"error": "why"}. The spec:
##   "node": a node name (the scene's %UniqueName); "prefix": the start of a node name (sword_ for sword_1); "text" / "tr": its shown text (contains; "exact": true for equal),
##   "tr" is an i18n key turned into the shown text; "tip": its tooltip contains; "type": a class ("Button");
##   "within": a node name or a spec whose subtree is searched; "row": a text that a label near the control shows
##   (up to 4 levels above it); "has": a text inside the control itself; "enabled": only buttons that are not disabled; "via" + "fn" + "args": a locator of a panel (MarketPanel.row_of("wood", 0)) whose
##   result is searched with the rest of the spec; "index": the n-th match (0 by default); "any": also hidden ones.
func find(spec: Variant, from: Node = null) -> Dictionary:
	if spec is String:
		spec = {"node": spec} if not (spec as String).contains(" ") else {"text": spec}
	var s: Dictionary = spec
	var base: Node = from if from != null else root
	if s.has("via"):
		var host := _named(str(s["via"]))
		if host == null:
			return {"error": "no encuentro %s" % s["via"]}
		if s.has("fn"):
			if not host.has_method(str(s["fn"])):
				return {"error": "%s no tiene %s()" % [s["via"], s["fn"]]}
			var r: Variant = host.callv(str(s["fn"]), s.get("args", []))
			if not r is Node:
				return {"error": "%s.%s(%s) no da nada" % [s["via"], s["fn"], s.get("args", [])]}
			base = r as Node
		else:
			base = host
		var rest := s.duplicate()
		for k: String in ["via", "fn", "args"]:
			rest.erase(k)
		if rest.is_empty() or (rest.size() == 1 and rest.has("index")):
			return {"node": base} if base is Control else {"error": "%s no es un control" % base.name}
		s = rest
	if s.has("within"):
		var w := find(s["within"], from)
		if w.has("error"):
			return {"error": "dentro de %s: %s" % [s["within"], w["error"]]}
		base = w["node"]
	var want_text := str(s.get("text", ""))
	if s.has("tr"):
		want_text = TranslationServer.translate(str(s["tr"]))
	var exact := bool(s.get("exact", false))
	var hits: Array = []
	for c: Control in all_controls(base):
		if not bool(s.get("any", false)) and not c.is_visible_in_tree():
			continue
		if s.has("node") and str(c.name) != str(s["node"]):
			continue
		if s.has("prefix") and not str(c.name).begins_with(str(s["prefix"])):
			continue
		if s.has("type") and not c.is_class(str(s["type"])) and str(c.get_script().get_global_name() if c.get_script() != null else "") != str(s["type"]):
			continue
		if want_text != "" and not _matches(text_of(c), want_text, exact):
			continue
		if s.has("tip") and not _matches(c.tooltip_text, str(s["tip"]), false):
			continue
		if s.has("has") and not _has_text(c, str(s["has"])):
			continue
		if s.has("row") and not _near_text(c, str(s["row"]), bool(s.get("any", false))):
			continue
		if bool(s.get("enabled", false)) and c is BaseButton and (c as BaseButton).disabled:
			continue
		if (want_text != "" or s.has("row")) and not s.has("type") and not s.has("node") and not s.has("prefix") \
				and not _clickable_kind(c):
			continue
		hits.append(c)
	var i := int(s.get("index", 0))
	if hits.size() <= i:
		return {"error": "no encuentro %s" % JSON.stringify(spec)}
	return {"node": hits[i], "matches": hits.size()}


## Buttons and the like (what a text search wants): a button, a check, or a control that takes clicks itself.
static func _clickable_kind(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or (c.mouse_filter == Control.MOUSE_FILTER_STOP and not c is Label \
		and not c is Container and not c is Panel)


## A text shown inside `c` (its own subtree): a tree node with that name, a card with that title.
func _has_text(c: Control, text: String) -> bool:
	for d: Control in all_controls(c):
		if _matches(text_of(d), text, false):
			return true
	return false


func _near_text(c: Control, text: String, any: bool = false) -> bool:
	var n: Node = c
	for i: int in 4:
		n = n.get_parent()
		if n == null:
			return false
		for d: Control in all_controls(n):
			if (any or d.is_visible_in_tree()) and _matches(text_of(d), text, false):
				return true
	return false


## A node by its name anywhere in the tree (the first visible one, else the first).
func _named(n: String) -> Node:
	var first: Node = null
	for c: Node in _walk(root):
		if str(c.name) == n:
			if c is CanvasItem and (c as CanvasItem).is_visible_in_tree():
				return c
			if first == null:
				first = c
	return first


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c: Node in n.get_children():
		out.append_array(_walk(c))
	return out


func node(n: String) -> Node:
	return _named(n)


# --- clicking controls ----------------------------------------------------------------------------------------------

## Why `c` cannot take a click now ("" if it can): hidden, disabled (with its tooltip as the reason, or «sin motivo»),
## off screen or too small.
func why_not_clickable(c: Control) -> String:
	if not is_instance_valid(c):
		return "el control ya no existe"
	if not c.is_visible_in_tree():
		return "no se ve"
	if c is BaseButton and (c as BaseButton).disabled:
		var tip := c.tooltip_text.strip_edges()
		if tip != "":
			return "deshabilitado (%s)" % tip
		var said := reason_near(c)
		return "deshabilitado (dice al lado: %s)" % said if said != "" else "deshabilitado sin motivo (sin tooltip ni línea de motivo)"
	var r := c.get_global_rect()
	var vp := root.get_visible_rect()
	if r.size.x < 2 or r.size.y < 2:
		return "mide %s: no se puede pulsar" % r.size
	if not vp.encloses(r.grow(-1)):
		var inter := vp.intersection(r)
		if inter.get_area() < r.get_area() * 0.5:
			return "fuera de pantalla (%s)" % r
	return ""


## If `c` sits in a scroll list and is out of its view, the mouse wheel over the list brings it in (as a person
## would). Lists without a scroll are left as they are (a control out of the screen there is a failure).
func scroll_into_view(c: Control) -> void:
	var sc: ScrollContainer = null
	var n := c.get_parent()
	while n != null:
		if n is ScrollContainer:
			sc = n as ScrollContainer
			break
		n = n.get_parent()
	if sc == null:
		return
	for i: int in 40:
		var view := sc.get_global_rect().intersection(root.get_visible_rect())
		var r := c.get_global_rect()
		if view.grow(1).encloses(r):
			return
		var down := r.end.y > view.end.y
		var before := sc.scroll_vertical
		await wheel_at(view.get_center(), not down)
		if sc.scroll_vertical == before:
			return
	return


## A reason line shown next to `c` (a visible label named *Reason* near it, up to two levels up), "" if none.
func reason_near(c: Control) -> String:
	var n: Node = c
	for i: int in 3:
		n = n.get_parent()
		if n == null:
			return ""
		for d: Control in all_controls(n):
			if d is Label and str(d.name).contains("Reason") and d.is_visible_in_tree() and (d as Label).text.strip_edges() != "":
				return (d as Label).text.strip_edges().left(80)
	return ""


## The point to click in `c`: its centre, or the centre of the part inside the screen.
func point_of(c: Control) -> Vector2:
	var r := c.get_global_rect().intersection(root.get_visible_rect())
	return r.get_center().floor()


## The control under the pointer now (the one that would take a click).
func hovered() -> Control:
	return root.gui_get_hovered_control()


static func is_inside(c: Node, top: Node) -> bool:
	var n := c
	while n != null:
		if n == top:
			return true
		n = n.get_parent()
	return false


## Clicks the control of `spec` with real mouse events. Returns "" or the failure: not found, not clickable, covered
## (another control is under the pointer at its centre), or the click did not reach it (no pressed / gui_input).
## A panel that rebuilds the button while the pointer travels is searched again (a person would aim again) and noted.
func click(spec: Variant, button: String = "left", double: bool = false) -> String:
	var c: Control = null
	var at := Vector2.ZERO
	var h: Control = null
	for attempt: int in 4:
		var f := find(spec)
		if f.has("error"):
			return str(f["error"])
		c = f["node"]
		await scroll_into_view(c)
		if not is_instance_valid(c) or not c.is_inside_tree():
			notes.append("%s: el panel rehízo sus controles mientras se buscaba" % JSON.stringify(spec))
			continue
		var why := why_not_clickable(c)
		if why != "":
			return "%s: %s" % [path_of(c), why]
		at = point_of(c)
		await move_to(at)
		if not is_instance_valid(c) or not c.is_inside_tree():   # rebuilt while the pointer travelled
			notes.append("%s: el panel rehízo el botón mientras el ratón llegaba" % JSON.stringify(spec))
			continue
		h = hovered()
		break
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		return "%s: el panel no para de rehacer el botón" % JSON.stringify(spec)
	if h != null and not is_inside(h, c) and not is_inside(c, h):
		return "%s: lo tapa %s (%s sobre %s)" % [path_of(c), path_of(h), _r(h.get_global_rect()), _r(c.get_global_rect())]
	var got := {"pressed": false, "input": false}
	var on_pressed := func() -> void: got["pressed"] = true
	var on_input := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			got["input"] = true
	if c is BaseButton:
		(c as BaseButton).pressed.connect(on_pressed)
	c.gui_input.connect(on_input)
	await click_at(at, button, double)
	if is_instance_valid(c):
		if c is BaseButton and (c as BaseButton).pressed.is_connected(on_pressed):
			(c as BaseButton).pressed.disconnect(on_pressed)
		if c.gui_input.is_connected(on_input):
			c.gui_input.disconnect(on_input)
	_log("clicked", "%s «%s»" % [path_of(c), text_of(c).left(40)] if is_instance_valid(c) else "(freed)")
	if not is_instance_valid(c):
		return ""   # it went away with the click (a card's button closes it)
	if c is BaseButton and button == "left" and not bool(got["pressed"]) and (not c.is_inside_tree() or c.is_queued_for_deletion()):
		return "%s: REHECHO: el panel rehízo el botón entre pulsar y soltar (el clic se pierde)" % path_of(c)
	if c is BaseButton and button == "left" and not bool(got["pressed"]) and not bool(got["input"]):
		return "%s: el botón no recibió el clic" % path_of(c)
	if not c is BaseButton and not bool(got["input"]) and h != null and not is_inside(h, c):
		return "%s: no recibió el clic" % path_of(c)
	return ""


static func _r(r: Rect2) -> String:
	return "%d,%d %dx%d" % [r.position.x, r.position.y, r.size.x, r.size.y]


## A short readable path: the last three node names.
static func path_of(c: Node) -> String:
	if c == null or not is_instance_valid(c):
		return "(nada)"
	var parts: Array = []
	var n: Node = c
	while n != null and parts.size() < 3:
		parts.push_front(str(n.name))
		n = n.get_parent()
	return "/".join(parts)


## Clicks item `index` of the PopupMenu that `menu` (a MenuButton or OptionButton) has open: the item's row inside the
## embedded popup window. Returns "" or why not.
func click_popup_item(menu: Variant, index: int) -> String:
	var f := find(menu)
	if f.has("error"):
		return str(f["error"])
	var pop: PopupMenu = null
	if f["node"] is MenuButton:
		pop = (f["node"] as MenuButton).get_popup()
	elif f["node"] is OptionButton:
		pop = (f["node"] as OptionButton).get_popup()
	if pop == null or not pop.visible:
		return "%s no tiene su menú abierto" % path_of(f["node"])
	if index >= pop.item_count:
		return "el menú tiene %d entradas" % pop.item_count
	if pop.is_item_disabled(index):
		return "la entrada %d («%s») está deshabilitada" % [index, pop.get_item_text(index)]
	var sb := pop.get_theme_stylebox("panel")
	var top := sb.get_margin(SIDE_TOP) if sb != null else 0.0
	var bottom := sb.get_margin(SIDE_BOTTOM) if sb != null else 0.0
	var row_h := (pop.size.y - top - bottom) / float(pop.item_count)
	var at := Vector2(pop.position) + Vector2(pop.size.x / 2.0, top + row_h * (index + 0.5))
	var got := {"id": -1}
	var cb := func(id: int) -> void: got["id"] = id
	pop.id_pressed.connect(cb)
	await move_to(at)
	last_input = "mouse"
	_button(at, MOUSE_BUTTON_LEFT, true)
	await tree.process_frame
	_button(at, MOUSE_BUTTON_LEFT, false)
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(pop) and pop.id_pressed.is_connected(cb):
		pop.id_pressed.disconnect(cb)
	last_input = "mouse"
	_log("popup", "%s item %d «%s»" % [path_of(f["node"]), index, pop.get_item_text(index)])
	if int(got["id"]) < 0:
		return "la entrada %d del menú no recibió el clic (en %s)" % [index, at.round()]
	return ""


## Clicks the up (or down) arrow of the SpinBox of `spec` `times` times, as a person nudges a quantity.
func spin(spec: Variant, times: int = 1, up: bool = true) -> String:
	var f := find(spec)
	if f.has("error"):
		return str(f["error"])
	var sb := f["node"] as SpinBox
	if sb == null:
		return "%s no es un SpinBox" % path_of(f["node"])
	var why := why_not_clickable(sb)
	if why != "":
		return "%s: %s" % [path_of(sb), why]
	var before := sb.value
	var r := sb.get_global_rect()
	var at := Vector2(r.end.x - 3.0, r.position.y + r.size.y * (0.25 if up else 0.75)).floor()
	for i: int in times:
		await click_at(at)
	if is_equal_approx(sb.value, before):
		return "%s: la flecha %s no cambia el valor (sigue en %s)" % [path_of(sb), "arriba" if up else "abajo", before]
	return ""
