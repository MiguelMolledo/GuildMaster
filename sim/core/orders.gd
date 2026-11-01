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
## The actor must control the source: be it, or own the building it is. Proximity rules arrive with H2 (GDD 04 §4.3.4).
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
	var item := str(o.get("item", ""))
	var quality := int(o.get("quality", 0))
	var qty := int(o.get("qty", 0))
	if qty <= 0:
		return fail("bad_quantity")
	if Inventory.count(src, item, quality) < qty:
		return fail("not_enough")
	if not Inventory.can_add(dst, sim.catalog, item, quality, qty):
		return fail("no_room")
	Inventory.remove(src, item, quality, qty)
	Inventory.add(dst, sim.catalog, item, quality, qty)
	sim.events.append({"type": "items_moved", "actor": actor, "from": from, "to": to, "item": item,
		"quality": quality, "qty": qty})
	return ok()


## {"type": "move_to", "actor", "tile": [col, row]}: walk there by the cheapest route (GDD 05 §5.4, D3).
## Reasons: unknown_actor, dead, no_map, out_of_bounds, blocked, unreachable. The rules live in Movement.
static func _move_to(sim: Sim, o: Dictionary) -> Dictionary:
	return Movement.move_to(sim, str(o.get("actor", "")), o.get("tile"))


static func _controls(st: WorldState, actor: String, entity: String) -> bool:
	if entity == actor:
		return true
	return st.buildings.has(entity) and str(st.buildings[entity].get("owner", "")) == actor
