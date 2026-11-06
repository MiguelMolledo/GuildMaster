class_name Peddler
extends RefCounted
## Vida · the peddler's stall (04f 4.24.3 «monta un puesto un día», 4.26.7 the loaded dice; H16 audit, 2026-11-06): a
## visitor whose kind has `wares` (data/life/life.json visitors.kinds.peddler.wares: [{item, price, qty, chance}])
## arrives with his stock (each ware a keyed roll against its chance: `life|vis|...|ware|<item>`, so nothing else moves)
## and sells it to whoever comes to him while he is in town: order buy_from_peddler. The gold goes out (P4, purchases);
## the piece goes to the buyer's bag. His stock lives in the visitor (state.characters[id].visitor.wares) and leaves
## with him at dusk.


## The stock a visitor of kind data `kd` brings, keyed by his arrival key: [{item, price, qty}].
static func stock_for(st: WorldState, kd: Dictionary, key: String) -> Array:
	var out: Array = []
	for w: Dictionary in kd.get("wares", []):
		var item := str(w.get("item", ""))
		if item == "" or Kin.roll(st, "%s|ware|%s" % [key, item]) >= float(w.get("chance", 1.0)):
			continue
		out.append({"item": item, "price": int(w.get("price", 1)), "qty": int(w.get("qty", 1))})
	return out


## The wares a character sells now ([] if he is not a peddler in town).
static func wares(st: WorldState, target: String) -> Array:
	var v: Variant = st.characters.get(target, {}).get("visitor")
	return (v as Dictionary).get("wares", []) if v is Dictionary else []


## "" if `actor` may buy `item` from `target` now (in range or not: the panel walks there first), else why: not_a_peddler,
## sold_out, not_enough_gold, too_heavy.
static func reason(sim: Sim, actor: String, target: String, item: String) -> String:
	var st := sim.state
	if not st.characters.has(actor) or not st.characters.has(target):
		return "unknown_actor"
	var w := _ware(st, target, item)
	if wares(st, target).is_empty():
		return "not_a_peddler"
	if w.is_empty() or int(w.get("qty", 0)) <= 0:
		return "sold_out"
	var fam := str(st.characters[actor].get("family", ""))
	if not Money.can_pay(st, fam, int(w["price"])):
		return "not_enough_gold"
	if not Inventory.can_add(st.characters[actor]["inventory"], sim.catalog, item, Inventory.NORMAL, 1):
		return "too_heavy"
	return ""


static func _ware(st: WorldState, target: String, item: String) -> Dictionary:
	for w: Dictionary in wares(st, target):
		if str(w["item"]) == item:
			return w
	return {}


## {"type": "buy_from_peddler", "actor", "target", "item"}: one piece of the peddler's stock, within the NPC actions'
## range. Reasons: the ones of reason and too_far.
static func order_buy(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var item := str(o.get("item", ""))
	var why := reason(sim, actor, target, item)
	if why != "":
		return Orders.fail(why)
	if not NpcActions.in_range(sim, actor, target):
		return Orders.fail("too_far")
	var w := _ware(st, target, item)
	var fam := str(st.characters[actor].get("family", ""))
	Money.change(sim, fam, -int(w["price"]), Money.PURCHASES, "peddler:" + item, "", actor)
	Inventory.add(st.characters[actor]["inventory"], sim.catalog, item, Inventory.NORMAL, 1)
	w["qty"] = int(w["qty"]) - 1
	sim.events.append({"type": "peddler_sold", "actor": actor, "family": fam, "peddler": target, "item": item,
		"price": int(w["price"])})
	if OS.is_debug_build():
		print("[Peddler] %s compra %s al buhonero %s por %d (le quedan %d)" % [actor, item, target, int(w["price"]),
			int(w["qty"])])
	return Orders.ok()
