class_name BotSmith
extends RefCounted
## Bot that plays the smith by hand (GDD 07 §7.2, H2-H3): Hugo works in the family forge (ingots and swords in normal
## mode) and, when iron or coal run short and the market is open, walks to the resources stall and buys them with an
## errand to the forge (Market, buy with deliver_to), then goes back to work. It reads the station options through
## Production.recipe_options and the market through Market (the same queries as the UI) and gives the same orders.
## Measures that production, auto-repeat and buying hold up for days without refused orders.

const ID: String = "smith"
const ACTOR: String = "chr_0001"
const BUILDING: String = "bld_0001"
const STALL: String = "resources"
const BUY_IRON: int = 10  # iron bought at a time (test bot, not a rule)
const BUY_COAL: int = 3
const MIN_BUY: Dictionary = {"iron": 2, "coal": 1}  # fewer is not worth the trip


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not st.characters.has(ACTOR) or not st.buildings.has(BUILDING):
		return []
	var ch: Dictionary = st.characters[ACTOR]
	if not bool(ch.get("alive", true)) or not (ch.get("order_queue", []) as Array).is_empty() \
			or not (ch.get("path", []) as Array).is_empty():
		return []
	var inside := str(ch.get("location", "")) == BUILDING
	if inside:
		if Production.job_zone(sim, ACTOR, BUILDING) != "":
			return []  # working: auto-repeat goes on by itself
		if _status(sim, "anvil", "forge_sword") == "ok":
			return [_work("anvil", "forge_sword")]
		if _status(sim, "furnace", "forge_ingot") == "ok":
			return [_work("furnace", "forge_ingot")]
	var need := _needs(sim)
	if not need.is_empty() and Market.is_open(sim):
		if str(ch.get("location", "")) != "":
			return [{"type": "exit_building", "actor": ACTOR}]
		if Market.stall_at(sim, ACTOR) != STALL:
			return [{"type": "move_to", "actor": ACTOR, "tile": _service(sim)}]
		for item: String in need:
			var n := mini(int(need[item]), Market.max_buy(sim, ACTOR, STALL, item, Inventory.NORMAL, BUILDING))
			if n >= int(MIN_BUY[item]):
				return [{"type": "buy", "actor": ACTOR, "stall": STALL, "item": item, "quality": Inventory.NORMAL,
					"qty": n, "deliver_to": BUILDING}]
	if not inside:
		return [{"type": "enter_building", "actor": ACTOR, "building": BUILDING}]
	return []


func _status(sim: Sim, zone: String, recipe: String) -> String:
	for opt: Dictionary in Production.recipe_options(sim, ACTOR, BUILDING, zone):
		if str(opt["recipe"]) == recipe:
			return str(opt["status"])
	return ""


func _work(zone: String, recipe: String) -> Dictionary:
	return {"type": "work_at", "actor": ACTOR, "building": BUILDING, "zone": zone, "recipe": recipe, "mode": "normal"}


## What to buy ({item: qty}, iron first): iron below 2 or coal below 1 counting the errands on their way, and only
## if the family can pay at least MIN_BUY of it with the errand surcharge and it fits in the storage.
func _needs(sim: Sim) -> Dictionary:
	var st := sim.state
	var fam := Money.family_of(st, ACTOR)
	var inv: Dictionary = st.buildings[BUILDING]["inventory"]
	var out := {}
	for item: String in ["iron", "coal"]:
		var have := Inventory.count(inv, item)
		for d: Dictionary in Market.pending(sim, fam):
			if str(d["item"]) == item and str(d["to"]) == BUILDING:
				have += int(d["qty"])
		var low := 2 if item == "iron" else 1
		if have >= low:
			continue
		var cost := Market.price(sim, item, Inventory.NORMAL, "buy") * int(MIN_BUY[item])
		if Money.can_pay(st, fam, cost + Market.errand_surcharge(sim, cost)) \
				and Inventory.can_add(inv, sim.catalog, item, Inventory.NORMAL, int(MIN_BUY[item])):
			out[item] = BUY_IRON if item == "iron" else BUY_COAL
	return out


func _service(sim: Sim) -> Array:
	var map: Dictionary = sim.catalog.maps().get(sim.state.map_id, {})
	return map.get("stalls", {}).get(STALL, {}).get("service", [0, 0])
