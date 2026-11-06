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
	_give(sim, me, "fine_clothes", 2)
	eq(Orders.apply(sim, {"type": "festival_enter_contest", "actor": me, "festival": str(inst["id"]), "item": "fine_clothes"})[
		"reason"], "no_piece", "a smith presents a piece of his own trade, not a tailor's")
	_give(sim, me, "sword", 2)
	var r := Orders.apply(sim, {"type": "festival_enter_contest", "actor": me, "festival": str(inst["id"])})
	check(r["ok"], "the player presents an excellent sword (%s)" % r["reason"])
	var rep := Reputation.of(sim.state, fam)
	var fame := Reputation.class_mod(sim.state, fam, "artisan")
	var evs := _to(sim, 3 * DAY + 18 * 60 + 1)
	var won := _types(evs, "festival_contest")
	eq(won.size(), 1, "judged at 18:00")
	eq(str(won[0]["family"]), fam, "the best quality wins")
	eq(Reputation.of(sim.state, fam), rep + 6, "reputation +6")
	eq(Reputation.class_mod(sim.state, fam, "artisan"), fame + 10, "fame among the artisans +10")
	var won_at := 0
	for b: String in sim.state.buildings:
		won_at += int(sim.state.buildings[b].get("contests_won", 0))
	eq(won_at, 1, "a contest won on the workshop (the workshop's fame of 04g will count it)")
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
	check(Notices.list(s2, f2).any(func(n: Dictionary) -> bool: return str(n.get("key", "")) == "notice.festival_ai_sponsored"),
		"the player sees the rival's sponsoring")
	var rg := Money.gold(s2.state, r2)
	var pg := Money.gold(s2.state, f2)
	var price := Festivals.bid_price(s2, inst, "banquet")
	eq(price, 90, "a bid: ×1,5 of the 60 the rival paid")
	var b := Festivals.order_sponsor(s2, {"actor": Kin.head(s2.state, f2), "festival": str(inst["id"]), "part": "banquet",
		"bid": true})
	check(b["ok"], "the player outbids the rival (%s)" % b["reason"])
	eq(Festivals.part_taken_by(inst, "banquet"), f2, "the banquet is the player's")
	eq(Money.gold(s2.state, f2), pg - 90, "it paid 90")
	eq(Money.gold(s2.state, r2), rg + 60, "the rival gets its 60 back")


func test_court_fields_survive_a_save() -> void:
	var sim := _game()
	var me := Kin.head(sim.state, SimQuery.player_family(sim.state))
	var inst := _marquis(sim)
	_give(sim, me, "decorative_sword", 1)
	Orders.apply(sim, {"type": "festival_offer_gift", "actor": me, "festival": str(inst["id"])})
	var back: WorldState = SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.festivals), SaveFile.canonical(sim.state.festivals), "offers and held pieces round-trip")


## The fair's pens at the outskirts; where they do not fit, the cattle at stalls and the chronicle says so.
func test_the_cattle_goes_to_the_outskirts_or_to_stalls() -> void:
	var sim := _game()
	check(FestivalGround.fits(cat, "town_e", Vector2i(3, 3), 2), "two 3x3 pens fit by the gates of town_e")
	_to(sim, 3 * DAY + 60)
	var fair: Dictionary = Festivals.active(sim).filter(func(i: Dictionary) -> bool: return str(i["def"]) == "harvest_fair")[0]
	eq(str(fair.get("cattle", "")), "pens", "town_e: pens at the outskirts")
	check(Festivals.view_of(sim, fair)["decor"].any(func(d: Dictionary) -> bool:
		return str(d["prop"]) == "pen" and str(d["where"]) == "outskirts"), "the view puts them there")
	var c := Catalog.load_from()
	c.festivals["rules"]["view_sites"]["outskirts"]["radius"] = 0
	var s2 := _game(c)
	_to(s2, 3 * DAY + 60)
	var f2: Dictionary = Festivals.active(s2).filter(func(i: Dictionary) -> bool: return str(i["def"]) == "harvest_fair")[0]
	eq(str(f2.get("cattle", "")), "stalls", "no room by the gates: the cattle at stalls")
	check((f2["stalls"] as Array).any(func(x: Dictionary) -> bool: return str(x["stall"]) == "cattle"), "a cattle stall")
	check(s2.state.chronicle.any(func(x: Dictionary) -> bool: return str(x["kind"]) == "fair_cattle_stalls"), "the chronicle says so")
	check(not Festivals.view_of(s2, f2)["decor"].any(func(d: Dictionary) -> bool: return str(d["prop"]) == "pen"),
		"no pens in the view: stalls instead")


