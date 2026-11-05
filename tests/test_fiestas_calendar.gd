extends "res://tests/test_case.gd"
## Fiestas (docs/gdd/04f_vida_y_fiestas.md 4.25): the calendar of the year (the eight fixed feasts, the crier the day
## before and its contracts, the variable ones by roll and by wedding), the sim effects (demand, price, counter
## customers, the holy day, the feria franca, the hooks of the other blocks), sponsoring and the mayor's
## organize_festival, the other cities' feasts and fairs (tariff, demand, toll), the festival contracts as a race with a
## single winner, the switch (off = nothing changes) and the save (round trip and v16 -> v18).

const DAY: int = 1440

var cat := Catalog.load_from()


func _game(seed: int = 1) -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, seed)
	var sim := Sim.new(r["state"], cat)
	sim.step()  # the government is handed out at the first step
	return sim


## Runs only the festivals' step minute by minute up to `minute` (fast: the calendar needs no other system).
func _fest_to(sim: Sim, minute: int) -> Array:
	var seen: Array = []
	while int(sim.state.clock["minute"]) < minute:
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + 1
		sim.events = []
		Festivals.step(sim)
		for e: Dictionary in sim.events:
			seen.append(e)
	return seen


func _types(evs: Array, type: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == type)


func _player(sim: Sim) -> String:
	return SimQuery.player_family(sim.state)


func _head(sim: Sim, fam: String) -> String:
	return Kin.head(sim.state, fam)


func test_catalog_has_the_calendar() -> void:
	eq(cat.validate().size(), 0, "no catalog problems (%s)" % ", ".join(cat.validate()))
	var fixed := 0
	var variable := 0
	for id: String in cat.festivals["festivals"]:
		var k := str(cat.festivals["festivals"][id]["kind"])
		fixed += 1 if k == "fixed" else 0
		variable += 1 if k == "variable" else 0
	eq(fixed, 8, "eight fixed feasts (4.25.1)")
	eq(variable, 9, "nine variable ones (4.25.2)")
	check(not cat.contracts().has("festivals"), "the festival contracts are not a table of the daily board")
	check((cat.festival_contracts.get("tables", {}) as Dictionary).has("noble_wedding"), "the wedding table is there")
	var days: Array = []
	for f: Dictionary in Festivals.calendar(_game()):
		days.append(int(f["day_of_year"]))
	eq(days, [0, 1, 2, 3, 4, 5, 6, 7], "one fixed feast on every day of the year")


func test_a_year_of_fixed_feasts_with_crier_and_contracts() -> void:
	var sim := _game()
	var evs := _fest_to(sim, 9 * DAY - 1)
	var started: Array = []
	for e: Dictionary in _types(evs, "festival_started"):
		if str(Festivals.def_of(sim, str(e["def"])).get("kind", "")) == "fixed":
			started.append(str(e["def"]))
	eq(started, ["mayday_corpus", "st_john", "harvest_fair", "st_michael", "all_saints_matanza", "christmas", "carnival",
		"holy_week"], "every fixed feast of the year, Holy Week of year 1 too (day 0 is the arrival: first_day 1)")
	var eves := _types(evs, "festival_eve")
	check(eves.size() >= 8, "a crier for each (%d)" % eves.size())
	var first: Dictionary = eves[0]
	eq(str(first["def"]), "mayday_corpus", "the first crier: the Mayos")
	var posted := _types(evs, "contract_posted").filter(func(e: Dictionary) -> bool: return str(e.get("festival", "")) != "")
	check(posted.size() >= 10, "the feasts post their contracts (%d)" % posted.size())
	eq(_types(evs, "festival_ended").size(), _types(evs, "festival_started").size() - (Festivals.active(sim) as Array).size(),
		"each one that started ended (or is on)")
	check((sim.state.festivals["history"] as Array).size() >= 8, "the history keeps them")
	var chron := sim.state.chronicle.filter(func(c: Dictionary) -> bool: return str(c.get("kind", "")) == "festival")
	check(chron.size() >= 8, "the chronicle has each feast")


