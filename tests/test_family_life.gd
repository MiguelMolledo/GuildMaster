extends "res://tests/test_case.gd"
## H8 life cycle and succession (GDD 4.2.5, 4.10.4, 4.17; docs/contratos/h8_familia.md): birthdays at year_changed
## (school, trade, coming of age, decline), death and inheritance (the game goes on with the heir), the minor heir's
## regent, Game Over without heir with the score broken down, designate_heir.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(id: String, s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


## Runs to the next year change (and `extra` minutes after it).
func _to_new_year(sim: Sim, extra: int = 1) -> void:
	var dpy := Clock.days_per_year(cat.time)
	var day := Clock.day(int(sim.state.clock["minute"]))
	var target := (floori(float(day) / dpy) + 1) * dpy * Clock.MINUTES_PER_DAY
	sim.state.clock["minute"] = target - 1
	sim.run_minutes(extra)


func _types(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return str(e["type"]))


func test_game_over_without_heir_with_the_score() -> void:
	var sim := _sim("founder_no_heir")
	eq(sim.state.ending, {}, "the game goes on before midnight")
	var seen: Array = []
	for i: int in 15:
		seen.append_array(_types(sim.step()))
	check(not Kin.alive(sim.state, HERO), "Hugo dies at 75 when the year changes")
	check("character_died" in seen and "family_extinct" in seen and "game_over" in seen, "death, extinction, game over")
	eq(str(sim.state.ending.get("kind", "")), "game_over", "Game Over (4.17)")
	eq(str(sim.state.ending.get("family", "")), FAM, "of the player's family")
	var sc := Dynasty.score(sim, FAM)
	eq(int(sc["by_kind"].get("wedding", 0)), 20, "wedding 20")
	eq(int(sc["by_kind"].get("birth", 0)), 10, "birth 10")
	check(int(sc["by_kind"].get("wealth_peak", 0)) >= 13, "wealth peak 1 per 100 (%s)" % sc)
	eq(int(sim.state.ending["score"]), int(sc["total"]), "the ending keeps the total")
	var total := 0
	for k: String in sc["by_kind"]:
		total += int(sc["by_kind"][k])
	eq(total, int(sc["total"]), "the breakdown adds up")
	var sum := Dynasty.summary(sim, FAM)
	eq((sum["heads"] as Array).size(), 1, "one head (the founder)")
	eq(int(sum["generation"]), 1, "first generation")


func test_the_game_goes_on_with_the_heir() -> void:
	var sim := _sim("founder_old")
	var st := sim.state
	var son := str(st.characters[HERO]["children"][0])
	var gold := Money.gold(st, FAM)
	var owned := st.buildings.keys().filter(func(b: String) -> bool: return str(st.buildings[b]["owner"]) == FAM)
	var hammer: Variant = st.characters[HERO]["equipment"]["tool"]
	check(hammer is Dictionary, "the founder has the hammer")
	Lifecycle.die(sim, HERO, "test")
	eq(str(st.families[FAM]["head"]), son, "the son is the head")
	eq(int(st.families[FAM]["generation"]), 2, "generation 2")
	eq(Money.gold(st, FAM), gold, "the family keeps its gold")
	eq(st.buildings.keys().filter(func(b: String) -> bool: return str(st.buildings[b]["owner"]) == FAM), owned,
		"and its buildings")
	eq(Inventory.count(st.characters[son]["inventory"], "hammer"), 1, "the heir gets the hammer")
	eq(str(st.characters[son]["controlled_by"]), "human", "the heir is controlled")
	eq(Kin.group(st, FAM)[0], son, "and leads the group")
	eq(st.ending, {}, "no ending")
	var inh := st.chronicle.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "inheritance")
	eq(inh.size(), 1, "inheritance in the chronicle")
	eq(int(Dynasty.score(sim, FAM)["by_kind"].get("inheritance", 0)), 100, "100 points (4.17)")
	sim.run_minutes(30, null)
	var r := Orders.apply(sim, {"type": "exit_building", "actor": son})
	check(r["ok"] or str(r["reason"]) == "not_inside", "the heir takes orders (%s)" % r)
	sim.run_minutes(120)
	eq(st.ending, {}, "the game goes on")


func test_minor_heir_has_a_regent() -> void:
	var sim := _sim("founder_old")
	var st := sim.state
	var son := str(st.characters[HERO]["children"][0])
	var wife := str(st.characters[HERO]["spouse"])
	st.characters[son]["birth_day"] = Kin.birth_day_for(15, int(st.clock["minute"]), cat.time)
	st.characters[son]["controlled_by"] = "ai"
	eq(Kin.heir(sim, FAM), son, "a minor heir while the mother lives")
	Lifecycle.die(sim, HERO, "test")
	eq(str(st.families[FAM]["head"]), son, "the minor is the head")
	eq(str(st.families[FAM]["regent"]), wife, "the mother is the regent")
	eq(str(st.characters[wife]["controlled_by"]), "human", "the regent is controlled")
	eq(str(st.characters[son]["controlled_by"]), "ai", "the minor is not yet")
	_to_new_year(sim)
	eq(Kin.age(sim, son), 16, "16")
	eq(str(st.families[FAM]["regent"]), "", "the regency ends")
	eq(str(st.characters[son]["controlled_by"]), "human", "the heir takes over")
	eq(str(st.characters[wife]["controlled_by"]), "ai", "the mother goes back to AI")


