class_name PausedOrders
extends RefCounted
## The orders given while the game is paused (GDD 4.1: none applies until the clock runs) as a screen that pauses sees
## them (the region map and the caravans over it, verificación E1): the button already pressed says it waits («Firmando…
## (al reanudar)»), the screen shows them in its own queue strip (the HUD's is under the screen) and the book's notices
## list them as «En espera». Reads Game.pending(); gives no orders.


## Whether an order of `type` whose fields match `fields` waits for the clock (the game paused).
static func waiting(game: Node, type: String, fields: Dictionary = {}) -> bool:
	if game == null or not bool(game.get("paused")) or not game.has_method("pending"):
		return false
	for o: Dictionary in game.call("pending"):
		if str(o.get("type", "")) != type:
			continue
		var all := true
		for k: Variant in fields:
			if str(o.get(k, "")) != str(fields[k]):
				all = false
				break
		if all:
			return true
	return false


## The queue lines of the orders of family `fam` that wait for the clock («1. Proponer el tratado…»), oldest first.
static func lines(game: Node, sim: Sim, fam: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if game == null or sim == null or not bool(game.get("paused")) or not game.has_method("pending"):
		return out
	for o: Dictionary in game.call("pending"):
		if str(sim.state.characters.get(str(o.get("actor", "")), {}).get("family", "")) != fam:
			continue
		out.append("%d. %s" % [out.size() + 1, SimQuery.order_label(sim.state, sim.catalog, o)])
	return out


## The strip of a screen that pauses: «En pausa · se hará al reanudar: 1. …» (hidden when nothing waits).
static func fill_strip(strip: Label, game: Node, sim: Sim, fam: String) -> void:
	if strip == null:
		return
	var ls := lines(game, sim, fam)
	strip.visible = not ls.is_empty()
	if ls.is_empty():
		return
	var text := SimQuery.t_("ui.paused_orders.strip") % "   ".join(ls)
	if strip.text != text:
		strip.text = text
		if OS.is_debug_build():
			print("[PausedOrders] en espera: %s" % text)
