extends "res://tests/test_case.gd"
## Equilibrio 5 (docs/decisiones.json; GDD 4.19): the pecha, a progressive tax on wealth at the close of each year.

const FAM: String = "fam_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	for id: String in sim.state.loans:
		sim.state.loans[id]["state"] = Loans.PAID
		sim.state.loans[id]["outstanding"] = 0
	sim.state.buildings[FORGE]["inventory"]["stacks"] = []
	return sim


func _set_gold(sim: Sim, g: int) -> void:
	Money.change(sim, FAM, g - Money.gold(sim.state, FAM), Money.EVENTS, "test")


## Runs until the year changes (the close of year 0: the dawn of day 8).
func _close_year(sim: Sim) -> Array:
	var all: Array = []
	sim.state.clock["minute"] = Clock.days_per_year(cat.time) * Clock.MINUTES_PER_DAY - 2
	for i: int in 4:
		all.append_array(sim.step())
	return all


func test_brackets_are_marginal() -> void:
	var sim := _sim()
	eq(Pecha.due(sim, 900), 0, "under 1000, nothing")
	eq(Pecha.due(sim, 2000), 40, "4 % of the 1000 above 1000")
	eq(Pecha.due(sim, 5000), 80 + 160, "4 % of 2000 + 8 % of 2000")
	eq(Pecha.due(sim, 20000), 80 + 560 + 1200, "and 12 % over 10000")


func test_charged_at_the_close_of_the_year() -> void:
	var sim := _sim()
	_set_gold(sim, 2000)
	var ev := _close_year(sim)
	var paid := ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "pecha_paid" and str(e["family"]) == FAM)
	eq(paid.size(), 1, "once, at the year change")
	eq(int(paid[0]["amount"]), 40, "on 2000 of wealth")
	check(Money.gold(sim.state, FAM) <= 1960, "paid from the gold (%d)" % Money.gold(sim.state, FAM))
	var log: Array = sim.state.families[FAM].get("pecha_log", [])
	eq(int(log[-1]["year"]), 0, "logged for year 0")


func test_poor_families_pay_nothing() -> void:
	var sim := _sim()
	_set_gold(sim, 300)
	var ev := _close_year(sim)
	eq(ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "pecha_paid" and str(e["family"]) == FAM).size(), 0,
		"300 of wealth pays no pecha")


func test_goods_count_and_the_rest_is_owed() -> void:
	var sim := _sim()
	_set_gold(sim, 40)
	Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, "sword", 2, 40)
	var w := Pecha.wealth_of(sim, FAM)
	check(w > 1500, "the goods are wealth (%d)" % w)
	_close_year(sim)
	var owed := 0
	for id: String in Loans.of_family(sim, FAM):
		owed += int(sim.state.loans[id]["outstanding"])
	check(owed > 0, "what the gold does not cover is owed to the town (%d)" % owed)
	check(Money.gold(sim.state, FAM) >= 0, "never negative")
