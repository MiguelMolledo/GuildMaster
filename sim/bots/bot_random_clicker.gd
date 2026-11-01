class_name BotRandomClicker
extends RefCounted
## Bot that clicks at random (GDD 07 §7.2, 4.19 conservation): now and then gives an order of any type, with fields
## picked at random from what exists (characters, buildings, items, stalls, loans, contracts, notices) and, a part of
## the time, nonsense (unknown ids, negative quantities, missing fields). Valid and invalid orders of every type,
## through the same Orders.apply as the UI. The randomness comes from state.rng. It measures that nothing breaks and
## that the ledger always adds up to the gold.

const ID: String = "random_clicker"
const CHANCE_PER_MINUTE: float = 0.15  # an order every ~7 game minutes (test bot, not a rule)
const NONSENSE: float = 0.15           # share of fields filled with something that does not exist
const TYPES: Array[String] = ["wait", "transfer", "move_to", "enter_building", "exit_building", "go_to_station",
	"equip", "unequip", "work_at", "stop_work", "master_touch", "buy", "sell", "repay_loan",
	"read_notices", "accept_contract", "deliver_contract", "abandon_contract", "nonsense_order"]


func orders(sim: Sim) -> Array:
	var st := sim.state
	var rng := st.rng
	if st.characters.is_empty() or rng.randf() >= CHANCE_PER_MINUTE:
		return []
	var type := TYPES[rng.randi_range(0, TYPES.size() - 1)]
	var o := {"type": type, "actor": _pick(rng, _sorted(st.characters.keys()))}
	match type:
		"transfer":
			var places: Array = _sorted(st.characters.keys()) + _sorted(st.buildings.keys())
			o.merge({"from": _pick(rng, places), "to": _pick(rng, places), "item": _item(sim), "quality": _quality(rng),
				"qty": _qty(rng)})
		"move_to":
			var m: Dictionary = sim.catalog.maps().get(st.map_id, {})
			var size: Array = m.get("size", [10, 10])
			o["tile"] = [rng.randi_range(-2, int(size[0]) + 1), rng.randi_range(-2, int(size[1]) + 1)]
		"enter_building":
			o["building"] = _pick(rng, _sorted(st.buildings.keys()))
		"go_to_station", "work_at", "master_touch":
			o["zone"] = _pick(rng, ["furnace", "anvil", "counter", "storage"])
			if type != "go_to_station":
				o["building"] = _pick(rng, _sorted(st.buildings.keys()))
			if type == "work_at":
				o["recipe"] = _pick(rng, _sorted(sim.catalog.recipes().keys()))
				o["mode"] = _pick(rng, _sorted((sim.catalog.production.get("modes", {}) as Dictionary).keys()))
		"equip":
			o.merge({"item": _item(sim), "quality": _quality(rng)})
		"unequip":
			o["slot"] = _pick(rng, ["tool", "clothes", "accessory"])
		"buy", "sell":
			o.merge({"stall": _pick(rng, _sorted((sim.catalog.market.get("stalls", {}) as Dictionary).keys())),
				"item": _item(sim), "quality": _quality(rng), "qty": _qty(rng)})
			if type == "buy" and rng.randf() < 0.3:
				o["deliver_to"] = _pick(rng, _sorted(st.buildings.keys()))
		"repay_loan":
			o.merge({"loan": _pick(rng, _sorted(st.loans.keys())), "amount": rng.randi_range(-5, 60)})
		"read_notices":
			var ids: Array = []
			for n: Dictionary in st.notices:
				if rng.randf() < 0.3:
					ids.append(str(n["id"]))
			o["ids"] = ids
		"accept_contract", "deliver_contract", "abandon_contract":
			var cs: Array = []
			for c: Dictionary in st.contracts.get("board", []) + st.contracts.get("accepted", []):
				cs.append(str(c["id"]))
			o["contract"] = _pick(rng, cs)
	return [o]


func _pick(rng: RandomNumberGenerator, from: Array) -> String:
	if from.is_empty() or rng.randf() < NONSENSE:
		return "nothing_%d" % rng.randi_range(0, 99)
	return str(from[rng.randi_range(0, from.size() - 1)])


func _item(sim: Sim) -> String:
	return _pick(sim.state.rng, _sorted(sim.catalog.items().keys()))


func _quality(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(-1, 3)


func _qty(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(-1, 6)


func _sorted(a: Array) -> Array:
	var out: Array = []
	for x: Variant in a:
		out.append(str(x))
	out.sort()
	return out
