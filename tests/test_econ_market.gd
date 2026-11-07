extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## The market (GDD 4.5.1-4.5.3, 4.5.7, 4.23; docs/contratos/h3_mercado.md): buying and selling at the stalls and in
## the armory, never selling more than carried (H3 criterion), prices with quality, demand and difficulty, demand
## dropping with sales and recovering at dawn, opening hours, errands (H3 criterion) and save/load with one on its way.

const FAM: String = "fam_0001"
const HUGO: String = "chr_0001"
const FORGE: String = "bld_0001"
const RIVAL_FORGE: String = "bld_0002"
const ARMORY: String = "bld_0003"
const DAY: int = 600          # day 0, 10:00 (spring: day phase from 420 to 1140)
const NIGHT_STARTS: int = 1260
const NEXT_DAWN: int = 1440 + 300

var cat := Pins.no_player_needs(Pins.classic(Catalog.load_from()))  # pre-H5 figures, the founder without sleep and food: see tests/balance_pins.gd


## town_e_start by day, without the rival AI (so nobody else sells or buys while a test runs).
func _sim() -> Sim:
	# The rules are checked with the figures written in these tests (raw prices and demand drop are [balance] in data/).
	cat.item("iron")["base_price"] = 5
	cat.item("coal")["base_price"] = 3
	cat.market["demand"]["drop_per_unit"] = 0.05
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 3)["state"], cat)
	sim.state.families["fam_0003"]["ai_profile"] = ""
	sim.state.clock["minute"] = DAY
	return sim


func _at_stall(sim: Sim, stall: String, who: String = HUGO) -> void:
	var ch: Dictionary = sim.state.characters[who]
	ch["location"] = ""
	ch["path"] = []
	ch["position"] = (cat.maps()["town_e"]["stalls"][stall]["service"] as Array).duplicate()


func _in_armory(sim: Sim, who: String = HUGO) -> void:
	var ch: Dictionary = sim.state.characters[who]
	ch["location"] = ARMORY
	ch["station"] = ""
	ch["position"] = (sim.state.buildings[ARMORY]["door"] as Array).duplicate()


func _bag(sim: Sim, who: String = HUGO) -> Dictionary:
	return sim.state.characters[who]["inventory"]


func _storage(sim: Sim, b: String = FORGE) -> Dictionary:
	return sim.state.buildings[b]["inventory"]


func _gold(sim: Sim) -> int:
	return Money.gold(sim.state, FAM)


func _refused(sim: Sim, o: Dictionary, reason: String, msg: String) -> void:
	var r := Orders.apply(sim, o)
	eq(r["reason"], reason, msg)


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func _run(sim: Sim, minutes: int) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step())
	return all


func _sell(item: String, qty: int, quality: int = 0) -> Dictionary:
	return {"type": "sell", "actor": HUGO, "stall": "armory", "item": item, "quality": quality, "qty": qty}


func _buy(item: String, qty: int, to: String = "", stall: String = "resources") -> Dictionary:
	var o := {"type": "buy", "actor": HUGO, "stall": stall, "item": item, "quality": 0, "qty": qty}
	if to != "":
		o["deliver_to"] = to
	return o


# --- Hito: imposible vender más de lo que se tiene -------------------------------------------------------------------

func test_cannot_sell_more_than_carried() -> void:
	var sim := _sim()
	_in_armory(sim)
	Inventory.add(_bag(sim), cat, "sword", 0, 2)
	var gold := _gold(sim)
	_refused(sim, _sell("sword", 3), "not_enough", "3 swords with 2 in the bag")
	_refused(sim, _sell("sword", 1, 1), "not_enough", "no good sword, only normal ones")
	_refused(sim, _sell("hammer", 1), "not_enough", "no hammer at all")
	eq(Inventory.count(_bag(sim), "sword"), 2, "nothing left the bag")
	eq(_gold(sim), gold, "no gold for a refused sale")
	eq((sim.state.ledger["entries"] as Array).size(), 0, "nothing in the ledger")
	check(Orders.apply(sim, _sell("sword", 2))["ok"], "sells the 2 it has")
	eq(Inventory.count(_bag(sim), "sword"), 0, "bag empty")
	_refused(sim, _sell("sword", 1), "not_enough", "nothing left to sell")
	# The storage of the forge does not count: only what the character carries.
	eq(Inventory.count(_storage(sim), "sword"), 0, "no swords in the forge either")
	Inventory.add(_storage(sim), cat, "sword", 0, 5)
	_refused(sim, _sell("sword", 1), "not_enough", "swords in the forge are not in the bag")


