extends "res://tests/test_case.gd"
## Viajes · the orders (docs/gdd/09b_region.md §9b.5): travel and return (title, way, toll, escort, ambush, away),
## the city market (tariff, quota), the city contracts, caravans (cart, carter, cargo, min price, shopping list) and
## the treaties (family and town, the council's vote, the season count, breach).

var cat := Catalog.load_from()


func _game(title: String = "citizen", gold: int = 500, seed: int = 1) -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, seed)
	var sim := Sim.new(r["state"], cat)
	Region.ensure(sim)
	var fam := SimQuery.player_family(sim.state)
	sim.state.families[fam]["title"] = title
	Money.change(sim, fam, gold, Money.EVENTS, "test")
	return sim


func _hero(sim: Sim) -> String:
	return str(sim.state.families[SimQuery.player_family(sim.state)]["head"])


func _until(sim: Sim, cond: Callable, max_minutes: int = 3000) -> bool:
	for i: int in max_minutes:
		if bool(cond.call()):
			return true
		sim.step()
	return bool(cond.call())


func test_travelling_needs_the_citizen_title() -> void:
	var sim := _game("common")
	var r := Orders.apply(sim, {"type": "travel", "actor": _hero(sim), "to": "capital"})
	eq(str(r["reason"]), "title_needed", "a commoner does not travel")
	sim.state.families[SimQuery.player_family(sim.state)]["title"] = "citizen"
	check(bool(Orders.apply(sim, {"type": "travel", "actor": _hero(sim), "to": "capital"})["ok"]), "a citizen does")


func test_a_trip_there_and_back() -> void:
	var sim := _game()
	var st := sim.state
	var hero := _hero(sim)
	var fam := SimQuery.player_family(st)
	sim.step([{"type": "travel", "actor": hero, "to": "capital"}])
	check(Region.is_away(st, hero), "away")
	eq(Travel.trip(st, hero)["path"], ["r1", "r7"], "by the hamlet and the ford (7 h) before the royal road (8 h)")
	sim.step([{"type": "move_to", "actor": hero, "tile": [5, 5]}])
	check(sim.events.any(func(e: Dictionary) -> bool: return e["type"] == "order_refused" and e["reason"] == "away"),
		"no orders of the town while away")
	check(not Needs.tracked(sim, hero), "no needs while away")
	check(_until(sim, func() -> bool: return Travel.in_city(st, hero) == "capital"), "arrives")
	var minutes := int(st.clock["minute"]) - int(Travel.trip(st, hero)["since"])
	check(absi(minutes - 7 * 60) <= 2, "in 7 hours (%d min)" % minutes)
	var g := Money.gold(st, fam)
	sim.step([{"type": "return", "actor": hero}])
	check(_until(sim, func() -> bool: return not Region.is_away(st, hero)), "comes back")
	eq(st.characters[hero]["position"], Region.gate_tile(sim), "at the gate")
	eq(Money.gold(st, fam), g - 1, "the ford's toll (1) on the way back")


func test_the_escort_costs_and_the_ambush_takes_the_cargo() -> void:
	var sim := _game()
	var st := sim.state
	var hero := _hero(sim)
	sim.catalog.trade["travel"]["ambush_per_risk"] = 1.0  # every leg with risk >= 1 is ambushed
	Inventory.add(st.characters[hero]["inventory"], cat, "sword", 0, 3)
	var fam := SimQuery.player_family(st)
	var g := Money.gold(st, fam)
	sim.step([{"type": "travel", "actor": hero, "to": "hamlet", "escort": true}])
	eq(Money.gold(st, fam), g - 20, "the escort of the first leg (20)")
	check(_until(sim, func() -> bool: return Travel.in_city(st, hero) == "hamlet"), "arrives")
	eq(Inventory.count(st.characters[hero]["inventory"], "sword"), 0, "the bandits took the swords")
	check(Kin.alive(st, hero), "no wound (the health of 4.22 is not there yet)")
	sim.catalog.trade["travel"]["ambush_per_risk"] = 0.04