## One pen is enough (manager, 2026-11-06): in Vilablat (region_hamlet) only one of the fair's two pens fits by its
## gates. The sim keeps «pens» with one, the rest of the cattle goes to one stall in the plaza, the chronicle says so
## (fair_cattle_pens_short, never «no pens»); the view puts that one pen at the outskirts and one fair stall.
func test_one_pen_is_enough_in_vilablat() -> void:
	check(FestivalGround.fits(cat, "region_hamlet", Vector2i(3, 3), 1), "Vilablat: one 3x3 pen fits by a gate")
	check(not FestivalGround.fits(cat, "region_hamlet", Vector2i(3, 3), 2), "but not two")
	var st0 := WorldState.new()
	st0.map_id = "region_hamlet"
	var vs := FestivalLayer.sites(st0, cat)
	var meadow := {}
	for t: Vector2i in (vs["_meadow"] as Array):
		meadow[t] = true
	var view_fits := false
	for t: Vector2i in (vs["outskirts"] as Array):
		var ok := true
		for dy: int in 3:
			for dx: int in 3:
				ok = ok and meadow.has(t + Vector2i(dx, dy))
		view_fits = view_fits or ok
	check(view_fits, "the view finds the same room for it")
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed", "city": "hamlet"}, 1)
	check(bool(r.get("ok", false)), "a new game in Vilablat (%s)" % r.get("error", ""))
	if not bool(r.get("ok", false)):
		return
	var sim := Sim.new(r["state"], cat)
	sim.step()
	eq(sim.state.map_id, "region_hamlet", "in Vilablat")
	_to(sim, 3 * DAY + 60)
	var fairs: Array = Festivals.active(sim).filter(func(i: Dictionary) -> bool: return str(i["def"]) == "harvest_fair")
	check(not fairs.is_empty(), "the harvest fair is on")
	if fairs.is_empty():
		return
	var fair: Dictionary = fairs[0]
	eq(str(fair.get("cattle", "")), "pens", "one pen is enough: pens")
	eq(int(fair.get("cattle_pens", 0)), 1, "one of two")
	check((fair["stalls"] as Array).any(func(x: Dictionary) -> bool: return str(x["stall"]) == "cattle"),
		"the rest of the cattle at a stall")
	var short: Array = sim.state.chronicle.filter(func(x: Dictionary) -> bool: return str(x["kind"]) == "fair_cattle_pens_short")
	eq(short.size(), 1, "the chronicle says only one pen fit")
	if not short.is_empty():
		eq([int(short[0].get("pens", 0)), int(short[0].get("wanted", 0))], [1, 2], "one of the two")
	check(not sim.state.chronicle.any(func(x: Dictionary) -> bool: return str(x["kind"]) == "fair_cattle_stalls"),
		"not «no pens»")
	var decor: Array = Festivals.view_of(sim, fair)["decor"]
	var pens: Array = decor.filter(func(d: Dictionary) -> bool: return str(d["prop"]) == "pen")
	eq(pens.size(), 1, "the view puts the pens")
	if not pens.is_empty():
		eq([str(pens[0]["where"]), int(pens[0]["count"])], ["outskirts", 1], "one, at the outskirts")
	check(decor.any(func(d: Dictionary) -> bool:
		return str(d["prop"]) == "fair_stall" and str(d["where"]) == "plaza_ring" and int(d["count"]) == 1),
		"and one cattle stall in the plaza")
	var home := _game()  # Vilarrasa (town_e) keeps its two pens and no chronicle line
	_to(home, 3 * DAY + 60)
	var hf: Dictionary = Festivals.active(home).filter(func(i: Dictionary) -> bool: return str(i["def"]) == "harvest_fair")[0]
	eq(int(hf.get("cattle_pens", 0)), 2, "Vilarrasa: both pens")
	check(not (hf["stalls"] as Array).any(func(x: Dictionary) -> bool: return str(x["stall"]) == "cattle"), "no cattle stall")
	check(not home.state.chronicle.any(func(x: Dictionary) -> bool:
		return str(x["kind"]) in ["fair_cattle_pens_short", "fair_cattle_stalls"]), "nor a line in the chronicle")
