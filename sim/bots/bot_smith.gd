class_name BotSmith
extends RefCounted
## Bot that plays the smith by hand (GDD 07 §7.2, H2): Hugo enters the family forge, buys iron and coal when they
## are missing (buy_raw, provisional until H3) and makes ingots and swords in normal mode. It reads the station
## options through Production.recipe_options (the same query as the UI) and gives the same orders as the UI.
## Measures that production, auto-repeat and buying hold up for days without refused orders.

const ID: String = "smith"
const ACTOR: String = "chr_0001"
const BUILDING: String = "bld_0001"
const BUY_IRON: int = 10  # iron bought at a time (test bot, not a rule)
const BUY_COAL: int = 3


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not st.characters.has(ACTOR) or not st.buildings.has(BUILDING):
		return []
	var ch: Dictionary = st.characters[ACTOR]
	if not bool(ch.get("alive", true)) or not (ch.get("order_queue", []) as Array).is_empty() \
			or not (ch.get("path", []) as Array).is_empty():
		return []
	if str(ch.get("location", "")) != BUILDING:
		return [{"type": "enter_building", "actor": ACTOR, "building": BUILDING}]
	if Production.job_zone(sim, ACTOR, BUILDING) != "":
		return []  # working: auto-repeat goes on by itself
	if _status(sim, "anvil", "forge_sword") == "ok":
		return [_work("anvil", "forge_sword")]
	if _status(sim, "furnace", "forge_ingot") == "ok":
		return [_work("furnace", "forge_ingot")]
	var inv: Dictionary = st.buildings[BUILDING]["inventory"]
	if Inventory.count(inv, "iron_ingot") >= 2 and Inventory.count(inv, "coal") < 1:
		return _buy(sim, "coal", BUY_COAL)
	if Inventory.count(inv, "iron") < 2:
		return _buy(sim, "iron", BUY_IRON)
	return []


func _status(sim: Sim, zone: String, recipe: String) -> String:
	for opt: Dictionary in Production.recipe_options(sim, ACTOR, BUILDING, zone):
		if str(opt["recipe"]) == recipe:
			return str(opt["status"])
	return ""


func _work(zone: String, recipe: String) -> Dictionary:
	return {"type": "work_at", "actor": ACTOR, "building": BUILDING, "zone": zone, "recipe": recipe, "mode": "normal"}


## Buys as many as affordable up to `qty` (at least 2 iron / 1 coal to be useful); nothing if it cannot.
func _buy(sim: Sim, item: String, qty: int) -> Array:
	var gold := Money.gold(sim.state, Money.family_of(sim.state, ACTOR))
	var n := qty
	while n > 0 and Production.raw_cost(sim.catalog, item, n) > gold:
		n -= 1
	var inv: Dictionary = sim.state.buildings[BUILDING]["inventory"]
	if n < (2 if item == "iron" else 1) or not Inventory.can_add(inv, sim.catalog, item, Inventory.NORMAL, n):
		return []
	return [{"type": "buy_raw", "actor": ACTOR, "building": BUILDING, "item": item, "qty": n}]
