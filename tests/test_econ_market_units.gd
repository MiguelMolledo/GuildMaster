extends "res://tests/test_case.gd"
## Selling several units at once is paid unit by unit (subgrim «balance», H3): each unit at the demand left by the
## one before, so selling 10 at once gives the same gold and the same demand as selling them one at a time.

const FAM: String = "fam_0001"
const HUGO: String = "chr_0001"
const ARMORY: String = "bld_0003"

var cat := Catalog.load_from()


func _sim() -> Sim:
	cat.market["demand"]["drop_per_unit"] = 0.05  # the figure these checks are written with ([balance] in data/)
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 3)["state"], cat)
	sim.state.families["fam_0003"]["ai_profile"] = ""
	sim.state.clock["minute"] = 600
	var ch: Dictionary = sim.state.characters[HUGO]
	ch["location"] = ARMORY
	ch["station"] = ""
	ch["path"] = []
	ch["inventory"]["limit"] = 500.0
	Inventory.add(ch["inventory"], cat, "sword", 0, 10)
	Inventory.add(ch["inventory"], cat, "sword", 1, 10)
	return sim


func _sell(qty: int, quality: int = 0) -> Dictionary:
	return {"type": "sell", "actor": HUGO, "stall": "armory", "item": "sword", "quality": quality, "qty": qty}


func test_ten_at_once_equals_ten_of_one() -> void:
	for q: int in [0, 1]:
		var a := _sim()
		var b := _sim()
		var g0 := Money.gold(a.state, FAM)
		check(Orders.apply(a, _sell(10, q))["ok"], "sells 10 at once (q=%d)" % q)
		for i: int in 10:
			check(Orders.apply(b, _sell(1, q))["ok"], "sells 1 (q=%d, #%d)" % [q, i])
		eq(Money.gold(a.state, FAM), Money.gold(b.state, FAM), "same gold at once or one by one (q=%d)" % q)
		near(Market.demand(a, "sword"), Market.demand(b, "sword"), 0.00001,
			"same demand after (q=%d)" % q)
		check(Money.gold(a.state, FAM) - g0 < 10 * Market.price(_sim(), "sword", q, "sell"),
			"10 at once pays less than 10 × the first price (q=%d)" % q)


func test_unit_prices_and_event() -> void:
	var sim := _sim()
	var g0 := Money.gold(sim.state, FAM)
	check(Orders.apply(sim, _sell(3))["ok"], "sells 3")
	# round(65 × 0.7 × d) with d = 1, 0.95, 0.9: 46 + 43 + 41
	eq(Money.gold(sim.state, FAM) - g0, 130, "46 + 43 + 41")
	near(Market.demand(sim, "sword"), 0.85, 0.00001, "demand dropped 3 × 0.05")
	var sold: Array = sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "market_sold")
	eq([int(sold[0]["price"]), int(sold[0]["total"]), int(sold[0]["qty"])], [46, 130, 3], "price = first unit, total = sum")
	var dem: Array = sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "demand_changed")
	eq(dem.size(), 1, "one demand_changed event")
	near(float(dem[0]["demand"]), 0.85, 0.00001, "with the final demand")
	var e: Dictionary = sim.state.ledger["entries"][-1]
	eq([e["category"], int(e["amount"])], ["market_sales", 130], "one ledger entry with the sum")


func test_floor_of_demand_unit_by_unit() -> void:
	var sim := _sim()
	sim.state.market["demand"] = {"sword": 0.6}
	var g0 := Money.gold(sim.state, FAM)
	check(Orders.apply(sim, _sell(4))["ok"], "sells 4 near the minimum")
	# d = 0.6, 0.55, 0.5, 0.5: round(45.5 × d) = 27 + 25 + 23 + 23
	eq(Money.gold(sim.state, FAM) - g0, 98, "the units below the minimum pay the minimum price")
	near(Market.demand(sim, "sword"), 0.5, 0.00001, "never below the minimum")
