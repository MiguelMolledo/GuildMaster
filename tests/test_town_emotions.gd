extends "res://tests/test_case.gd"
## H7 · emotional states (GDD 4.11.5, docs/contratos/h7_ciudad.md): angry raises the prices of its stall (and refuses
## over 80), grateful lowers them, incompatible states replace each other, at most 2 towards a source, they fade and
## leave a residue, employees work better or worse, offended blocks courtship (H8).

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _sim(id: String, s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


## The hero at the food stall (its service tile) during the day.
func _at_food_stall(sim: Sim) -> void:
	var st := sim.state
	st.clock["minute"] = Clock.MINUTES_PER_DAY + 10 * 60
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["position"] = (cat.maps()["town_e"]["stalls"]["food"]["service"] as Array).duplicate()
	st.characters[HERO]["path"] = []


func test_angry_keeper_raises_prices() -> void:
	var sim := _sim("plaza_dusk")
	_at_food_stall(sim)
	var keeper := TownLife.stall_keeper(sim.state, cat, "food")
	check(keeper != "", "the food stall has a keeper")
	var base := Market.trade_price(sim, HERO, "food", "bread", 0, "buy")
	eq(base, Market.price(sim, "bread", 0, "buy"), "no emotion: the market price")
	var e := Emotions.add(sim, keeper, "angry", FAM)
	e["start"] = int(sim.state.clock["minute"]) - int(e["duration"]) / 2  # half faded: intensity 50, under 80
	var angry := Market.trade_price(sim, HERO, "food", "bread", 0, "buy")
	eq(angry, roundi(base * 1.25), "angry: +25 % buying (4.11.5)")
	check(Market.trade_price(sim, HERO, "food", "bread", 0, "sell") <= roundi(Market.price(sim, "bread", 0, "sell") * 0.75) + 1,
		"angry: −25 % selling")
	var gold := Money.gold(sim.state, FAM)
	var r := Orders.apply(sim, {"type": "buy", "actor": HERO, "stall": "food", "item": "bread", "quality": 0, "qty": 2})
	check(r["ok"], "buys from the angry keeper (%s)" % r["reason"])
	eq(gold - Money.gold(sim.state, FAM), angry * 2, "and pays the angry price")
	var other := _sim("plaza_dusk")
	_at_food_stall(other)
	Emotions.add(other, TownLife.stall_keeper(other.state, cat, "materials"), "angry", FAM)
	eq(Market.trade_price(other, HERO, "food", "bread", 0, "buy"), base, "another stall's keeper does not touch this one")


func test_very_angry_keeper_refuses_to_trade() -> void:
	var sim := _sim("plaza_dusk")
	_at_food_stall(sim)
	Emotions.add(sim, TownLife.stall_keeper(sim.state, cat, "food"), "angry", FAM)
	var r := Orders.apply(sim, {"type": "buy", "actor": HERO, "stall": "food", "item": "bread", "quality": 0, "qty": 1})
	eq(r["reason"], "vendor_refuses", "intensity 100 > 80: no trade")
	check(Emotions.refuses_trade(sim, TownLife.stall_keeper(sim.state, cat, "food"), FAM), "refuses_trade")


func test_grateful_lowers_and_incompatible_replace() -> void:
	var sim := _sim("plaza_dusk")
	_at_food_stall(sim)
	var keeper := TownLife.stall_keeper(sim.state, cat, "food")
	var base := Market.price(sim, "bread", 0, "buy")
	Emotions.add(sim, keeper, "grateful", FAM)
	eq(Market.trade_price(sim, HERO, "food", "bread", 0, "buy"), roundi(base * 0.9), "grateful: −10 %")
	Emotions.add(sim, keeper, "angry", FAM)
	var states: Array = Emotions.active(sim, keeper, FAM).map(func(x: Dictionary) -> String: return str(x["state"]))
	eq(states, ["angry"], "angry replaces grateful (incompatible, the newest wins)")
	Emotions.add(sim, keeper, "offended", FAM)
	Emotions.add(sim, keeper, "scared", FAM)
	eq(Emotions.active(sim, keeper, FAM).size(), 2, "at most 2 towards the same source")
	Emotions.add(sim, keeper, "offended", "fam_0003")
	eq(Emotions.active(sim, keeper).size(), 3, "another family is another source")


func test_emotions_fade_and_leave_a_residue() -> void:
	var sim := _sim("plaza_dusk")
	var npc := TownLife.stall_keeper(sim.state, cat, "food")
	var e := Emotions.add(sim, npc, "offended", FAM)
	var days := float(e["duration"]) / Clock.MINUTES_PER_DAY
	check(days >= 1.0 and days <= 2.0, "offended lasts 1-2 days (%.2f)" % days)
	near(Emotions.intensity(sim, e), 100.0, 0.01, "starts at 100")
	sim.state.clock["minute"] = int(e["start"]) + int(e["duration"]) / 2
	near(Emotions.intensity(sim, e), 50.0, 1.0, "half way: 50")
	var rel0 := Emotions.relation(sim.state, HERO, npc)
	sim.state.clock["minute"] = int(e["start"]) + int(e["duration"]) - 1
	sim.state.clock["minute"] = (int(sim.state.clock["minute"]) / 60 + 1) * 60 - 1
	sim.step()
	eq(Emotions.active(sim, npc, FAM).size(), 0, "gone when it reaches 0")
	eq(Emotions.relation(sim.state, HERO, npc), rel0 - 3, "an unforgiven offence leaves −3 (4.11.5)")
	check(not sim.state.emotions.has(npc), "the list is cleaned")


func test_employee_efficiency_follows_emotions() -> void:
	var sim := _sim("town_microevents")
	var emp: String = Staff.employees_of(sim.state, "bld_0001")[0]
	var base := Staff.efficiency(sim, emp)
	Emotions.add(sim, emp, "angry", FAM)
	near(Staff.efficiency(sim, emp), base * 0.8, 0.0001, "angry employee −20 %")
	Emotions.add(sim, emp, "grateful", FAM)
	near(Staff.efficiency(sim, emp), base * 1.1, 0.0001, "grateful employee +10 %")


func test_offended_blocks_courtship() -> void:
	var sim := _sim("courtship")
	var agnes := ""
	for id: String in sim.state.characters:
		if str(sim.state.characters[id]["name"]) == "Agnès" and TownLife.is_townsperson(sim.state, id):
			agnes = id
	check(agnes != "", "Agnès")
	Emotions.add(sim, agnes, "offended", FAM)
	eq(Courtship.status(sim, HERO, agnes), "offended", "offended (H7) blocks court_talk (H8)")
