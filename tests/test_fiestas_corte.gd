extends "res://tests/test_case.gd"
## Fiestas · the owner's decisions of 2026-11-05 (04f 4.25.2, 4.25.5): the town's gift chosen by the mayor among the
## pieces offered (by quality and value when nobody chooses), the marquis's audience (title, gift, Rhetoric, the
## privileges: title favour, exemption, minor office), the quality contest of the fair and the AI families' sponsoring
## (once a year, competing for each part). Their chronicle, and the pieces that go back home.

const DAY: int = 1440

var cat := Catalog.load_from()


func _game(c: Catalog = null) -> Sim:
	var k := c if c != null else cat
	var r := NewGame.from_start(k, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], k)
	sim.step()
	return sim


func _to(sim: Sim, minute: int) -> Array:
	var seen: Array = []
	while int(sim.state.clock["minute"]) < minute:
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + 1
		sim.events = []
		Festivals.step(sim)
		seen.append_array(sim.events)
	return seen


func _types(evs: Array, t: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == t)


func _rival(sim: Sim) -> String:
	for f: String in Festivals._sorted_keys(sim.state.families):
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			return f
	return ""


## The marquis on day 10 (announced on day 8 at noon).
func _marquis(sim: Sim) -> Dictionary:
	_to(sim, 8 * DAY + 11 * 60)
	var id := Festivals._schedule(sim, "marquis_visit", 10, "test")
	_to(sim, 8 * DAY + 12 * 60 + 1)
	return Festivals.find(sim, id)


func _give(sim: Sim, actor: String, item: String, q: int) -> void:
	Inventory.add(sim.state.characters[actor]["inventory"], cat, item, q, 1)


func test_the_town_gift_goes_to_the_best_piece() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var inst := _marquis(sim)
	var ai_offers := (inst.get("gift_offers", []) as Array).size()
	_give(sim, me, "decorative_sword", 2)
	var r := Orders.apply(sim, {"type": "festival_offer_gift", "actor": me, "festival": str(inst["id"])})
	check(r["ok"], "the player offers the ceremonial sword (%s)" % r["reason"])
	eq(Inventory.count(sim.state.characters[me]["inventory"], "decorative_sword", 2), 0, "the piece leaves the bag")
	eq(Orders.apply(sim, {"type": "festival_offer_gift", "actor": me, "festival": str(inst["id"])})["reason"],
		"already_offered", "one offer per family")
	var gold := Money.gold(sim.state, fam)
	var evs := _to(sim, 10 * DAY + 10 * 60 + 1)
	var chosen := _types(evs, "festival_gift_chosen")
	eq(chosen.size(), 1, "the gift is chosen at 10:00 (%d offers of the AI too)" % ai_offers)
	eq(str(chosen[0]["family"]), fam, "the excellent ceremonial sword wins")
	eq(str(chosen[0]["by"]), "best", "nobody chose: the best by quality and value")
	check(Money.gold(sim.state, fam) > gold, "the town pays it")
	check(sim.state.chronicle.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "town_gift"), "the chronicle")
	check(_types(evs, "festival_gift_offers").size() == 1, "an hour before, the mayor's call")


func test_the_mayor_chooses_and_the_rest_go_home() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	Offices.take(sim, "mayor", 0, me)
	var inst := _marquis(sim)
	var rival := _rival(sim)
	var rh := Kin.head(sim.state, rival)
	FestivalCourt.give_back(sim, inst)  # start clean: only the two offers below
	inst["gift_offers"] = []
	_give(sim, rh, "decorative_sword", 2)
	_give(sim, me, "sword", 0)
	check(Orders.apply(sim, {"type": "festival_offer_gift", "actor": rh, "festival": str(inst["id"])})["ok"], "the rival offers")
	check(Orders.apply(sim, {"type": "festival_offer_gift", "actor": me, "festival": str(inst["id"])})["ok"], "the mayor offers")
	eq(Orders.apply(sim, {"type": "festival_choose_gift", "actor": rh, "festival": str(inst["id"]), "offer": 1})["reason"],
		"not_the_mayor", "only the mayor chooses")
	check(Orders.apply(sim, {"type": "festival_choose_gift", "actor": me, "festival": str(inst["id"]), "offer": 1})["ok"],
		"the mayor chooses his own plain sword")
	var evs := _to(sim, 10 * DAY + 10 * 60 + 1)
	var chosen: Dictionary = _types(evs, "festival_gift_chosen")[0]
	eq(str(chosen["family"]), fam, "the mayor's choice rules")
	eq(str(chosen["by"]), "mayor", "chosen by the mayor")
	_to(sim, int(inst["end"]) + 1)
	eq(Inventory.count(sim.state.characters[rh]["inventory"], "decorative_sword", 2), 1, "the rival's sword comes home")


func test_the_audience_grants_a_privilege() -> void:
	var c := Catalog.load_from()
	c.festivals["rules"]["audience"]["base"] = 1.0
	c.festivals["rules"]["audience"]["max"] = 1.0
	var sim := _game(c)
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var inst := _marquis(sim)
	_give(sim, me, "sword", 1)
	eq(Orders.apply(sim, {"type": "festival_audience", "actor": me, "festival": str(inst["id"]), "privilege": "title_favour"})[
		"reason"], "title_too_low", "a commoner gets no audience")
	sim.state.families[fam]["title"] = "citizen"
	var cost := Titles.cost_of(sim, fam, "patrician")
	check(Orders.apply(sim, {"type": "festival_audience", "actor": me, "festival": str(inst["id"]),
		"privilege": "title_favour"})["ok"], "a citizen asks with a sword")
	var evs := _to(sim, 10 * DAY + 12 * 60 + 1)
	var a: Array = _types(evs, "festival_audience").filter(func(e: Dictionary) -> bool: return str(e["family"]) == fam)
	eq(str(a[0]["granted"]), "title_favour", "granted")
	eq(Titles.cost_of(sim, fam, "patrician"), roundi(cost * 0.5), "the next title costs half")
	check(sim.state.chronicle.any(func(x: Dictionary) -> bool: return str(x["kind"]) == "audience"), "the chronicle")
	eq(Inventory.count(sim.state.characters[me]["inventory"], "sword", 1), 0, "the marquis keeps the gift")


