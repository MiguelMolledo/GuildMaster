extends "res://tests/test_case.gd"
## Viajes · the sim of the region (docs/gdd/09b_region.md §9b.6): state.region and its v16 save, the cities' markets
## (demand_city, mod_ciudad, their own events), the keyed rolls that never touch home, the regional events that cut
## routes, the AI caravans.

var cat := Catalog.load_from()


func _game(seed: int = 1) -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, seed)
	var sim := Sim.new(r["state"], cat)
	Region.ensure(sim)
	return sim


func test_the_region_holds_every_city_but_home() -> void:
	var sim := _game()
	eq(Region.home(sim), "villa", "a game on town_e is at home in the villa")
	var cities: Array = (sim.state.region["cities"] as Dictionary).keys()
	cities.sort()
	eq(cities, ["abbey", "capital", "hamlet", "port", "quarry"], "the five settlements away from home")
	for k: String in ["events", "treaties", "caravans", "contracts"]:
		eq(sim.state.region[k], [], "%s starts empty" % k)


func test_a_save_from_before_migrates_to_v16_with_an_empty_region() -> void:
	var old := SaveFile.load_file("res://data/scenarios/town_e_start.json")
	check(bool(old["ok"]), "an old scenario loads")
	var st: WorldState = old["state"]
	eq(st.version, WorldState.VERSION, "migrated to the current version")
	check(WorldState.VERSION >= 16, "travel is v16 (posada: v19 since)")
	eq(st.region, {}, "nothing travelled before: an empty region")
	var sim := Sim.new(st, cat)
	sim.step()
	check((st.region as Dictionary).has("cities"), "the first step fills the region from data/world/region.json")
	# from v14: neither the duel's root (v15) nor the region (v16); both steps chain
	var v14 := sim.state.to_dict()
	v14["version"] = 14
	v14.erase("duels")
	v14.erase("region")
	var m14 := SaveFile.migrate(v14)
	check(bool(m14["ok"]), "a v14 dictionary migrates")
	eq(int(m14["data"]["version"]), WorldState.VERSION, "to the current version")
	eq(m14["data"]["duels"], {"open": {}, "closed": []}, "14 -> 15 (duelo) adds the duels")
	eq(m14["data"]["region"], {}, "15 -> 16 (viajes) adds the region")
	var b14 := SaveFile.from_text(JSON.stringify(v14))
	check(bool(b14["ok"]), "a v14 save loads")
	eq(SaveFile.canonical(WorldState.from_dict(SaveFile.migrate(JSON.parse_string(JSON.stringify(
		(b14["state"] as WorldState).to_dict())))["data"]).to_dict()), SaveFile.canonical((b14["state"] as WorldState).to_dict()),
		"and saved again it comes back the same")
	# from v15: the duels it had stay, the region is added
	var v15 := sim.state.to_dict()
	v15["version"] = 15
	v15["duels"] = {"open": {}, "closed": [{"id": "dul_0001", "status": "closed"}]}
	v15.erase("region")
	var m := SaveFile.migrate(v15)
	check(bool(m["ok"]), "a v15 dictionary migrates")
	eq(m["data"]["region"], {}, "15 -> 16 adds the region")
	eq((m["data"]["duels"]["closed"] as Array).size(), 1, "and keeps the duels of v15")
	var b15 := SaveFile.from_text(JSON.stringify(v15))
	check(bool(b15["ok"]), "a v15 save loads")
	var again := SaveFile.from_text(JSON.stringify((b15["state"] as WorldState).to_dict()))
	eq(SaveFile.canonical((again["state"] as WorldState).to_dict()), SaveFile.canonical((b15["state"] as WorldState).to_dict()),
		"a v15 save loaded and saved comes back the same")
	eq(SaveFile.to_v16({"version": 14})["region"], {}, "to_v16 needs nothing of v15")


func test_round_trip_with_a_trip_a_caravan_and_a_treaty() -> void:
	var sim := _game()
	var st := sim.state
	var fam := SimQuery.player_family(st)
	st.families[fam]["title"] = "baron"
	Money.change(sim, fam, 500, Money.EVENTS, "test")
	var hero := str(st.families[fam]["head"])
	sim.step([{"type": "travel", "actor": hero, "to": "hamlet"}])
	(st.region["cities"]["capital"]["reputation"] as Dictionary)[fam] = 30
	Treaties._sign(sim, fam, "capital", "exemption", "", "family", hero)
	Region.drop_demand(sim, "port", "wood", 3)
	var text := JSON.stringify(st.to_dict())
	var back := SaveFile.from_text(text)
	check(bool(back["ok"]), "it loads")
	eq(SaveFile.canonical((back["state"] as WorldState).to_dict()), SaveFile.canonical(st.to_dict()),
		"what is saved is what comes back")
	var b: WorldState = back["state"]
	check(Region.is_away(b, hero), "still on the road after loading")
	eq(int((b.region["treaties"] as Array).size()), 1, "the treaty is kept")