# --- Precios: calidad, demanda y dificultad --------------------------------------------------------------------------

func test_prices_with_quality_demand_and_difficulty() -> void:
	var sim := _sim()
	sim.state.market["demand"]["sword"] = 1.2
	eq(Market.price(sim, "sword", 1, "buy"), 101, "round(65 × 1.3 × 1.2)")
	sim.state.market["demand"]["sword"] = 0.8
	eq(Market.price(sim, "sword", 2, "sell"), 58, "round(65 × 1.6 × 0.8 × 0.7)")
	sim.state.market["demand"]["sword"] = 1.0
	sim.state.difficulty = "easy"
	eq(Market.price(sim, "sword", 2, "buy"), 94, "easy: round(104 × 0.9)")
	sim.state.difficulty = "hard"
	eq(Market.price(sim, "sword", 2, "buy"), 114, "hard: round(104 × 1.1)")
	eq(Market.price(sim, "sword", 2, "sell"), 73, "the difficulty does not touch selling: round(104 × 0.7)")
	# What the orders charge and pay is that price.
	_at_stall(sim, "resources")
	var gold := _gold(sim)
	check(Orders.apply(sim, _buy("iron", 2))["ok"], "buys 2 iron on hard")
	eq(_gold(sim), gold - 2 * 6, "pays round(5 × 1.1) each")
	_in_armory(sim)
	Inventory.add(_bag(sim), cat, "sword", 1, 1)
	gold = _gold(sim)
	check(Orders.apply(sim, _sell("sword", 1, 1))["ok"], "sells a good sword")
	eq(_gold(sim), gold + 59, "round(65 × 1.3 × 0.7)")


# --- Venta: cobra y baja la demanda ----------------------------------------------------------------------------------

func test_selling_pays_and_drops_the_demand() -> void:
	var sim := _sim()
	_in_armory(sim)
	_bag(sim)["limit"] = 500.0  # room for 20 swords (8 kg each)
	check(Inventory.add(_bag(sim), cat, "sword", 0, 20), "20 swords in the bag")
	var gold := _gold(sim)
	var r := Orders.apply(sim, _sell("sword", 2))
	check(r["ok"], "sells 2: %s" % r["reason"])
	eq(_gold(sim), gold + 89, "unit by unit: round(65 × 0.7) + round(65 × 0.95 × 0.7)")
	near(Market.demand(sim, "sword"), 0.9, 0.0001, "demand drops 0.05 per unit")
	var e: Dictionary = sim.state.ledger["entries"][-1]
	eq([e["category"], int(e["amount"]), e["actor"]], ["market_sales", 89, HUGO], "market_sales entry")
	var sold: Dictionary = _of(sim.events, "market_sold")[0]
	eq([sold["actor"], sold["family"], sold["stall"], sold["item"], int(sold["quality"]), int(sold["qty"]),
		int(sold["price"]), int(sold["total"])], [HUGO, FAM, "armory", "sword", 0, 2, 46, 89], "market_sold event (price = the first unit's)")
	near(float(_of(sim.events, "demand_changed")[0]["demand"]), 0.9, 0.0001, "demand_changed event")
	eq(Market.price(sim, "sword", 0, "sell"), 41, "the next ones are cheaper: round(65 × 0.9 × 0.7)")
	check(Orders.apply(sim, _sell("sword", 18))["ok"], "sells the other 18")
	near(Market.demand(sim, "sword"), 0.5, 0.0001, "never below the minimum")
	# Any actor's sales count: the rival's man in the armory too.
	sim.state.market["demand"]["sword"] = 1.0
	_in_armory(sim, "chr_0006")
	Inventory.add(_bag(sim, "chr_0006"), cat, "sword", 0, 1)
	var o := _sell("sword", 1)
	o["actor"] = "chr_0006"
	check(Orders.apply(sim, o)["ok"], "the rival sells")
	near(Market.demand(sim, "sword"), 0.95, 0.0001, "the rival's sale drops it too")
	eq(Money.gold(sim.state, "fam_0003"), 80 + 46, "paid to the rival's family")