func test_birthdays_school_trade_majority_decline() -> void:
	var sim := _sim("founder_old")
	var st := sim.state
	var daughter := str(st.characters[HERO]["children"][1])
	st.characters[daughter]["birth_day"] = Kin.birth_day_for(7, int(st.clock["minute"]), cat.time)
	st.characters[daughter]["profession"] = ""
	st.characters[HERO]["birth_day"] = Kin.birth_day_for(44, int(st.clock["minute"]), cat.time)
	var con := int(st.characters[HERO]["stats"]["constitution"])
	_to_new_year(sim)
	eq(Kin.age(sim, daughter), 8, "8")
	eq(str(st.characters[daughter]["life"].get("school", "")), "pending", "the player chooses the school stat")
	check(st.notices.any(func(n: Dictionary) -> bool: return str(n["key"]) == "notice.school_choice"), "school notice")
	var craft := int(st.characters[daughter]["stats"]["craft"])
	eq(Orders.apply(sim, {"type": "school_choice", "actor": HERO, "child": daughter, "stat": "craft"})["ok"], true,
		"school_choice")
	eq(int(st.characters[daughter]["stats"]["craft"]), mini(10, craft + 1), "+1 craft")
	eq(Orders.apply(sim, {"type": "school_choice", "actor": HERO, "child": daughter, "stat": "craft"})["reason"],
		"no_choice", "only once")
	eq(int(st.characters[HERO]["stats"]["constitution"]), con - 1, "-1 Constitution at 45")
	st.characters[daughter]["birth_day"] = Kin.birth_day_for(11, int(st.clock["minute"]), cat.time)
	_to_new_year(sim)
	eq(str(st.characters[daughter]["profession"]), "blacksmith", "a trade at 12")
	eq(str(st.characters[daughter]["assigned"]), FORGE, "assigned to the family forge")
	st.characters[daughter]["birth_day"] = Kin.birth_day_for(15, int(st.clock["minute"]), cat.time)
	_to_new_year(sim)
	eq(str(st.characters[daughter]["controlled_by"]), "human", "joins the group at 16")
	check(st.characters[daughter]["schedule"] is Dictionary, "with the default routine")
	eq(Kin.group(st, FAM).size(), 3, "three in the group")
	check(float(st.characters[daughter]["inventory"]["limit"]) > 0.0, "an inventory of her own")


func test_group_has_at_most_three() -> void:
	var sim := _sim("family_routines")
	var st := sim.state
	var wife := str(st.characters[HERO]["spouse"])
	var extra := Births.born(sim, wife, HERO)
	st.characters[extra]["birth_day"] = Kin.birth_day_for(15, int(st.clock["minute"]), cat.time)
	_to_new_year(sim)
	eq(Kin.group(st, FAM).size(), 3, "still three")
	eq(str(st.characters[extra]["controlled_by"]), "ai", "the fourth adult stays with AI")


func test_designate_heir() -> void:
	var sim := _sim("founder_old")
	var st := sim.state
	var son := str(st.characters[HERO]["children"][0])
	var daughter := str(st.characters[HERO]["children"][1])
	var wife := str(st.characters[HERO]["spouse"])
	eq(Orders.apply(sim, {"type": "designate_heir", "actor": HERO, "heir": wife})["reason"], "not_an_heir",
		"the spouse is not an heir")
	eq(Orders.apply(sim, {"type": "designate_heir", "actor": HERO, "heir": daughter})["ok"], true, "the daughter")
	eq(Kin.heir(sim, FAM), daughter, "designated")
	Lifecycle.die(sim, HERO, "test")
	eq(str(st.families[FAM]["head"]), daughter, "the designated one inherits")
	eq(str(st.families[FAM]["regent"]), wife, "a minor: the mother rules")
	check(Kin.alive(st, son), "the brother keeps his things (alive)")


func test_close_dynasty_is_off() -> void:
	var sim := _sim("founder_old")
	eq(Orders.apply(sim, {"type": "close_dynasty", "actor": HERO})["reason"], "disabled", "D19 pending: off")
	sim.catalog.family["succession"]["voluntary_close"] = true
	eq(Orders.apply(sim, {"type": "close_dynasty", "actor": HERO})["ok"], true, "on when the data allows it")
	eq(str(sim.state.ending["kind"]), "closed", "closed ending")
	sim.catalog.family["succession"]["voluntary_close"] = false


func test_death_chance_grows_with_age() -> void:
	var sim := _sim("founder_old")
	var st := sim.state
	st.characters[HERO]["stats"]["constitution"] = 5
	var last := 0.0
	for age: int in [56, 60, 64, 68, 72]:
		st.characters[HERO]["birth_day"] = Kin.birth_day_for(age, int(st.clock["minute"]), cat.time)
		var p := Lifecycle.death_chance(sim, HERO)
		check(p > last, "grows at %d (%f)" % [age, p])
		last = p
	st.characters[HERO]["birth_day"] = Kin.birth_day_for(68, int(st.clock["minute"]), cat.time)
	near(Lifecycle.death_chance(sim, HERO), 0.355, 0.01, "~33 % at 68 (4.2.5)")
	st.characters[HERO]["stats"]["constitution"] = 9
	check(Lifecycle.death_chance(sim, HERO) < 0.3, "Constitution lowers it")
