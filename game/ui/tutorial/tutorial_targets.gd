class_name TutorialTargets
extends RefCounted
## Where a step's target is on screen (docs/ui/05_tutorial.md §4.4) and, when it cannot be seen, what opens it
## (§4.5): the hidden panel that holds it, "@interior" for a station seen from the town, "@town" for the town seen
## from inside. Returns {"found": bool, "rect": Rect2, "opener": bool, "text": i18n key of the opener ("" = none),
## "node": the UI node or null, "world": true for a world target, "target": the target actually lit (the step's own or
## the opener's)}. A target can carry its own "opener" (a target, with "opener_text" or the text of its "in" panel's
## entry): it wins over the table.

const MAX_DEPTH: int = 4


static func resolve(t: Dictionary, ctx: TutorialContext, openers: Dictionary, ev: Dictionary = {},
		depth: int = 0) -> Dictionary:
	var none := {"found": false, "rect": Rect2(), "opener": false, "text": "", "node": null, "world": false}
	if t.is_empty() or depth > MAX_DEPTH:
		return none
	var pad := float(t.get("pad", 0.0))
	if t.has("zone"):
		var z := ctx.zone_rect(str(t["zone"]))
		return {"found": z.has_area(), "rect": z, "opener": false, "text": "", "node": null, "world": false, "target": t}
	if t.has("ui"):
		var n := ctx.find_ui(str(t["ui"]), str(t.get("in", "")))
		if ctx.shown(n):
			return {"found": true, "rect": ctx.node_rect(n).grow(pad), "opener": false, "text": "", "node": n,
				"world": false, "target": t}
		return _via(_opener_key(t, n, ctx, openers), t, ctx, openers, ev, depth)
	if t.has("world"):
		var w := ctx.world_rect(t, ev)
		var need := str(w.get("need", "none"))
		if need == "":
			return {"found": true, "rect": (w["rect"] as Rect2).grow(pad), "opener": false, "text": "", "node": null,
				"world": true, "target": t}
		if t.has("opener"):
			return _via("#own", t, ctx, openers, ev, depth)
		return _via(need if openers.has(need) else "", t, ctx, openers, ev, depth)
	return none


## Which entry of `openers` opens target `t` whose node `n` (maybe null) cannot be seen: the target's own "opener",
## the nearest hidden ancestor with an entry, "@interior" for the building's UI seen from the town, the "in" panel,
## the node's own name.
static func _opener_key(t: Dictionary, n: Node, ctx: TutorialContext, openers: Dictionary) -> String:
	if t.has("opener"):
		return "#own"
	if n != null and is_instance_valid(n):
		var a: Node = n
		while a != null:
			if openers.has(str(a.name)) and not ctx.shown(a):
				return str(a.name)
			a = a.get_parent()
		if ctx.place_of(n) == "interior" and not ctx.interior_open() and openers.has("@interior"):
			return "@interior"
	if t.has("in") and openers.has(str(t["in"])) and not ctx.shown(ctx.find_ui(str(t["in"]))):
		return str(t["in"])   # the panel that holds it is closed (open, a missing row is not opened by its button)
	if openers.has(str(t["ui"])):
		return str(t["ui"])
	return ""


static func _via(key: String, t: Dictionary, ctx: TutorialContext, openers: Dictionary, ev: Dictionary,
		depth: int) -> Dictionary:
	var none := {"found": false, "rect": Rect2(), "opener": false, "text": "", "node": null, "world": false}
	if key == "":
		return none
	var op: Dictionary
	if key == "#own":
		var text := str(t.get("opener_text", ""))
		if text == "":
			text = str((openers.get(str(t.get("in", "")), {}) as Dictionary).get("text", ""))
		op = {"target": t["opener"], "text": text}
	else:
		op = openers[key]
	var r := resolve(op.get("target", {}) as Dictionary, ctx, openers, ev, depth + 1)
	if r["found"] and not bool(r["opener"]):
		r["text"] = str(op.get("text", ""))
	r["opener"] = bool(r["found"])
	return r