# --- Compra ----------------------------------------------------------------------------------------------------------

func test_buying_rules() -> void:
	var sim := _sim()
	var b := _buy("iron", 2)
	_refused(sim, b, "not_at_stall", "Hugo is in the street, not at the stall")
	_at_stall(sim, "food")
	_refused(sim, b, "not_at_stall", "at another stall")
	_at_stall(sim, "resources")
	_refused(sim, b.merged({"stall": "nowhere"}, true), "unknown_stall", "no such stall")
	_refused(sim, b.merged({"item": "dragon"}, true), "unknown_item", "no such item")
	_refused(sim, b.merged({"item": "sword"}, true), "wrong_stall", "swords are not sold at resources")
	_refused(sim, b.merged({"quality": 1}, true), "bad_quality", "only normal quality in H3 (provisional)")
	_refused(sim, b.merged({"qty": 0}, true), "bad_quantity", "zero")
	_refused(sim, b.merged({"qty": 16}, true), "too_heavy", "16 iron = 32 kg > 30")
	sim.state.characters[HUGO]["path"] = [[17, 15]]
	_refused(sim, b, "not_at_stall", "still walking")
	sim.state.characters[HUGO]["path"] = []
	sim.state.clock["minute"] = NIGHT_STARTS + 60
	_refused(sim, b, "market_closed", "closed at night")
	sim.state.clock["minute"] = 330
	_refused(sim, b, "market_closed", "closed at dawn")
	sim.state.clock["minute"] = 1150
	check(Orders.apply(sim, b)["ok"], "open at dusk")
	sim.state.families[FAM]["gold"] = 5
	_refused(sim, b, "not_enough_gold", "2 × 5 > 5 gold")
	eq(Inventory.count(_bag(sim), "iron"), 2, "only the dusk purchase is in the bag")
	sim.state.families[FAM]["gold"] = 100
	sim.state.clock["minute"] = DAY
	var gold := _gold(sim)
	sim.events = []
	check(Orders.apply(sim, b.merged({"qty": 3}, true))["ok"], "buys 3")
	eq(Inventory.count(_bag(sim), "iron"), 5, "into the bag")
	eq(_gold(sim), gold - 15, "3 × 5")
	var e: Dictionary = sim.state.ledger["entries"][-1]
	eq([e["category"], int(e["amount"]), e["building"], e["actor"]], ["purchases", -15, "", HUGO], "purchases entry")
	var ev: Dictionary = _of(sim.events, "market_bought")[0]
	eq([ev["actor"], ev["family"], ev["stall"], ev["item"], int(ev["quality"]), int(ev["qty"]), int(ev["cost"])],
		[HUGO, FAM, "resources", "iron", 0, 3, 15], "market_bought event")
	near(Market.demand(sim, "iron"), 1.0, 0.0001, "buying does not touch the demand")
	# The armory sells and buys inside, without taking its counter.
	_in_armory(sim)
	check(Orders.apply(sim, _buy("hammer", 1, "", "armory"))["ok"], "buys a hammer in the armory")
	_refused(sim, _buy("iron", 1, "", "armory"), "wrong_stall", "no iron in the armory")
	eq(str(sim.state.buildings[ARMORY]["zones"]["counter"].get("occupant", "")), "", "the counter stays free")


# --- Horario de la Armería -------------------------------------------------------------------------------------------

