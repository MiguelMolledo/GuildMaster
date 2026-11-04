class_name TutorialContext
extends RefCounted
## What the tutorial reads of the game (docs/ui/05_tutorial.md §7). This base knows only the UI: it finds nodes by
## name under ui_roots() and answers the conditions about panels; the game's answers (symbols, the world, the sim's
## state, the session) come from the subclass the app uses (AppTutorialContext). The tests use this base with a few
## nodes of their own. Nothing here gives an order.

const REFIND_SECONDS: float = 0.25

var viewport: Vector2 = Vector2(960, 540)
var _cache: Dictionary = {}   # "<name>|<in>" -> {node, at}


## The nodes under which the UI targets are looked for (HUD, the interior's UI, the cards).
func ui_roots() -> Array:
	return []


## A menu or nothing to show: the tutorial hides and waits.
func blocked() -> bool:
	return false


## The value of a "$symbol" now (`ev` = the event a hint came from, for "$event.<field>"); anything else as it is.
func symbol(v: Variant, ev: Dictionary = {}) -> Variant:
	if v is String and str(v).begins_with("$event."):
		return ev.get(str(v).substr(7), "")
	return v


## The {placeholders} of the texts.
func text_args() -> Dictionary:
	return {}


## A sim event concerns the player's family.
func mine(_e: Dictionary) -> bool:
	return true


## A world target on screen: {"rect": Rect2, "need": ""} when it can be seen now, else "need" says what opens it
## ("@interior" | "@town") or "none".
func world_rect(_t: Dictionary, _ev: Dictionary = {}) -> Dictionary:
	return {"rect": Rect2(), "need": "none"}


## Moves the camera so that a world target falls in the free view (only if it does not already).
func focus_camera(_t: Dictionary, _ev: Dictionary = {}) -> void:
	pass


## The game's conditions (CONDITIONS minus the panel ones, which this base answers).
func state_value(_name: String, _t: Dictionary) -> bool:
	return false


## The UI events since the last call: [[type, data], ...] (panels opened and closed, camera, pause...).
func poll() -> Array:
	return []


## Rects that take clicks in guided mode besides the target and the card (the pause and the speeds).
func passthrough() -> Array:
	return []


## "interior" if `node` belongs to the building's view (its bar, its panels), else "".
func place_of(_node: Node) -> String:
	return ""


func interior_open() -> bool:
	return false


func set_paused(_on: bool) -> void:
	pass


## The camera's position in screen pixels (for camera_moved).
func camera_screen() -> Vector2:
	return Vector2.ZERO


## The rect of HUD zone `z` (or the free view, "view").
func zone_rect(z: String) -> Rect2:
	if z == "view":
		return HudLayout.view_rect(viewport)
	return HudLayout.zones(viewport).get(z, Rect2())


# --- the UI ----------------------------------------------------------------------------------------------------------

## Whether `n` is on screen: it and every parent visible (canvas layers too), and with some size. Walked by hand so
## that it also answers outside the scene tree (the tests).
func shown(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or not n is CanvasItem:
		return false
	var p: Node = n
	while p != null:
		if p is CanvasItem and not (p as CanvasItem).visible:
			return false
		if p is CanvasLayer and not (p as CanvasLayer).visible:
			return false
		p = p.get_parent()
	if n is Control:
		return (n as Control).size.x > 0.0 and (n as Control).size.y > 0.0
	return true


## The node of the UI named `name` (with * wildcards) under a node named `inside` (if given): the first one on
## screen, else the first one found (hidden), else null. Cached; looked for again every REFIND_SECONDS when the cached
## one is gone or hidden.
func find_ui(name: String, inside: String = "") -> Node:
	var key := name + "|" + inside
	var now := Time.get_ticks_msec() / 1000.0
	var c: Dictionary = _cache.get(key, {})
	if not c.is_empty():
		var obj: Variant = c["node"]
		var n: Node = obj as Node if is_instance_valid(obj) else null
		if n != null and n.is_inside_tree() and shown(n):
			return n
		if now - float(c["at"]) < REFIND_SECONDS:
			return n
	var found := _search(name, inside)
	_cache[key] = {"node": found, "at": now}
	return found


## Forgets the cache (a new game, the tests).
func clear_cache() -> void:
	_cache.clear()


func _search(name: String, inside: String) -> Node:
	var first: Node = null
	for r: Variant in ui_roots():
		var root := r as Node
		if root == null or not is_instance_valid(root):
			continue
		var scopes: Array = [root]
		if inside != "":
			scopes = []
			_collect(root, inside, scopes)
		for s: Node in scopes:
			var hit := _first(s, name, first == null)
			if hit.has("shown"):
				return hit["shown"]
			if first == null and hit.has("any"):
				first = hit["any"]
	return first


## The nodes named `name` under `n` (n included).
func _collect(n: Node, name: String, out: Array) -> void:
	if TutorialRules.name_is(str(n.name), name):
		out.append(n)
	for ch: Node in n.get_children():
		_collect(ch, name, out)


## {"shown": the first match on screen} or {"any": the first match} under `n` (`n` itself is not a match).
func _first(n: Node, name: String, want_any: bool) -> Dictionary:
	var out := {}
	for ch: Node in n.get_children():
		if TutorialRules.name_is(str(ch.name), name):
			if shown(ch):
				return {"shown": ch}
			if want_any and not out.has("any"):
				out["any"] = ch
		var sub := _first(ch, name, want_any and not out.has("any"))
		if sub.has("shown"):
			return sub
		if sub.has("any") and not out.has("any"):
			out["any"] = sub["any"]
	return out


## Screen rect of a node of the UI.
func node_rect(n: Node) -> Rect2:
	if n is Control:
		return (n as Control).get_global_rect()
	return Rect2()


## A condition ({"state": name, args...}) now.
func condition(t: Dictionary, ev: Dictionary = {}) -> bool:
	var name := str(t.get("state", ""))
	match name:
		"panel_open":
			var p := find_ui(str(t.get("is", "")))
			if not shown(p):
				return false
			for k: String in TutorialRules.PANEL_PROPS:
				if t.has(k) and not TutorialRules.same(p.get(k), symbol(t[k], ev)):
					return false
			return true
		"panel_prop":
			var p := find_ui(str(t.get("panel", "")))
			return shown(p) and TutorialRules.same(p.get(str(t.get("prop", ""))), symbol(t.get("value"), ev))
		"node_visible":
			return shown(find_ui(str(t.get("is", "")), str(t.get("in", ""))))
	return state_value(name, t)


## panel_opened's data: the panel and the properties it has of PANEL_PROPS.
static func panel_data(p: Node) -> Dictionary:
	var d := {"panel": str(p.name)}
	for k: String in TutorialRules.PANEL_PROPS:
		var v: Variant = p.get(k)
		if v != null and (v is String or v is int or v is float or v is bool or v is StringName):
			d[k] = str(v) if v is StringName else v
	return d