func test_the_exemption_and_a_failed_audience() -> void:
	var c := Catalog.load_from()
	c.festivals["rules"]["audience"]["base"] = 1.0
	c.festivals["rules"]["audience"]["max"] = 1.0
	var sim := _game(c)
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	sim.state.families[fam]["title"] = "citizen"
	var inst := _marquis(sim)
	_give(sim, me, "sword", 0)
	Orders.apply(sim, {"type": "festival_audience", "actor": me, "festival": str(inst["id"]), "privilege": "exemption"})
	_to(sim, 10 * DAY + 12 * 60 + 1)
	check(Treaties.exempt(sim, "capital", fam), "no tariff in Bellcaire")
	near(Region.tariff(sim, "capital", fam), 0.0, 0.0001, "the tariff is 0")
	var c2 := Catalog.load_from()
	c2.festivals["rules"]["audience"]["base"] = 0.0
	c2.festivals["rules"]["audience"]["per_rhetoric"] = 0.0
	c2.festivals["rules"]["audience"]["per_value"] = 0.0
	var s2 := _game(c2)
	var f2 := SimQuery.player_family(s2.state)
	var m2 := Kin.head(s2.state, f2)
	s2.state.families[f2]["title"] = "citizen"
	var i2 := _marquis(s2)
	_give(s2, m2, "sword", 0)
	Orders.apply(s2, {"type": "festival_audience", "actor": m2, "festival": str(i2["id"]), "privilege": "exemption"})
	var evs := _to(s2, 10 * DAY + 12 * 60 + 1)
	var a: Array = _types(evs, "festival_audience").filter(func(e: Dictionary) -> bool: return str(e["family"]) == f2)
	eq(str(a[0]["granted"]), "", "with no chance, nothing")
	check(not Treaties.exempt(s2, "capital", f2), "no exemption")


func test_the_quality_contest_of_the_fair() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	_to(sim, 2 * DAY + 12 * 60 + 1)  # the fair announced
	var inst: Dictionary = Festivals.announced(sim).filter(func(i: Dictionary) -> bool: return str(i["def"]) == "harvest_fair")[0]
	_give(sim, me, "sword", 2)
	var r := Orders.apply(sim, {"type": "festival_enter_contest", "actor": me, "festival": str(inst["id"])})
	check(r["ok"], "the player presents an excellent sword (%s)" % r["reason"])
	var gold := Money.gold(sim.state, fam)
	var evs := _to(sim, 3 * DAY + 18 * 60 + 1)
	var won := _types(evs, "festival_contest")
	eq(won.size(), 1, "judged at 18:00")
	eq(str(won[0]["family"]), fam, "the best quality wins")
	eq(Money.gold(sim.state, fam), gold + 60, "the prize")
	_to(sim, int(inst["end"]) + 1)
	eq(Inventory.count(sim.state.characters[me]["inventory"], "sword", 2), 1, "the sword comes home")
	check(sim.state.chronicle.any(func(x: Dictionary) -> bool: return str(x["kind"]) == "contest_won"), "the chronicle")


func test_the_ai_sponsors_once_a_year_and_takes_the_part() -> void:
	var sim := _game()
	var rival := _rival(sim)
	sim.state.families[rival]["gold"] = 2000
	var fam := SimQuery.player_family(sim.state)
	sim.state.families[fam]["gold"] = 2000
	var sponsored: Array = []
	for d: int in range(0, 8):
		for e: Dictionary in _to(sim, d * DAY + 12 * 60 + 2):
			if str(e["type"]) == "festival_sponsored" and str(e["family"]) == rival:
				sponsored.append(str(e["def"]))
	check(sponsored.size() <= 1, "at most once a year (%s)" % [sponsored])
	var c2 := Catalog.load_from()
	c2.festivals["rules"]["ai_sponsor"]["chance"] = 1.0
	var s2 := _game(c2)
	var r2 := _rival(s2)
	s2.state.families[r2]["gold"] = 2000
	_to(s2, 12 * 60 + 2)
	var inst: Dictionary = Festivals.announced(s2)[0]
	eq(Festivals.part_taken_by(inst, "banquet"), r2, "the rival pays the banquet of the Mayos")
	var f2 := SimQuery.player_family(s2.state)
	s2.state.families[f2]["gold"] = 2000
	eq(Festivals.order_sponsor(s2, {"actor": Kin.head(s2.state, f2), "festival": str(inst["id"]), "part": "banquet"})[
		"reason"], "part_taken", "the player arrives late for the banquet")
	check(Festivals.order_sponsor(s2, {"actor": Kin.head(s2.state, f2), "festival": str(inst["id"]), "part": "music"})["ok"],
		"the music is still free")


func test_court_fields_survive_a_save() -> void:
	var sim := _game()
	var me := Kin.head(sim.state, SimQuery.player_family(sim.state))
	var inst := _marquis(sim)
	_give(sim, me, "decorative_sword", 1)
	Orders.apply(sim, {"type": "festival_offer_gift", "actor": me, "festival": str(inst["id"])})
	var back: WorldState = SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.festivals), SaveFile.canonical(sim.state.festivals), "offers and held pieces round-trip")