func test_armory_opening_hours() -> void:
	var sim := _sim()
	var hugo: Dictionary = sim.state.characters[HUGO]
	hugo["position"] = (sim.state.buildings[ARMORY]["door"] as Array).duplicate()
	var enter := {"type": "enter_building", "actor": HUGO, "building": ARMORY}
	sim.state.clock["minute"] = NIGHT_STARTS + 30
	_refused(sim, enter, "market_closed", "closed at night: cannot go in")
	eq(str(hugo["location"]), "", "still outside")
	sim.state.clock["minute"] = DAY
	check(Orders.apply(sim, enter)["ok"], "open by day: goes in")
	eq(str(hugo["location"]), ARMORY, "inside")
	check(Orders.apply(sim, enter)["ok"], "already inside: nothing to do")
	# Whoever is inside when it closes is put out at the door.
	sim.state.clock["minute"] = NIGHT_STARTS - 1
	var ev := sim.step()
	eq(str(hugo["location"]), "", "put out when it closes")
	eq(hugo["position"], sim.state.buildings[ARMORY]["door"], "at the door")
	eq(_of(ev, "shop_closed_out").size(), 1, "shop_closed_out event")
	eq(_of(ev, "building_left").size(), 1, "building_left event")
	# Own buildings do not close: Hugo enters his forge at night.
	hugo["position"] = (sim.state.buildings[FORGE]["door"] as Array).duplicate()
	check(Orders.apply(sim, {"type": "enter_building", "actor": HUGO, "building": FORGE})["ok"], "own forge at night")


# --- Demanda: se recupera al amanecer --------------------------------------------------------------------------------

func test_demand_recovers_at_dawn() -> void:
	var sim := _sim()
	var d: Dictionary = sim.state.market["demand"]
	d["sword"] = 0.5
	d["iron"] = 1.5
	d["coal"] = 0.95
	_run(sim, 60)
	near(Market.demand(sim, "sword"), 0.5, 0.0001, "no recovery during the day")
	sim.state.clock["minute"] = NEXT_DAWN - 1
	var ev := sim.step()
	near(Market.demand(sim, "sword"), 0.6, 0.0001, "+0.1 at dawn")
	near(Market.demand(sim, "iron"), 1.4, 0.0001, "above rest it goes down towards 1.0")
	near(Market.demand(sim, "coal"), 1.0, 0.0001, "never past rest")
	eq(_of(ev, "demand_changed").size(), 3, "one demand_changed per item that moved")
	_run(sim, 120)
	near(Market.demand(sim, "sword"), 0.6, 0.0001, "once per dawn")
	sim.state.clock["minute"] = 2 * 1440 + int(cat.time["phase_starts"]["summer"]["dawn"]) - 1  # day 2 is summer
	ev = sim.step()
	near(Market.demand(sim, "sword"), 0.7, 0.0001, "next dawn, +0.1 again")
	eq(_of(ev, "demand_changed").size(), 2, "coal is at rest: no event")


# --- Hito: recado de entrega -----------------------------------------------------------------------------------------

func test_errand_costs_20_percent_arrives_in_2_hours_and_weighs_nothing() -> void:
	var sim := _sim()
	_at_stall(sim, "resources")
	var gold := _gold(sim)
	var r := Orders.apply(sim, _buy("iron", 5, FORGE))
	check(r["ok"], "errand: %s" % r["reason"])
	eq(_gold(sim), gold - 25 - 5, "5 × 5 + 20 %")
	var entries: Array = sim.state.ledger["entries"]
	eq(entries.size(), 2, "two entries")
	eq([entries[0]["category"], int(entries[0]["amount"]), entries[0]["building"], entries[0]["ref"]],
		["purchases", -25, FORGE, "dlv_0001"], "the purchase")
	eq([entries[1]["category"], int(entries[1]["amount"]), entries[1]["building"], entries[1]["ref"]],
		["errands", -5, FORGE, "dlv_0001"], "the surcharge apart, in errands")
	eq(Inventory.weight(_bag(sim), cat), 0.0, "nothing in the bag: it does not weigh on Hugo")
	eq(Inventory.count(_storage(sim), "iron"), 10, "not in the storage yet")
	var sent: Dictionary = _of(sim.events, "errand_sent")[0]
	eq([sent["actor"], sent["family"], sent["delivery"], sent["stall"], sent["item"], int(sent["quality"]),
		int(sent["qty"]), sent["to"], int(sent["cost"]), int(sent["surcharge"]), int(sent["arrive"])],
		[HUGO, FAM, "dlv_0001", "resources", "iron", 0, 5, FORGE, 25, 5, DAY + 120], "errand_sent event")
	eq((sim.state.deliveries as Array).size(), 1, "on its way")
	eq(Market.pending(sim, FAM).size(), 1, "pending for the UI")
	var ev := _run(sim, 119)
	eq(Inventory.count(_storage(sim), "iron"), 10, "not before 2 h")
	eq(_of(ev, "errand_arrived").size(), 0, "no arrival yet")
	ev = _run(sim, 1)
	eq(Inventory.count(_storage(sim), "iron"), 15, "in the storage at 2 h")
	eq(_of(ev, "errand_arrived").size(), 1, "errand_arrived")
	eq((sim.state.deliveries as Array).size(), 0, "no longer on its way")
	# Heavier than Hugo could ever carry: an errand does not care.
	sim.state.families[FAM]["gold"] = 200
	check(Orders.apply(sim, _buy("iron", 16, FORGE))["ok"], "32 kg sent to the forge")


