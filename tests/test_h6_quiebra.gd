extends "res://tests/test_case.gd"
## H6 · the bankruptcy of an AI family (docs/gdd/04c_ia_rival.md §4.21.6.3, Q9 b; Bankruptcy): austerity, the «Se
## vende» sign that anybody may buy at its price, the closure when nobody does, the fall («venida a menos»: its adults
## can be hired, they lodge in a house, it puts up a workshop again) and the recovery. Only on the maps of the AI's
## economy: here the tests turn it on for Vilarrasa (construction.json bankruptcy.maps).

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL: String = "fam_0002"

var cat := Catalog.load_from()


func _new(on: bool = true) -> Sim:
	cat.construction["bankruptcy"]["maps"] = ["town_e"] if on else []
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)


func _off() -> void:
	cat.construction["bankruptcy"].erase("maps")


## The dawn of `day` as the sim sees it (the bankruptcy is looked at then).
func _dawn(sim: Sim, day: int) -> void:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + 360
	sim.events = [{"type": "phase_changed", "phase": "dawn"}]
	Bankruptcy.step(sim)


func _forge(sim: Sim) -> String:
	return Bankruptcy.workshop_of(sim, RIVAL)


func test_austerity_then_the_sign_and_the_player_buys_it() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["gold"] = 0
	var forge := _forge(sim)
	_dawn(sim, 10)
	eq(Bankruptcy.stage(sim, RIVAL), Bankruptcy.AUSTERITY, "under its reserve: austerity")
	eq(Construction.choose(sim, RIVAL), {}, "it builds nothing in austerity")
	_dawn(sim, 11)
	eq(Bankruptcy.stage(sim, RIVAL), Bankruptcy.AUSTERITY, "a season lasts")
	_dawn(sim, 12)
	eq(Bankruptcy.stage(sim, RIVAL), Bankruptcy.FOR_SALE, "not recovered: the «Se vende» sign")
	var b: Dictionary = sim.state.buildings[forge]
	check(bool(b.get("for_sale", false)), "the building is for sale")
	eq(int(b["sale_price"]), roundi(100.0 * 0.8), "(cost + upgrades) × 0.8")
	var heard := sim.state.notices.any(func(n: Dictionary) -> bool:
		return str(n["family"]) == FAM and str(n["key"]) == "notice.plots.ai_for_sale")
	check(heard, "the player hears of it")
	var head := Kin.head(sim.state, RIVAL)
	Emotions.change_relation(sim, head, HERO, -90 - Emotions.relation(sim.state, head, HERO), "test")
	sim.state.families[FAM]["gold"] = 1000
	sim.state.families[FAM]["title"] = "citizen"
	var r := Plots.can_buy_from(sim, HERO, forge)
	check(r["ok"], "the sign is public: even a family it hates may buy: %s" % r)
	eq(int(r.get("price", 0)), int(b["sale_price"]), "at the sign's price")
	check(Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": forge})["ok"], "bought with buy_building")
	_dawn(sim, 13)
	check(sim.state.families[RIVAL].has("fallen"), "no business left: venida a menos")
	eq(str(sim.state.families[RIVAL]["after_sale"]["fate"]), "rebuilds", "it will put up a workshop again")
	_off()


func test_nobody_buys_it_so_it_is_pulled_down_and_the_family_falls() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["gold"] = 0
	var forge := _forge(sim)
	var plot := Plots.plot_of(sim, forge)
	for d: int in [10, 12, 14]:
		_dawn(sim, d)
	check(not sim.state.buildings.has(forge), "unsold a season: pulled down")
	eq(str(Plots.get_plot(sim, plot)["kind"]), "lot", "its plot is a free lot again")
	eq(int(sim.state.families[RIVAL]["gold"]), roundi(100.0 * 0.4), "40 % of its cost back")
	check(sim.state.families[RIVAL].has("fallen"), "venida a menos")
	var head := Kin.head(sim.state, RIVAL)
	check(Staff.is_unemployed(sim, head), "its head can be hired now (Q9 b)")
	check(str(sim.state.characters[head].get("rank", "")) != "", "with a rank")
	var home := str(sim.state.characters[head].get("home", ""))
	check(home != "" and str(sim.state.buildings[home]["type"]) == "house", "it lodges in a house of the town")
	check(Buildings.can_enter(sim, head, home)["ok"], "and may go into it")
	eq(Titles.current(sim, RIVAL), "common", "it keeps its title")
	_off()


func test_a_fallen_family_with_gold_puts_up_a_workshop_again() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["gold"] = 0
	for d: int in [10, 12, 14]:
		_dawn(sim, d)
	cat.construction["valve"]["min_free"] = 0
	sim.state.families[RIVAL]["gold"] = 600
	var c := Construction.choose(sim, RIVAL)
	eq(str(c.get("building_type", "")), "forge", "it builds a forge again: %s" % c)
	check(Orders.apply(sim, Construction.order_for(sim, RIVAL, c))["ok"], "the order is taken")
	var bld := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b]["owner"]) == RIVAL and str(sim.state.buildings[b]["state"]) == "construction":
			bld = b
	sim.state.buildings[bld]["construction"]["end"] = int(sim.state.clock["minute"]) + 1
	sim.step([])
	sim.step([])
	check(not sim.state.families[RIVAL].has("fallen"), "with its workshop it is no longer fallen")
	cat.construction["valve"]["min_free"] = 2
	_off()


func test_it_recovers_when_the_money_comes_back() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["gold"] = 0
	_dawn(sim, 10)
	eq(Bankruptcy.stage(sim, RIVAL), Bankruptcy.AUSTERITY, "austerity")
	sim.state.families[RIVAL]["gold"] = 800
	_dawn(sim, 12)
	eq(Bankruptcy.stage(sim, RIVAL), Bankruptcy.NORMAL, "gold over its reserve and no loss: back to normal")
	check(not bool(sim.state.buildings[_forge(sim)].get("for_sale", false)), "no sign")
	_off()


func test_nothing_off_the_economy_maps() -> void:
	var sim := _new(false)
	sim.state.families[RIVAL]["gold"] = 0
	for d: int in [10, 12, 14]:
		_dawn(sim, d)
	eq(Bankruptcy.stage(sim, RIVAL), Bankruptcy.NORMAL, "Vilarrasa (not an economy map): nothing")
	check(sim.state.buildings.has(_forge(sim)), "its forge stands")
	_off()
