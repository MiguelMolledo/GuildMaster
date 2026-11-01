class_name Orders
extends RefCounted
## Every change an actor starts comes in as an order (GDD 05 §5.5): a Dictionary {"type": String, "actor": String, ...}.
## The UI, the bots, family AI and rival families give the same orders; nobody changes the state another way.
## apply() validates first and returns {"ok": bool, "reason": String}. A refused order changes nothing; its reason is
## an id the UI shows through i18n ("reason.<id>").
##
## Orders today: wait, transfer, move_to; H2: enter_building, exit_building, go_to_station, equip, unequip, work_at,
## stop_work, master_touch, buy_raw (handlers live with their system; docs/contratos/h2_forja.md). Each milestone adds its own (GDD 05 §5.5 has the full list).


static func apply(sim: Sim, order: Dictionary) -> Dictionary:
	var type := str(order.get("type", ""))
	match type:
		"wait":
			return ok()
		"transfer":
			return _transfer(sim, order)
		"move_to":
			return _move_to(sim, order)
		# H2 · buildings and items (sim/world/buildings.gd, sim/econ/equipment.gd)
		"enter_building":
			return Buildings.order_enter(sim, order)
		"exit_building":
			return Buildings.order_exit(sim, order)
		"go_to_station":
			return Buildings.order_go_to_station(sim, order)
		"equip":
			return Equipment.order_equip(sim, order)
		"unequip":
			return Equipment.order_unequip(sim, order)
		# H2 · production (sim/econ/production.gd)
		"work_at":
			return Production.order_work_at(sim, order)
		"stop_work":
			return Production.order_stop_work(sim, order)
		"master_touch":
			return Production.order_master_touch(sim, order)
		"buy_raw":
			return Production.order_buy_raw(sim, order)
	return fail("unknown_order")


static func ok() -> Dictionary:
	return {"ok": true, "reason": ""}


static func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## {"type": "transfer", "actor", "from", "to", "item", "quality", "qty"}: moves items between two inventories.
## The actor must control the source: be it, or own the building it is (its own or its family's), and be near
## (GDD 04 §4.3.4, _near). A character's weight limit counts its equipment (Equipment): too_heavy.
static func _transfer(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var from := str(o.get("from", ""))
	var to := str(o.get("to", ""))
	if not st.characters.has(actor):
		return fail("unknown_actor")
	if from == to:
		return fail("same_inventory")
	var src := st.inventory_of(from)
	var dst := st.inventory_of(to)
	if src.is_empty() or dst.is_empty():
		return fail("no_inventory")
	if not _controls(st, actor, from):
		return fail("not_yours")
	var near := _near(st, from, to)
	if near == "" and actor != from and actor != to:
		near = _near(st, actor, from)  # an owner moving its building's goods must be inside it too
	if near != "":
		return fail(near)
	var item := str(o.get("item", ""))
	var quality := int(o.get("quality", 0))
	var qty := int(o.get("qty", 0))
	if qty <= 0:
		return fail("bad_quantity")
	if Inventory.count(src, item, quality) < qty:
		return fail("not_enough")
	if not Inventory.can_add(dst, sim.catalog, item, quality, qty):
		return fail("too_heavy" if st.characters.has(to) else "no_room")  # a character's limit counts its equipment
	Inventory.remove(src, item, quality, qty)
	Inventory.add(dst, sim.catalog, item, quality, qty)
	sim.events.append({"type": "items_moved", "actor": actor, "from": from, "to": to, "item": item,
		"quality": quality, "qty": qty})
	return ok()


## {"type": "move_to", "actor", "tile": [col, row]}: walk there by the cheapest route (GDD 05 §5.4, D3).
## Reasons: unknown_actor, dead, no_map, out_of_bounds, blocked, unreachable. The rules live in Movement.
## Inside a building a character does not walk the map: not_inside_map until it leaves (exit_building).
static func _move_to(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	if str(sim.state.characters.get(actor, {}).get("location", "")) != "":
		return fail("not_inside_map")
	return Movement.move_to(sim, actor, o.get("tile"))


static func _controls(st: WorldState, actor: String, entity: String) -> bool:
	if entity == actor:
		return true
	return Buildings.owns(st, actor, entity)


## Physical proximity for a transfer (GDD 4.3.4): "" when near, else the reason. Character <-> building: the
## character is inside it. Character <-> character: same family, and same tile on the map or inside the same building.
static func _near(st: WorldState, a: String, b: String) -> String:
	if st.characters.has(a) and st.characters.has(b):
		var ca: Dictionary = st.characters[a]
		var cb: Dictionary = st.characters[b]
		if str(ca.get("family", "")) == "" or str(ca.get("family", "")) != str(cb.get("family", "")):
			return "not_family"
		var la := str(ca.get("location", ""))
		if la != str(cb.get("location", "")):
			return "too_far"
		if la != "":
			return ""
		var pa: Array = ca.get("position", [])
		var pb: Array = cb.get("position", [])
		return "" if pa.size() == 2 and pb.size() == 2 and int(pa[0]) == int(pb[0]) and int(pa[1]) == int(pb[1]) \
			else "too_far"
	if st.characters.has(a) and st.buildings.has(b):
		return "" if str(st.characters[a].get("location", "")) == b else "not_inside"
	if st.buildings.has(a) and st.characters.has(b):
		return "" if str(st.characters[b].get("location", "")) == a else "not_inside"
	return "too_far"  # building <-> building: somebody has to carry it