func test_errand_refused_if_it_does_not_fit() -> void:
	var sim := _sim()
	_at_stall(sim, "resources")
	var st := _storage(sim)
	for it: String in ["flour", "cloth", "planks", "bread", "saw", "needle", "document"]:
		Inventory.add(st, cat, it, 0, 1)
	eq((st["stacks"] as Array).size(), 9, "9 of 10 stacks")
	var gold := _gold(sim)
	check(Orders.apply(sim, _buy("stone", 1, FORGE))["ok"], "stone takes the last stack")
	gold = _gold(sim)
	_refused(sim, _buy("wood", 1, FORGE), "storage_full", "the last stack is reserved for the stone on its way")
	eq(_gold(sim), gold, "nothing paid")
	check(Orders.apply(sim, _buy("stone", 2, FORGE))["ok"], "more stone joins the reserved stack")
	check(Orders.apply(sim, _buy("iron", 3, FORGE))["ok"], "iron joins its own stack")
	_refused(sim, _buy("iron", 87, FORGE), "storage_full", "10 + 3 + 87 > 99 per stack and no stack left")
	_refused(sim, _buy("iron", 1, RIVAL_FORGE), "not_your_building", "not to the rival's forge")
	_refused(sim, _buy("iron", 1, ARMORY), "not_your_building", "not to the armory")
	_refused(sim, _buy("iron", 1, "bld_9999"), "unknown_building", "no such building")
	sim.state.families[FAM]["gold"] = 5
	_refused(sim, _buy("iron", 1, FORGE), "not_enough_gold", "5 + 1 > 5 gold")
	sim.state.families[FAM]["gold"] = 6
	check(Orders.apply(sim, _buy("iron", 1, FORGE))["ok"], "6 gold is enough for 5 + 1")
	eq(_gold(sim), 0, "all of it")


func test_errand_waits_at_the_door_if_the_storage_filled_meanwhile() -> void:
	var sim := _sim()
	_at_stall(sim, "resources")
	check(Orders.apply(sim, _buy("stone", 1, FORGE))["ok"], "stone on its way")
	var st := _storage(sim)
	for it: String in ["flour", "cloth", "planks", "bread", "saw", "needle", "document", "wool"]:
		Inventory.add(st, cat, it, 0, 1)
	var ev := _run(sim, 120)
	eq(_of(ev, "errand_blocked").size(), 1, "blocked once")
	eq((sim.state.deliveries as Array).size(), 1, "still waiting")
	ev = _run(sim, 10)
	eq(_of(ev, "errand_blocked").size(), 0, "the block is not repeated every minute")
	Inventory.remove(st, "wool", 0, 1)
	ev = _run(sim, 1)
	eq(_of(ev, "errand_arrived").size(), 1, "arrives as soon as there is room")
	eq(Inventory.count(st, "stone"), 1, "the stone is in")


# --- Guardar y cargar con un recado en camino ------------------------------------------------------------------------

