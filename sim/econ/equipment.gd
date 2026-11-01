class_name Equipment
extends RefCounted
## Equipment slots and carried weight (GDD 4.3.4). Owner: subgrim «edificio». Contract: docs/contratos/h2_forja.md.
##
## Slots: tool, clothes, accessory; each null or {item, quality}. The slot comes from the item's "slot" field
## (data/items: tools -> tool, work clothes and armour -> clothes, travel cloak -> accessory).
## Equipped things still weigh (GDD 4.3.4): the character's inventory "limit" holds the room left for the bag,
## max_weight - equipped weight. Equipping or unequipping moves weight between bag and slots and moves the limit
## the same amount, so Inventory.can_add (transfers, production, buying) counts the equipment too.

const SLOTS: Array[String] = ["tool", "clothes", "accessory"]


## Everything the character carries: bag + equipment, in kg.
static func carried_weight(sim: Sim, actor: String) -> float:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if ch.is_empty():
		return 0.0
	return Inventory.weight(ch.get("inventory", {}), sim.catalog) + equipped_weight(sim, actor)


## Most a character may carry, bag + equipment. Today the 30 kg of the scenario (the bag's limit plus what is worn).
## The Constitution bonus (GDD 4.2.2, a proposal) will add here when it is decided.
static func max_weight(sim: Sim, actor: String) -> float:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if ch.is_empty():
		return 0.0
	return float(ch.get("inventory", {}).get("limit", 0.0)) + equipped_weight(sim, actor)


static func equipped_weight(sim: Sim, actor: String) -> float:
	var eq: Dictionary = sim.state.characters.get(actor, {}).get("equipment", {})
	var w := 0.0
	for slot: String in SLOTS:
		var e: Variant = eq.get(slot)
		if e is Dictionary:
			w += float(sim.catalog.item(str((e as Dictionary).get("item", ""))).get("weight", 0.0))
	return w


## The slot an item goes to, "" if it cannot be worn.
static func slot_of(catalog: Catalog, item: String) -> String:
	var s := str(catalog.item(item).get("slot", ""))
	return s if s in SLOTS else ""


## {"type": "equip", "actor", "item", "quality"}: from the bag to its slot; what was there goes back to the bag.
static func order_equip(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var ch: Dictionary = st.characters[actor]
	if not bool(ch.get("alive", true)):
		return Orders.fail("dead")
	var item := str(o.get("item", ""))
	var quality := int(o.get("quality", 0))
	var slot := slot_of(sim.catalog, item)
	if slot == "":
		return Orders.fail("not_equippable")
	var inv: Dictionary = ch.get("inventory", {})
	if Inventory.count(inv, item, quality) < 1:
		return Orders.fail("not_enough")
	if not ch.has("equipment") or not ch["equipment"] is Dictionary:
		ch["equipment"] = {"tool": null, "clothes": null, "accessory": null}
	var eq: Dictionary = ch["equipment"]
	var old: Variant = eq.get(slot)
	var w_new := float(sim.catalog.item(item).get("weight", 0.0))
	Inventory.remove(inv, item, quality, 1)
	inv["limit"] = float(inv["limit"]) - w_new
	if old is Dictionary:
		var old_item := str((old as Dictionary).get("item", ""))
		var old_q := int((old as Dictionary).get("quality", 0))
		inv["limit"] = float(inv["limit"]) + float(sim.catalog.item(old_item).get("weight", 0.0))
		Inventory.add(inv, sim.catalog, old_item, old_q, 1)
		sim.events.append({"type": "item_unequipped", "actor": actor, "slot": slot, "item": old_item, "quality": old_q})
	eq[slot] = {"item": item, "quality": quality}
	sim.events.append({"type": "item_equipped", "actor": actor, "slot": slot, "item": item, "quality": quality})
	if OS.is_debug_build():
		print("[Equipment] %s equipa %s (q=%d) en %s (carga=%.1f/%.1f)" % [actor, item, quality, slot,
			carried_weight(sim, actor), max_weight(sim, actor)])
	return Orders.ok()


## {"type": "unequip", "actor", "slot"}: from the slot back to the bag (same total weight, so it always fits).
static func order_unequip(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var ch: Dictionary = st.characters[actor]
	var slot := str(o.get("slot", ""))
	if not slot in SLOTS:
		return Orders.fail("unknown_slot")
	var eq: Dictionary = ch.get("equipment", {})
	var cur: Variant = eq.get(slot)
	if not cur is Dictionary:
		return Orders.fail("slot_empty")
	var item := str((cur as Dictionary).get("item", ""))
	var quality := int((cur as Dictionary).get("quality", 0))
	var inv: Dictionary = ch.get("inventory", {})
	inv["limit"] = float(inv["limit"]) + float(sim.catalog.item(item).get("weight", 0.0))
	Inventory.add(inv, sim.catalog, item, quality, 1)
	eq[slot] = null
	sim.events.append({"type": "item_unequipped", "actor": actor, "slot": slot, "item": item, "quality": quality})
	if OS.is_debug_build():
		print("[Equipment] %s desequipa %s de %s" % [actor, item, slot])
	return Orders.ok()