func test_crier_is_on_the_eve_at_noon() -> void:
	var sim := _game()
	var evs := _fest_to(sim, DAY + 60)
	var eve: Dictionary = _types(evs, "festival_eve")[0]
	var up: Dictionary = Festivals.find(sim, str(eve["id"]))
	eq(int(up["announce"]), 12 * 60, "Mayos: the crier on day 0 at 12:00")
	eq(int(up["start"]), DAY, "it starts at 00:00 of day 1")
	var notices := Notices.list(sim, _player(sim))
	check(notices.any(func(n: Dictionary) -> bool: return str(n.get("key", "")) == "notice.festival_eve"), "the player hears it")


func test_effects_go_through_the_existing_multipliers() -> void:
	var sim := _game()
	_fest_to(sim, 8 * DAY + 8 * 60)  # Holy Week of year 1, 08:00
	near(WorldEvents.production_mult(sim, "sword"), 0.3, 0.0001, "holy day: workshops ×0,3 in the morning")
	check(Festivals.holy_day(sim), "the life block's hook says it is a holy day")
	near(WorldEvents.demand_mult(sim, "bread"), 0.8, 0.0001, "Lent: food demand ×0,8 before 17:00")
	_fest_to(sim, 8 * DAY + 18 * 60)
	near(WorldEvents.production_mult(sim, "sword"), 1.0, 0.0001, "no holy day in the evening")
	near(WorldEvents.demand_mult(sim, "bread"), 1.5, 0.0001, "Easter: food ×1,5 from 17:00")
	near(Festivals.hook_mult(sim, "visitors"), 2.0 * 0.7, 0.0001, "pilgrims ×2, fewer without a sponsor")
	var sim2 := _game()
	_fest_to(sim2, 3 * DAY + 10 * 60)  # the fair
	near(WorldEvents.customers_mult(sim2), 1.5, 0.0001, "fair: counter customers ×1,5")
	near(Festivals.home_tax_mult(sim2, 3), 0.0, 0.0001, "feria franca: no tax on that day's sales")
	near(Festivals.hook_mult(sim2, "visitors"), 5.0 * 0.7, 0.0001, "the fair: visitors ×5 (unsponsored ×0,7)")
	check("merchant" in Festivals.hook_kinds(sim2), "merchants come to the fair")
	eq((Festivals.active(sim2)[0]["stalls"] as Array).size(), 6, "six stalls of outsiders")
	var sim3 := _game()
	_fest_to(sim3, 5 * DAY + 12 * 60)  # the matanza
	var p := Market.price(sim3, "bread", 0, "buy")
	sim3.catalog.festivals["enabled"] = false
	var p_off := Market.price(sim3, "bread", 0, "buy")
	sim3.catalog.festivals["enabled"] = true
	check(p < p_off, "the matanza makes food cheap (%d < %d)" % [p, p_off])
	eq(WorldEvents.factors(sim3, "bread").filter(func(f: Dictionary) -> bool: return str(f["source"]) == "festival").size(),
		1, "the market says why")


func test_switched_off_changes_nothing() -> void:
	var c := Catalog.load_from()
	c.festivals["enabled"] = false
	var r := NewGame.from_start(c, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], c)
	_fest_to(sim, 4 * DAY)
	eq(sim.state.festivals, {}, "nothing written")
	near(WorldEvents.customers_mult(sim), 1.0, 0.0001, "no multiplier")
	eq(Festivals.order_sponsor(sim, {"actor": _head(sim, _player(sim)), "festival": "fst_0001", "part": "music"})["reason"],
		"festivals_off", "orders refused")