func test_save_and_load_with_an_errand_on_its_way() -> void:
	var sim := _sim()
	_at_stall(sim, "resources")
	check(Orders.apply(sim, _buy("iron", 4, FORGE))["ok"], "errand sent")
	sim.state.market["demand"]["sword"] = 0.85
	_run(sim, 60)
	var r := SaveFile.from_text(JSON.stringify(sim.state.to_dict()))
	check(r.has("state"), "loads: %s" % str(r.get("error", "")))
	var back := Sim.new(r["state"], cat)
	eq((back.state.deliveries as Array).size(), 1, "the errand is still on its way")
	near(Market.demand(back, "sword"), 0.85, 0.0001, "demand saved")
	_run(sim, 60)
	var ev := _run(back, 60)
	eq(_of(ev, "errand_arrived").size(), 1, "arrives in the loaded game")
	eq(Inventory.count(_storage(back), "iron"), 14, "into the storage")
	eq(back.state_hash(), sim.state_hash(), "same as the game that was never saved")
	check(Orders.apply(back, _buy("coal", 1, FORGE))["ok"], "another errand after loading")
	eq(str(back.state.deliveries[0]["id"]), "dlv_0002", "ids go on")


# --- Consultas de la UI ----------------------------------------------------------------------------------------------

func test_offers_and_stall_at() -> void:
	var sim := _sim()
	eq(Market.stall_at(sim, HUGO), "", "in the street: no stall")
	var off := Market.offers(sim, HUGO, "resources")
	eq(off["reason"], "not_at_stall", "not there")
	eq(int((off["buy"] as Array)[0]["max_qty"]), 0, "nothing to buy from afar")
	eq(str((off["buy"] as Array)[0]["status"]), "not_at_stall", "with the reason")
	_at_stall(sim, "resources")
	Inventory.add(_bag(sim), cat, "iron", 0, 3)
	Inventory.add(_bag(sim), cat, "sword", 0, 1)
	eq(Market.stall_at(sim, HUGO), "resources", "at the resources stall")
	off = Market.offers(sim, HUGO, "resources")
	eq([off["open"], off["reason"]], [true, ""], "open and there")
	var items: Array = (off["buy"] as Array).map(func(row: Dictionary) -> String: return str(row["item"]))
	eq(items, ["coal", "iron", "stone", "wheat", "wood", "wool"], "the resources, sorted")
	var iron: Dictionary = (off["buy"] as Array)[1]
	eq([int(iron["quality"]), int(iron["price"]), int(iron["max_qty"]), iron["status"]], [0, 5, 8, "ok"],
		"iron: 5 each, 8 more fit (30 kg - 6 kg of iron - 8 kg of sword)")
	eq(off["sell"], [{"item": "iron", "quality": 0, "qty": 3, "price": 4}], "only what the stall takes")
	eq(off["deliver_to"], [FORGE], "the forge")
	eq(Market.max_buy(sim, HUGO, "resources", "iron", 0, FORGE), 16, "16 × 5 + 16 = 96 ≤ 100 gold")
	sim.state.families[FAM]["gold"] = 3
	off = Market.offers(sim, HUGO, "resources")
	eq(str((off["buy"] as Array)[1]["status"]), "not_enough_gold", "no gold for one iron")
	eq(str((off["buy"] as Array)[0]["status"]), "ok", "one coal (3) is affordable")
	sim.state.clock["minute"] = NIGHT_STARTS + 10
	off = Market.offers(sim, HUGO, "resources")
	eq([off["open"], off["reason"]], [false, "market_closed"], "closed")
	eq(Market.stall_at(sim, HUGO), "resources", "still at the stall while closed")
	_in_armory(sim)
	eq(Market.stall_at(sim, HUGO), "armory", "inside the armory")
	eq(Market.offers(sim, HUGO, "nowhere")["reason"], "unknown_stall", "unknown stall")


# --- bot_smith compra en el mercado ----------------------------------------------------------------------------------

func test_bot_smith_buys_at_the_market() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 5)["state"], cat)
	sim.state.families["fam_0003"]["ai_profile"] = ""
	var bot := BotSmith.new()
	var refused := 0
	var errands := 0
	var swords := 0
	for i: int in 3 * Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step(NeedsRoutine.bot_filter(sim, bot.orders(sim))):
			match str(e["type"]):
				"order_refused":
					if str(e["actor"]) == HUGO:
						refused += 1
				"errand_sent":
					errands += 1
				"work_done":
					if str(e.get("item", "")) == "sword" or str(e.get("output", {}).get("item", "")) == "sword":
						swords += 1
	eq(refused, 0, "no refused orders")
	check(errands >= 1, "buys iron or coal by errand (%d)" % errands)
	check(swords >= 1, "makes swords (%d)" % swords)