func test_a_cut_way_cannot_be_taken() -> void:
	var sim := _game()
	(Region.ensure(sim)["events"] as Array).append({"id": "rev_1", "def": "snow", "start": 0, "end": 999999})
	eq(str(Orders.apply(sim, {"type": "travel", "actor": _hero(sim), "to": "quarry"})["reason"]), "no_open_route",
		"snow: no way to the quarry")


func test_selling_in_a_city_pays_its_tariff_and_an_exemption_lifts_it() -> void:
	var sim := _game("patrician")
	var st := sim.state
	var hero := _hero(sim)
	var fam := SimQuery.player_family(st)
	sim.step([{"type": "travel", "actor": hero, "to": "capital"}])
	_until(sim, func() -> bool: return Travel.in_city(st, hero) == "capital")
	Inventory.add(st.characters[hero]["inventory"], cat, "sword", 0, 2)
	var gross := Region.price(sim, "capital", "sword", 0, "sell")
	var g := Money.gold(st, fam)
	sim.step([{"type": "city_sell", "actor": hero, "item": "sword", "quality": 0, "qty": 1}])
	eq(Money.gold(st, fam), g + gross - roundi(gross * 0.1), "10 % tariff in the capital")
	(st.region["cities"]["capital"]["reputation"] as Dictionary)[fam] = 25
	sim.step([{"type": "sign_treaty", "actor": hero, "kind": "exemption"}])
	check(Treaties.exempt(sim, "capital", fam), "the exemption is signed")
	g = Money.gold(st, fam)
	gross = Region.price(sim, "capital", "sword", 0, "sell")
	sim.step([{"type": "city_sell", "actor": hero, "item": "sword", "quality": 0, "qty": 1}])
	eq(Money.gold(st, fam), g + gross, "no tariff with the exemption")


func test_a_quota_is_paid_at_its_price_and_breaks_if_short() -> void:
	var sim := _game()
	var st := sim.state
	var hero := _hero(sim)
	var fam := SimQuery.player_family(st)
	sim.step([{"type": "travel", "actor": hero, "to": "hamlet"}])
	_until(sim, func() -> bool: return Travel.in_city(st, hero) == "hamlet")
	eq(str(Orders.apply(sim, {"type": "sign_treaty", "actor": hero, "kind": "quota", "item": "hoe"})["reason"]),
		"reputation_needed", "a quota needs reputation there (5)")
	(st.region["cities"]["hamlet"]["reputation"] as Dictionary)[fam] = 10
	check(bool(Orders.apply(sim, {"type": "sign_treaty", "actor": hero, "kind": "quota", "item": "hoe"})["ok"]),
		"signed: the hamlet pays well for hoes")
	var t := Treaties.quota_of(sim, "hamlet", fam, "hoe")
	Inventory.add(st.characters[hero]["inventory"], cat, "hoe", 0, 1)
	var g := Money.gold(st, fam)
	Orders.apply(sim, {"type": "city_sell", "actor": hero, "item": "hoe", "quality": 0, "qty": 1})
	eq(Money.gold(st, fam), g + int(t["price"]), "the quota's fixed price, no tariff")
	var first := int(t["first"])
	Treaties.season(sim, Clock.day(first))
	check(not Treaties.quota_of(sim, "hamlet", fam, "hoe").is_empty(), "the season it was signed in is not counted")
	var rep := Region.reputation(sim, "hamlet", fam)
	Treaties.season(sim, Clock.day(first) + 2)
	check(Treaties.quota_of(sim, "hamlet", fam, "hoe").is_empty(), "1 of 4 hoes: broken")
	eq(Region.reputation(sim, "hamlet", fam), rep - 10, "and its reputation there drops")


func test_the_mayors_treaty_goes_through_the_council() -> void:
	var sim := _game("patrician")
	var st := sim.state
	var hero := _hero(sim)
	var fam := SimQuery.player_family(st)
	eq(str(Orders.apply(sim, {"type": "propose_town_treaty", "actor": hero, "city": "port", "kind": "exemption"})["reason"]),
		"not_the_mayor", "only the Mayor")
	Offices.take(sim, "mayor", 0, hero)
	var v := Treaties.council_vote(sim, hero)
	var r := Orders.apply(sim, {"type": "propose_town_treaty", "actor": hero, "city": "port", "kind": "exemption"})
	eq(bool(r["ok"]), bool(v["passed"]), "the vote decides (%s)" % [v])
	if bool(r["ok"]):
		var other := ""
		for f: String in st.families:
			if f != fam:
				other = f
				break
		check(Treaties.exempt(sim, "port", other), "a town treaty covers every family of home")