func test_sponsoring_pays_and_opens_the_bulls() -> void:
	var sim := _game()
	_fest_to(sim, 13 * 60)  # day 0, the Mayos announced
	var inst: Dictionary = Festivals.announced(sim)[0]
	eq(str(inst["def"]), "mayday_corpus", "the Mayos are announced")
	var fam := _player(sim)
	var actor := _head(sim, fam)
	sim.state.families[fam]["gold"] = 500
	var gold := Money.gold(sim.state, fam)
	var rep := Reputation.of(sim.state, fam)
	var before := FestivalContracts.open_of(sim, inst).size()
	var r := Festivals.order_sponsor(sim, {"actor": actor, "festival": str(inst["id"]), "part": "bulls"})
	check(r["ok"], "sponsor the bulls (%s)" % r["reason"])
	eq(Money.gold(sim.state, fam), gold - 80, "it costs 80")
	eq(Reputation.of(sim.state, fam), rep + 5, "reputation +5")
	check(FestivalContracts.open_of(sim, inst).size() > before, "the cart ring and the bullpen go up on the board")
	eq(Festivals.order_sponsor(sim, {"actor": actor, "festival": str(inst["id"]), "part": "bulls"})["reason"],
		"already_sponsored", "once")
	eq(Festivals.order_sponsor(sim, {"actor": actor, "festival": str(inst["id"]), "part": "dragons"})["reason"],
		"bad_part", "unknown part")
	var evs := _fest_to(sim, DAY + 18 * 60)
	var spec := _types(evs, "festival_spectacle")
	eq(spec.size(), 1, "the bulls run at 17:00")
	eq(str(spec[0]["spectacle"]), "bulls", "bulls")
	var started: Dictionary = _types(evs, "festival_started")[0]
	eq(started["sponsors"], [fam], "the crier thanks the sponsor")


func test_no_sponsor_no_bulls() -> void:
	var sim := _game()
	var evs := _fest_to(sim, DAY + 18 * 60)
	eq(_types(evs, "festival_spectacle").size(), 0, "nobody paid: no bulls")


func test_the_mayor_organizes_the_joust_on_the_patron_feast() -> void:
	var sim := _game()
	_fest_to(sim, 4 * DAY + 13 * 60)  # day 4: Sant Martí (the matanza, day 5) announced
	var inst: Dictionary = {}
	for i: Dictionary in Festivals.announced(sim):
		if str(i["def"]) == "all_saints_matanza":
			inst = i
	check(not inst.is_empty(), "the matanza is announced")
	check(bool(inst.get("patron", false)), "Vilarrasa's patron feast falls on it")
	var actor := _head(sim, _player(sim))
	eq(Offices.power_status(sim, actor, "organize_festival", {"festival": str(inst["id"]), "part": "joust"}),
		"not_office_holder", "only the mayor")
	Offices.take(sim, "mayor", 0, actor)
	eq(Offices.power_status(sim, actor, "organize_festival", {"festival": str(inst["id"]), "part": "joust"}), "",
		"the mayor may")
	var r := Offices.order_power(sim, {"type": "use_office_power", "actor": actor, "power": "organize_festival",
		"args": {"festival": str(inst["id"]), "part": "joust"}})
	check(r["ok"], "organized (%s)" % r["reason"])
	var t := ""
	for i: Dictionary in sim.state.festivals["upcoming"]:
		if str(i["def"]) == "tournament":
			t = str(i["id"])
	check(t != "", "the joust opens a tournament that day")
	eq(Offices.power_status(sim, actor, "organize_festival", {"festival": str(inst["id"]), "part": "bulls"}),
		"power_cooldown", "the power cools down")


