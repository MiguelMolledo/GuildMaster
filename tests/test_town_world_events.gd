extends "res://tests/test_case.gd"
## H13 · seasons in prices and production, and the global events (GDD 4.5.3 phase 2, 4.13): the season's price by
## goods group, the production multiplier, each effect kind, the rolls (deterministic with the seed, at most one per
## roll, never a disabled one), the duration rules (a local event never outlasts its season), excludes and limits,
## the notices, the mayor's declare_event, the save (round trip and the v12 -> v13 migration) and the price reason line.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"
const DAY: int = 1440

var cat := Catalog.load_from()


func _sim(id: String = "town_e_start", seed: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, seed)["state"], cat)


## Puts the clock at the start of `day` (the season follows: 2 days each, spring first).
func _at_day(sim: Sim, day: int, minute: int = 0) -> void:
	sim.state.clock["minute"] = day * DAY + minute


## The rolls of `days` days without running every minute: each day, what ends, then the rolls of that day.
func _roll_days(sim: Sim, from_day: int, days: int) -> Array:
	var started: Array = []
	for d: int in range(from_day, from_day + days):
		_at_day(sim, d)
		sim.events = [{"type": "day_started", "day": d}]
		WorldEvents.step(sim)
		for e: Dictionary in sim.events:
			if str(e["type"]) == "world_event_started":
				started.append("%d:%s:%d" % [d, e["def"], int(e["end"])])
	return started


func _raw_price(sim: Sim, item: String, side: String) -> float:
	var p := float(cat.item(item)["base_price"]) * float(cat.market["quality_mult"][0]) * Market.demand(sim, item)
	if side == "buy":
		return p * float(cat.difficulty_levels(sim.state.difficulty).get("buy_price_mult", 1.0))
	return p * float(cat.market["sell_ratio"])


func test_catalog_is_sound() -> void:
	var errs := cat.validate()
	eq(errs.size(), 0, "no catalog problems (%s)" % ", ".join(errs))
	eq(cat.goods_of("bread"), ["food"], "bread is food")
	eq(cat.goods_of("planks"), ["construction", "wood"], "planks: two groups, sorted")
	eq(cat.goods_of("iron"), [], "iron has no group")
	eq(WorldEvents.declarable(_sim()), ["festival", "religious_feast"], "what the mayor may declare")


## GDD 4.5.3: spring food ×0,8, summer food ×0,7 and textiles ×0,9, autumn wood ×1,2, winter food ×1,5,
## construction ×1,3, medicine ×1,4; everything else ×1.
func test_season_moves_prices_by_group() -> void:
	var sim := _sim()
	_at_day(sim, 0, 600)
	eq(Market.price(sim, "bread", 0, "sell"), roundi(_raw_price(sim, "bread", "sell") * 0.8), "spring: bread ×0,8")
	var sword_spring := Market.price(sim, "sword", 0, "sell")
	eq(sword_spring, roundi(_raw_price(sim, "sword", "sell")), "a sword has no season")
	_at_day(sim, 2, 600)
	eq(Market.price(sim, "wool", 0, "buy"), roundi(_raw_price(sim, "wool", "buy") * 0.9), "summer: wool ×0,9")
	eq(Market.price(sim, "bread", 0, "buy"), roundi(_raw_price(sim, "bread", "buy") * 0.7), "summer: bread ×0,7")
	_at_day(sim, 4, 600)
	eq(Market.price(sim, "wood", 0, "buy"), roundi(_raw_price(sim, "wood", "buy") * 1.2), "autumn: wood ×1,2")
	_at_day(sim, 6, 600)
	eq(Market.price(sim, "bread", 0, "buy"), roundi(_raw_price(sim, "bread", "buy") * 1.5), "winter: bread ×1,5")
	eq(Market.price(sim, "stone", 0, "buy"), roundi(_raw_price(sim, "stone", "buy") * 1.3), "winter: stone ×1,3")
	eq(Market.price(sim, "herbs", 0, "buy"), roundi(_raw_price(sim, "herbs", "buy") * 1.4), "winter: herbs ×1,4")
	eq(Market.price(sim, "iron", 0, "buy"), roundi(_raw_price(sim, "iron", "buy")), "winter: iron ×1")
	eq(Market.price(sim, "sword", 0, "sell"), sword_spring, "the sword is the same in every season")
	_at_day(sim, 8, 600)
	eq(Market.price(sim, "bread", 0, "sell"), roundi(_raw_price(sim, "bread", "sell") * 0.8), "the next year: spring again")