func test_a_caravan_goes_sells_buys_and_comes_back() -> void:
	var sim := _game("citizen", 800)
	var st := sim.state
	var hero := _hero(sim)
	var fam := SimQuery.player_family(st)
	var forge := ""
	for b: String in st.buildings:
		if str(st.buildings[b]["owner"]) == fam and str(st.buildings[b]["type"]) == "forge":
			forge = b
	var driver := ""
	for c: String in st.characters:
		if str(st.characters[c].get("family", "")) != fam and str(st.characters[c].get("rank", "")) != "" \
				and not st.characters[c].get("job") is Dictionary and Kin.is_adult(sim, c):
			driver = c
			break
	st.characters[driver]["job"] = {"building": forge, "role": "anvil", "start_day": 0, "end_day": -1, "loyalty": 50,
		"days_worked": 0, "hired_day": 0, "promotion_offered": false, "rank_days": 0, "unpaid_days": 0}
	Inventory.add(st.buildings[forge]["inventory"], cat, "sword", 0, 3)
	var send := {"type": "caravan_send", "actor": hero, "driver": driver, "building": forge, "city": "capital",
		"cargo": [{"item": "sword", "quality": 0, "qty": 3, "min_price": 1}], "buy": [{"item": "cloth", "qty": 2, "max_price": 0}]}
	eq(str(Orders.apply(sim, send)["reason"]), "no_free_cart", "a cart first")
	check(bool(Orders.apply(sim, {"type": "buy_cart", "actor": hero})["ok"]), "buys a cart")
	eq(Caravans.carts(sim, fam), 1, "one cart")
	check(bool(Orders.apply(sim, send)["ok"]), "the caravan leaves")
	check(Region.is_away(st, driver), "the carter is away")
	eq(Inventory.count(st.buildings[forge]["inventory"], "sword"), 0, "the swords left the forge")
	var stats: Dictionary = st.region["stats"]
	check(_until(sim, func() -> bool: return int(stats.get(fam, {}).get("caravans_back", 0)) >= 1, 4000), "it comes back")
	check(int(stats[fam].get("city_sales_units", 0)) + int(stats[fam].get("caravan_ambushes", 0)) > 0,
		"it sold the swords there (or was robbed)")
	check(not Region.is_away(st, driver), "the carter is back")
	eq(Caravans.busy_carts(sim, fam), 0, "the cart is free")


func test_a_city_contract_is_taken_and_delivered_there() -> void:
	var sim := _game()
	var st := sim.state
	var hero := _hero(sim)
	var fam := SimQuery.player_family(st)
	var board: Array = st.region["cities"]["hamlet"]["board"]
	board.append({"id": "rct_9001", "item": "hoe", "qty": 2, "reward": 50, "days": 3})
	sim.step([{"type": "travel", "actor": hero, "to": "hamlet"}])
	_until(sim, func() -> bool: return Travel.in_city(st, hero) == "hamlet")
	check(bool(Orders.apply(sim, {"type": "city_accept", "actor": hero, "contract": "rct_9001"})["ok"]), "accepted")
	eq(str(Orders.apply(sim, {"type": "city_deliver", "actor": hero, "contract": "rct_9001"})["reason"]), "not_enough",
		"without the hoes")
	Inventory.add(st.characters[hero]["inventory"], cat, "hoe", 0, 2)
	var g := Money.gold(st, fam)
	check(bool(Orders.apply(sim, {"type": "city_deliver", "actor": hero, "contract": "rct_9001"})["ok"]), "delivered")
	eq(Money.gold(st, fam), g + 50, "paid")
	eq(Region.reputation(sim, "hamlet", fam), 3, "reputation there +3")