func test_festival_contracts_are_a_race_with_one_winner() -> void:
	var sim := _game()
	_fest_to(sim, 13 * 60)
	var c: Dictionary = {}
	for x: Dictionary in sim.state.contracts["board"]:
		if bool(x.get("race", false)) and str(x["item"]) == "banner":
			c = x
	check(not c.is_empty(), "the Mayos ask for banners (the tailor of the town makes them)")
	if c.is_empty():
		return
	var fam := _player(sim)
	var a := _head(sim, fam)
	var rival := ""
	for f: String in sim.state.families:
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			rival = f
			break
	var b := _head(sim, rival)
	check(FestivalContracts.accept(sim, a, fam, c)["ok"], "the player takes it")
	check(FestivalContracts.accept(sim, b, rival, c)["ok"], "the rival takes it too")
	eq(FestivalContracts.status(sim, fam, c), "contract_mine", "not twice")
	eq(sim.state.contracts["board"].filter(func(x: Dictionary) -> bool: return str(x["id"]) == str(c["id"])).size(), 1,
		"it stays on the board while the race lasts")
	var ch: Dictionary = sim.state.characters[b]
	ch["position"] = Contracts.board_service(sim).duplicate()
	ch["location"] = ""
	ch["path"] = []
	Inventory.add(ch["inventory"], cat, "banner", int(c["min_quality"]), int(c["qty"]))
	var gold := Money.gold(sim.state, rival)
	sim.events = []
	var r := Contracts.order_deliver(sim, {"actor": b, "contract": str(c["id"])})
	check(r["ok"], "the rival delivers first (%s)" % r["reason"])
	eq(Money.gold(sim.state, rival), gold + int(c["pay"]), "paid")
	eq(_types(sim.events, "contract_lost").size(), 1, "the player loses it")
	check(Contracts.accepted_of(sim, fam).is_empty(), "no copy left for the player")
	check(sim.state.contracts["board"].filter(func(x: Dictionary) -> bool: return str(x["id"]) == str(c["id"])).is_empty(),
		"off the board")
	check(Notices.list(sim, fam).any(func(n: Dictionary) -> bool: return str(n.get("key", "")) == "notice.festival_contract_lost"),
		"the player is told")


func test_unclaimed_contracts_leave_at_their_hour() -> void:
	var sim := _game()
	_fest_to(sim, 13 * 60)
	var ids: Array = []
	for x: Dictionary in sim.state.contracts["board"]:
		if bool(x.get("race", false)):
			ids.append(str(x["id"]))
			eq(int(x["due_at"]), DAY + 17 * 60, "due at 17:00 of the feast")
	_fest_to(sim, DAY + 17 * 60 + 1)
	for x: Dictionary in sim.state.contracts["board"]:
		check(not str(x["id"]) in ids, "%s left the board" % x["id"])


func test_plain_board_ignores_festival_contracts_in_its_limits() -> void:
	var sim := _game()
	_fest_to(sim, 13 * 60)
	var view := Contracts.board_view(sim, _head(sim, _player(sim)))
	var race: Array = (view["open"] as Array).filter(func(x: Dictionary) -> bool: return bool(x.get("race", false)))
	check(not race.is_empty(), "the board shows them")
	eq(Contracts._plain_count(sim.state.contracts["board"]), (sim.state.contracts["board"] as Array).size() - race.size(),
		"the daily board counts only its own")


func test_weddings_open_their_feast() -> void:
	var sim := _game()
	_fest_to(sim, 9 * 60)
	var rival := ""
	for f: String in sim.state.families:
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			rival = f
			break
	sim.events = [{"type": "wedding", "family": rival, "character": _head(sim, rival), "spouse": "chr_9999",
		"from_family": ""}]
	Festivals.step(sim)
	var nw: Array = (sim.state.festivals["upcoming"] as Array).filter(func(i: Dictionary) -> bool:
		return str(i["def"]) == "noble_wedding")
	eq(nw.size(), 1, "a rich family's wedding opens the noble wedding")
	eq(int(nw[0]["day"]), 1, "tomorrow")
	eq(nw[0]["hosts"], [rival], "its hosts")
	_fest_to(sim, 13 * 60)
	var dress: Array = (sim.state.contracts["board"] as Array).filter(func(c: Dictionary) -> bool:
		return str(c["item"]) == "wedding_dress")
	eq(dress.size(), 1, "the bride's dress for the tailor")
	eq(int(dress[0]["min_quality"]), 2, "excellent")
	eq(FestivalContracts.status(sim, rival, dress[0]), "own_festival", "not for its own wedding")
	var fam := _player(sim)
	sim.events = [{"type": "wedding", "family": fam, "character": _head(sim, fam), "spouse": "chr_9998", "from_family": ""}]
	Festivals.step(sim)
	check((sim.state.festivals["offers"] as Dictionary).has(fam), "the player's wedding: an offer")
	sim.state.families[fam]["gold"] = 500
	var gold := Money.gold(sim.state, fam)
	var r := Festivals.order_host_wedding(sim, {"actor": _head(sim, fam)})
	check(r["ok"], "the player pays the banquet (%s)" % r["reason"])
	eq(Money.gold(sim.state, fam), gold - 80, "80 of gold")
	eq(Festivals.order_host_wedding(sim, {"actor": _head(sim, fam)})["reason"], "no_wedding", "once")
	sim.events = [{"type": "townsfolk_married", "husband": "chr_9001", "wife": "chr_9002", "house": ""}]
	Festivals.step(sim)
	check((sim.state.festivals["upcoming"] as Array).any(func(i: Dictionary) -> bool:
		return str(i["def"]) == "neighbours_wedding"), "the neighbours' wedding")