func test_production_follows_season_and_events() -> void:
	var c := Catalog.load_from()
	c.seasons["production"]["winter"] = {"weapons": 0.5}
	var sim := Sim.new(NewGame.from_scenario("kin_trader", 1)["state"], c)
	near(WorldEvents.production_mult(sim, "sword"), 1.0, 0.0001, "spring: ×1")
	_at_day(sim, 6, 600)
	near(WorldEvents.production_mult(sim, "sword"), 0.5, 0.0001, "winter: the data says ×0,5 for weapons")
	near(WorldEvents.production_mult(sim, "iron_ingot"), 1.0, 0.0001, "ingots have no group")
	# A real cycle at the furnace in a season with ingots at half speed takes twice as long.
	c.seasons["goods"]["metal"] = ["iron_ingot"]
	c.goods_reset()
	c.seasons["production"]["winter"] = {"metal": 0.5}
	var st := sim.state
	st.characters[HERO]["needs"] = {"hunger": 80, "rest": 80, "social": 80, "fun": 80}
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	Inventory.add(inv, c, "iron", 0, 4)
	st.characters[HERO]["location"] = FORGE
	var r := Orders.apply(sim, {"type": "work_at", "actor": HERO, "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "normal"})
	check(r["ok"], "works (%s)" % r["reason"])
	var job: Dictionary = st.buildings[FORGE]["zones"]["furnace"]["job"]
	var full := Production.owner_cycle_minutes(sim, FORGE, c.recipes()["forge_ingot"], "normal")
	eq(int(job["end"]) - int(job["start"]), full * 2, "half speed: twice the minutes")
	# The famine's farming ×0,5 goes through the same rule (no farming recipe yet: wheat).
	WorldEvents.start(sim, "famine")
	near(WorldEvents.production_mult(sim, "wheat"), 0.5, 0.0001, "famine: farming ×0,5")


func test_event_effects() -> void:
	var sim := _sim()
	_at_day(sim, 2, 600)  # summer: bread ×0,7
	var bread := _raw_price(sim, "bread", "buy")
	WorldEvents.start(sim, "famine")
	eq(Market.price(sim, "bread", 0, "buy"), roundi(bread * 0.7 * 2.5), "famine: food ×2,5 on top of the season")
	near(WorldEvents.mortality_mult(sim), 1.2, 0.0001, "famine: more deaths")
	var sword := _raw_price(sim, "sword", "sell")
	var errand := Market.errand_minutes(sim)
	WorldEvents.start(sim, "war")
	eq(Market.price(sim, "sword", 0, "sell"), roundi(sword * 2.0), "war: weapons ×2")
	eq(Market.price(sim, "bread", 0, "buy"), roundi(bread * 0.7 * 2.5 * 1.5), "war and famine multiply")
	eq(Market.errand_minutes(sim), roundi(errand * 1.5), "war: errands take ×1,5")
	sim.state.events_active.clear()
	WorldEvents.start(sim, "epidemic")
	near(WorldEvents.customers_mult(sim), 0.7, 0.0001, "epidemic: fewer customers")
	near(WorldEvents.mortality_mult(sim), 1.3, 0.0001, "epidemic: mortality +30 %")
	eq(Market.price(sim, "bandages", 0, "buy"), roundi(_raw_price(sim, "bandages", "buy") * 3.0), "medicine ×3 (summer ×1)")


## The demand effect multiplies the demand of the formula and stays inside the market's limits.
func test_demand_effect_is_clamped() -> void:
	var sim := _sim()
	_at_day(sim, 2, 600)
	sim.state.market["demand"]["bread"] = 1.9
	WorldEvents.start(sim, "festival")
	near(Market.effective_demand(sim, "bread"), float(cat.market["demand"]["max"]), 0.0001, "1,9 × 1,2 clamped to max")
	near(Market.demand(sim, "bread"), 1.9, 0.0001, "the stored demand does not change")
	sim.state.market["demand"]["bread"] = 1.0
	near(Market.effective_demand(sim, "bread"), 1.2, 0.0001, "festival: food demand ×1,2")
	near(WorldEvents.customers_mult(sim), 1.3, 0.0001, "festival: more customers")


## GDD 4.13: the mortality of an event in force multiplies the yearly death roll.
func test_mortality_multiplies_the_death_chance() -> void:
	var sim := _sim("founder_old")
	var old := ""
	for id: String in sim.state.characters:
		if Lifecycle.death_chance(sim, id) > 0.0 and Lifecycle.death_chance(sim, id) < 0.5:
			old = id
			break
	check(old != "", "somebody old enough")
	var p0 := Lifecycle.death_chance(sim, old)
	WorldEvents.start(sim, "epidemic")
	near(Lifecycle.death_chance(sim, old), p0 * 1.3, 0.000001, "epidemic: ×1,3")


func test_counter_customers_follow_the_events() -> void:
	var sim := _sim("town_microevents")
	var a := Counter._interval(sim, FORGE, 1000)
	WorldEvents.start(sim, "dignitary_visit")
	var b := Counter._interval(sim, FORGE, 1000)
	check(b < a and absf(float(b) - float(a) / 1.5) <= 1.0, "a visit: customers ×1,5, same roll, shorter wait (%d -> %d)" % [a, b])


## A season event starts with the season and lasts whole seasons; a local one never outlasts its season (GDD 4.13).
func test_durations() -> void:
	var sim := _sim()
	_at_day(sim, 4)  # autumn starts
	WorldEvents.start(sim, "war")
	var war: Dictionary = sim.state.events_active[0]
	eq(int(war["end"]), (4 + 8) * DAY, "war: 4 seasons from the start of autumn")
	sim.state.events_active.clear()
	_at_day(sim, 5, 600)  # the last day of autumn, 10:00
	WorldEvents.start(sim, "good_harvest")
	eq(int(sim.state.events_active[0]["end"]), 6 * DAY, "a season event started late still ends with its season")
	sim.state.events_active.clear()
	for seed: int in range(1, 30):  # whatever the duration roll, a 1-2 day visit on the last day ends with the season
		var s := _sim("town_e_start", seed)
		_at_day(s, 5, 0)
		WorldEvents.start(s, "dignitary_visit")
		check(int(s.state.events_active[0]["end"]) <= 6 * DAY, "seed %d: the visit stops at the end of autumn" % seed)
	_at_day(sim, 4, 0)
	WorldEvents.start(sim, "festival")
	eq(int(sim.state.events_active[0]["end"]), 5 * DAY, "a festival: one day")


func test_events_end_on_time_with_notices() -> void:
	var sim := _sim()
	_at_day(sim, 4)
	WorldEvents.start(sim, "festival")
	var n: Dictionary = sim.state.notices[sim.state.notices.size() - 1]
	eq(str(n["key"]), "notice.event_started", "a notice when it starts")
	eq(str(n["severity"]), Notices.WARNING, "it pops up (zone 7)")
	eq(str(n["family"]), FAM, "for the human family")
	eq(str(n["params"]["event"]), "festival", "with the event")
	_at_day(sim, 5, 0)
	sim.events = []
	WorldEvents.step(sim)
	check(sim.state.events_active.is_empty(), "over at its end")
	eq(str(sim.events[0]["type"]), "world_event_ended", "event emitted")
	n = sim.state.notices[sim.state.notices.size() - 1]
	eq(str(n["key"]), "notice.event_ended", "a notice when it ends")
	var view: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/view.json"))
	check("notice.event_ended" in (view["notices"]["done_keys"] as Array), "the end pops up as done (zone 7)")


func test_excludes_and_limits() -> void:
	var sim := _sim()
	_at_day(sim, 4)
	eq(WorldEvents.can_start(sim, "riot"), "event_disabled", "riot is off (no building damage yet)")
	eq(WorldEvents.can_start(sim, "political_crisis"), "event_disabled", "political crisis is off")
	eq(WorldEvents.can_start(sim, "discovery"), "event_disabled", "discovery is off")
	eq(WorldEvents.can_start(sim, "nope"), "unknown_event", "unknown")
	WorldEvents.start(sim, "famine")
	eq(WorldEvents.can_start(sim, "famine"), "event_active", "not twice")
	eq(WorldEvents.can_start(sim, "good_harvest"), "event_excluded", "no good harvest during a famine")
	eq(WorldEvents.can_start(sim, "festival"), "event_excluded", "no festival during a famine (festival excludes it)")
	WorldEvents.start(sim, "religious_feast")
	eq(WorldEvents.can_start(sim, "dignitary_visit"), "too_many_events", "one local event at a time")
	WorldEvents.start(sim, "war")
	eq(WorldEvents.can_start(sim, "epidemic"), "too_many_events", "at most 3 at once")


## The rolls come from the world seed by key: same seed = same events; at most one per roll; never a disabled one;
## in 10 years every enabled event shows up somewhere across the seeds.
func test_rolls_are_deterministic_and_bounded() -> void:
	var a := _roll_days(_sim("town_e_start", 7), 1, 80)
	var b := _roll_days(_sim("town_e_start", 7), 1, 80)
	eq(a, b, "same seed, same events")
	check(not a.is_empty(), "10 years bring events (%s)" % str(a))
	var seen := {}
	var per_day := {}
	for seed: int in range(1, 11):
		for x: String in _roll_days(_sim("town_e_start", seed), 1, 80):
			var parts := x.split(":")
			seen[parts[1]] = true
			var key := "%d|%s|%s" % [seed, parts[0], str(cat.world_events()[parts[1]]["scope"])]
			per_day[key] = int(per_day.get(key, 0)) + 1
	for id: String in cat.world_events():
		if bool(cat.world_events()[id]["enabled"]):
			check(seen.has(id), "%s shows up in 10 seeds × 10 years" % id)
		else:
			check(not seen.has(id), "%s never starts (disabled)" % id)
	for k: String in per_day:
		check(int(per_day[k]) <= 1, "at most one event per roll (%s)" % k)
	var c := _roll_days(_sim("town_e_start", 8), 1, 80)
	check(a != c, "another seed, other events")
	var quiet := Catalog.load_from()
	quiet.events["enabled"] = false
	eq(_roll_days(Sim.new(NewGame.from_scenario("town_e_start", 7)["state"], quiet), 1, 80), [], "events off: none")


## The rolls do not move any other roll (they are keyed): the state rng is untouched.
func test_rolls_leave_the_state_rng_alone() -> void:
	var sim := _sim("town_e_start", 7)
	var before := sim.state.rng.state
	_roll_days(sim, 1, 80)
	eq(sim.state.rng.state, before, "state.rng untouched")


## GDD 4.12.3 / 4.13: the mayor declares a festival; it starts at once, gives its notice and cools down.
func test_mayor_declares_an_event() -> void:
	var sim := Sim.new(NewGame.from_scenario("office_inspector", 1)["state"], cat)
	var st := sim.state
	for s: Dictionary in st.offices["market_inspector"]["seats"]:
		if str(s.get("holder", "")) == HERO:
			s["holder"] = ""
	st.offices["mayor"]["seats"][0]["holder"] = HERO
	eq(Offices.power_status(sim, HERO, "declare_event", {"event": "war"}), "bad_args", "war is not declarable")
	eq(Offices.power_status(sim, HERO, "declare_event", {"event": "riot"}), "bad_args", "nor a disabled one")
	var r := Orders.apply(sim, {"type": "use_office_power", "actor": HERO, "power": "declare_event",
		"args": {"event": "festival"}})
	check(r["ok"], "declares a festival (%s)" % r["reason"])
	check(WorldEvents.is_active(sim, "festival"), "in force")
	var ev: Dictionary = st.events_active[0]
	eq(str(ev["by"]), HERO, "declared by the mayor")
	eq(int(ev["start"]), int(st.clock["minute"]), "starts now")
	var today := Clock.day(int(st.clock["minute"]))
	check(int(ev["end"]) <= (today - today % 2 + 2) * DAY, "not past its season")
	var n: Dictionary = st.notices[st.notices.size() - 1]
	eq(str(n["key"]), "notice.event_declared", "the town is told who declared it")
	eq(Offices.power_status(sim, HERO, "declare_event", {"event": "religious_feast"}), "power_cooldown", "one a year")
	st.offices["mayor"]["seats"][0]["cooldowns"] = {}
	eq(Offices.power_status(sim, HERO, "declare_event", {"event": "religious_feast"}), "too_many_events",
		"one local event at a time")


func test_save_round_trip_with_events() -> void:
	var sim := _sim()
	_at_day(sim, 4, 30)
	WorldEvents.start(sim, "war")
	WorldEvents.start(sim, "festival")
	var back: WorldState = SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(sim.state.to_dict()), "same state after a round trip")
	var sim2 := Sim.new(back, cat)
	check(WorldEvents.is_active(sim2, "war") and WorldEvents.is_active(sim2, "festival"), "both still in force")
	eq(Market.price(sim2, "sword", 0, "sell"), Market.price(sim, "sword", 0, "sell"), "the same war price")
	eq(WorldState.VERSION, 13, "v13")


func test_v12_save_migrates_to_v13() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/saves/v12_kin_trader_events.json"))
	eq(int(raw["version"]), 12, "the fixture is v12")
	var r := SaveFile.load_file("res://tests/data/saves/v12_kin_trader_events.json")
	check(r["ok"], "the v12 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(st.version, WorldState.VERSION, "migrated")
	eq(st.events_active.size(), 1, "the malformed entries are dropped")
	eq(str(st.events_active[0]["def"]), "famine", "the good one stays")
	eq(str(st.events_active[0]["by"]), "", "rolled (by \"\")")
	var sim := Sim.new(st, cat)
	sim.run_minutes(10)
	check(WorldEvents.is_active(sim, "famine"), "still in force after loading")


## The market and the book say why a price moves (one line).
func test_price_reason_line() -> void:
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	_at_day(sim, 6, 600)  # winter
	sim.state.market["demand"]["bread"] = 0.84
	WorldEvents.start(sim, "war")
	eq(SimQuery.price_reason(sim, "bread"), "demanda ×0.84 · Invierno: alimentos ×1.5 · Guerra regional: alimentos ×1.5",
		"demand, season and event")
	eq(SimQuery.price_reason(sim, "iron"), "", "nothing moves iron")
	check(SimQuery.season_prices_line(sim).contains("alimentos ×1.5"), "the book: the season's prices")
	check(SimQuery.events_line(sim).begins_with("Guerra regional · quedan "), "the clock: the event and its time left (%s)" % SimQuery.events_line(sim))
	eq(SimQuery.events_short(sim), "Guerra 8 d", "the clock's short line")
	WorldEvents.start(sim, "religious_feast")
	eq(SimQuery.events_short(sim), "Guerra 8 d +1", "the longest one, and how many more")
	TranslationServer.set_locale(locale)