func test_a_city_price_reads_its_demand_its_identity_and_the_season() -> void:
	var sim := _game()
	var base := float(cat.item("iron").get("base_price", 0))
	var sell := float(cat.market.get("sell_ratio", 0.7))
	var season := WorldEvents.season_mult(sim, "price", "iron")
	eq(Region.price(sim, "quarry", "iron", 0, "sell"), maxi(1, roundi(base * 0.6 * sell * season)),
		"the quarry sells iron cheap (×0.6)")
	check(Region.price(sim, "capital", "sword", 0, "sell") > Market.price(sim, "sword", 0, "sell"),
		"the capital pays more for weapons than home")
	var before := Region.price(sim, "capital", "sword", 0, "sell")
	Region.drop_demand(sim, "capital", "sword", 5)
	check(Region.price(sim, "capital", "sword", 0, "sell") < before, "selling there drops its price")
	eq(Market.demand(sim, "sword"), float(cat.market["demand"]["start"]), "and home's demand does not move")
	Region._recover_demand(sim)
	check(Region.demand(sim, "capital", "sword") > 1.0 - 5 * 0.04, "the city's demand recovers at dawn")


func test_the_region_rolls_never_touch_the_home_stream() -> void:
	var sim := _game(7)
	var st := sim.state
	var rng_before := st.rng.state
	var events_before := JSON.stringify(st.events_active)
	var market_before := JSON.stringify(st.market)
	for day: int in range(2, 30):
		Region._roll_regional(sim, day)
		for c: String in ["abbey", "capital", "hamlet", "port", "quarry"]:
			Region._roll_city_event(sim, c, day)
			CityTrade.post_offer(sim, c, day)
		Region._ai_caravans(sim, day)
		Region._end_due(sim, day * Clock.MINUTES_PER_DAY)
	eq(st.rng.state, rng_before, "state.rng untouched")
	eq(JSON.stringify(st.events_active), events_before, "home's events untouched")
	eq(JSON.stringify(st.market), market_before, "home's market untouched")


func test_the_same_seed_gives_the_same_region() -> void:
	var a := _game(3)
	var b := _game(3)
	for sim: Sim in [a, b]:
		for day: int in range(2, 20):
			for c: String in ["capital", "port"]:
				Region._roll_city_event(sim, c, day)
				CityTrade.post_offer(sim, c, day)
			Region._roll_regional(sim, day * 2)
	eq(JSON.stringify(a.state.region), JSON.stringify(b.state.region), "same seed, same cities")


func test_snow_and_flood_cut_routes_by_terrain() -> void:
	var sim := _game()
	var r := Region.ensure(sim)
	eq(Region.path(sim, "villa", "quarry"), ["r4"], "the mountain path is the way to the quarry")
	(r["events"] as Array).append({"id": "rev_9001", "def": "snow", "start": 0, "end": 99999})
	check(not Region.is_open(sim, Region.route(sim, "r4")), "snow closes the mountain path")
	check(not Region.is_open(sim, Region.route(sim, "r5")), "and the ridge")
	check(Region.is_open(sim, Region.route(sim, "r2")), "not the royal road")
	eq(Region.path(sim, "villa", "quarry"), [], "the quarry is cut off")
	(r["events"] as Array).append({"id": "rev_9002", "def": "flood", "start": 0, "end": 99999})
	eq(Region.path(sim, "villa", "capital"), ["r2"], "with the ford flooded, the royal road")


func test_the_war_cuts_its_routes_and_slows_the_rest() -> void:
	var sim := _game()
	var r1 := Region.route(sim, "r1")
	var before := Region.leg_minutes(sim, r1)
	WorldEvents.start(sim, "war")
	check(not Region.is_open(sim, Region.route(sim, "r2")), "the war closes the royal road")
	eq(Region.leg_minutes(sim, r1), roundi(before * 1.5), "and every other leg takes ×1.5")


func test_ai_caravans_drop_the_demand_of_what_they_make() -> void:
	var sim := _game(2)
	var hits := 0
	for day: int in [2, 4, 6, 8, 10, 12, 14, 16]:
		Region._ai_caravans(sim, day)
	for c: String in ["abbey", "capital", "hamlet", "port", "quarry"]:
		for item: String in (Region.city(sim, c)["demand"] as Dictionary):
			if Region.demand(sim, c, item) < 1.0:
				hits += 1
	check(hits > 0, "some AI caravan sold somewhere (%d)" % hits)


func test_an_exclusivity_keeps_the_ai_caravans_out() -> void:
	var sim := _game(2)
	var st := sim.state
	var fam := SimQuery.player_family(st)
	var rival := ""
	for f: String in st.families:
		if str(st.families[f].get("ai_profile", "")) == "rival_smith":
			rival = f
	var item := Region._product_of(sim, rival)
	check(item != "", "the AI smith has something to sell (%s)" % item)
	for c: String in ["abbey", "capital", "hamlet", "port", "quarry"]:
		(Region.ensure(sim)["treaties"] as Array).append({"id": "tre_x" + c, "kind": "exclusivity", "scope": "family",
			"city": c, "family": fam, "item": item, "qty": 0, "price": 0, "start": 0, "end": 999999, "delivered": 0})
	for day: int in [2, 4, 6, 8, 10, 12, 14, 16]:
		Region._ai_caravans(sim, day)
	for c: String in ["abbey", "capital", "hamlet", "port", "quarry"]:
		eq(Region.demand(sim, c, item), 1.0, "%s: nothing of %s unloaded by an AI caravan" % [c, item])