func test_other_cities_feasts_and_fairs() -> void:
	var sim := _game()
	sim.state.clock["minute"] = 1 * DAY + 600  # spring 2: Sant Jordi and the fair in Bellcaire
	var feasts := Festivals.city_feasts(sim, "capital", 1)
	eq(feasts.map(func(f: Dictionary) -> String: return str(f["kind"])), ["patron", "fair"], "Sant Jordi with its fair")
	near(Region.tariff(sim, "capital", _player(sim)), 0.0, 0.0001, "feria franca in Bellcaire")
	near(Festivals.city_mult(sim, "capital", "demand", "sword"), 1.3 * 1.3, 0.0001, "weapons wanted (patron and fair)")
	eq(Festivals.route_toll(sim, Region.route(sim, "r2")), 0, "no toll on the royal road to the fair")
	sim.state.clock["minute"] = 0 * DAY + 600
	eq(Festivals.route_toll(sim, Region.route(sim, "r2")), 0, "nor the day before (toll_free_days 2)")
	sim.state.clock["minute"] = 4 * DAY + 600
	near(Region.tariff(sim, "capital", _player(sim)), 0.1, 0.0001, "the tariff comes back")
	eq(Festivals.route_toll(sim, Region.route(sim, "r2")), 2, "and the toll")


func test_the_pilgrimage_follows_the_abbey_feast() -> void:
	var sim := _game()
	var evs := _fest_to(sim, 5 * DAY)
	var pil := _types(evs, "festival_started").filter(func(e: Dictionary) -> bool: return str(e["def"]) == "pilgrimage")
	eq(pil.size(), 1, "the romería to Montsacre")
	eq(int(pil[0]["day"]) if not pil.is_empty() else -1, 4, "on its founder's day (autumn 1)")


func test_variable_rolls_are_deterministic() -> void:
	var a := _game(7)
	var b := _game(7)
	_fest_to(a, 24 * DAY)
	_fest_to(b, 24 * DAY)
	eq(SaveFile.canonical(a.state.festivals), SaveFile.canonical(b.state.festivals), "same seed, same calendar")
	var vars := 0
	for i: Dictionary in a.state.festivals["history"]:
		if str(Festivals.def_of(a, str(i["def"])).get("kind", "")) == "variable":
			vars += 1
	check(vars >= 1, "three years bring some variable feast (%d)" % vars)


func test_save_round_trip_and_v16_migration() -> void:
	var sim := _game()
	_fest_to(sim, DAY + 600)
	var text := JSON.stringify(sim.state.to_dict())
	var back: WorldState = SaveFile.from_text(text)["state"]
	eq(SaveFile.canonical(back.festivals), SaveFile.canonical(sim.state.festivals), "festivals survive a save")
	var raw: Dictionary = sim.state.to_dict()
	raw.erase("festivals")
	raw["version"] = 16
	var r := SaveFile.from_text(JSON.stringify(raw))
	check(r["ok"], "a v16 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(st.version, WorldState.VERSION, "migrated")
	eq(st.festivals, {}, "no festivals before v18")
	var s2 := Sim.new(st, cat)
	s2.run_minutes(5)
	check(st.festivals.get("active") is Array, "Festivals.ensure fills it at its first step")
