extends "res://tests/test_case.gd"
## The Rogue's second trade, the spy (docs/gdd/04d_otras_clases.md §4.22.6.5): spying a building from by its door for
## two hours (a report: the family's gold, its storage, its secrets), the town's spying jobs passed by the fence of the
## den, blackmail (who pays keeps quiet), exposing a secret, the watch that arrests a spy by night, and the adultery
## that is never tried. The start rogue_spy: the den on the Consulta's plot and the start's loan.

const DAY: int = 1440

var cat := Catalog.load_from()


func _game(difficulty: String = "normal") -> Sim:
	var r := NewGame.from_start(cat, "rogue_spy", difficulty, {"cast": "fixed"}, 1)
	check(bool(r["ok"]), "rogue_spy starts (%s)" % r.get("error", ""))
	var sim := Sim.new(r["state"], cat)
	sim.step()
	return sim


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == type)


func _me(sim: Sim) -> String:
	return Kin.head(sim.state, SimQuery.player_family(sim.state))


func _out(sim: Sim, c: String, tile: Array) -> void:
	var ch: Dictionary = sim.state.characters[c]
	ch["location"] = ""
	ch["path"] = []
	ch["position"] = tile.duplicate()


func _no_guards_near(sim: Sim) -> void:
	for g: String in Watch.guards(sim.state):
		_out(sim, g, [1, 1])


## The building of family `fam` (its first, sorted).
func _bld_of(sim: Sim, fam: String) -> String:
	for b: String in Festivals._sorted_keys(sim.state.buildings):
		if Money.family_of(sim.state, b) == fam:
			return b
	return ""


## The spy by `bld`'s door (one tile off), outdoors.
func _by_door(sim: Sim, who: String, bld: String) -> void:
	var door: Array = sim.state.buildings[bld]["door"]
	_out(sim, who, [int(door[0]), int(door[1]) + 1])


## Spies `bld` to the end (the check made easy unless `hard`); the events of the whole watch.
func _spy(sim: Sim, who: String, bld: String) -> Array:
	_by_door(sim, who, bld)
	var r := Orders.apply(sim, {"type": "spy", "actor": who, "building": bld})
	check(bool(r["ok"]), "spy %s allowed (%s)" % [bld, r.get("reason", "")])
	var evs: Array = []
	for i: int in int(Spy.cfg(sim).get("minutes", 120)) + 2:
		sim.state.characters[who]["position"] = (sim.state.characters[who]["position"] as Array).duplicate()
		sim.state.characters[who]["path"] = []
		evs.append_array(sim.step())
		if not Spy.book(sim)["spying"].has(who):
			break
	return evs


func _easy_checks() -> void:
	cat.rogue["spy"]["check_base"] = -30


func after_each() -> void:
	cat = Catalog.load_from()


func test_the_spy_start() -> void:
	var sim := _game()
	var st := sim.state
	var fam := SimQuery.player_family(st)
	eq(str(st.families[fam].get("class", "")), "rogue", "a Rogue")
	eq(str(st.characters[_me(sim)].get("profession", "")), "spy", "a spy")
	check(Rogue.den_of(st, fam) != "", "his den")
	check(not Loans.of_family(sim, fam).is_empty(), "the start's loan")
	check(Spy.job_underworld(st, cat.rogue["spy"], fam) >= int(cat.rogue["spy"]["jobs"]["min_underworld"]),
		"the den's contacts open the jobs")


func test_spying_gives_a_report_and_the_secrets() -> void:
	_easy_checks()
	var sim := _game()
	var st := sim.state
	var me := _me(sim)
	var fam := SimQuery.player_family(st)
	_no_guards_near(sim)
	var rival := "fam_0002"
	var forge := _bld_of(sim, rival)
	Upgrades.complete(sim, forge, "forge_secrets_1")
	_out(sim, me, [1, 1])
	eq(str(Orders.apply(sim, {"type": "spy", "actor": me, "building": forge}).get("reason", "")), "too_far", "from afar: no")
	eq(Spy.spy_reason(sim, me, Rogue.den_of(st, fam)), "own_building", "not his own den")
	var evs := _spy(sim, me, forge)
	check(_of(evs, "spy_interrupted").is_empty(), "he stays at his post")
	var done := _of(evs, "spy_done")
	check(not done.is_empty(), "two hours later, a report")
	var rep: Dictionary = Spy.intel(st, fam)[Spy.intel(st, fam).size() - 1]
	eq(str(rep["about"]), rival, "about the rival smith")
	check(absi(int(rep["gold"]) - Money.gold(st, rival)) <= ceili(Money.gold(st, rival) * 0.05) + 1, "his gold, about")
	eq((rep["secrets"] as Array).size(), 1, "the Secrets upgrade is a secret")
	var f := Tribunal.fact(st, str(rep["secrets"][0]))
	eq(str(f["charge"]), "tax_evasion", "a double ledger: tax evasion")
	check(not bool(f["public"]) and (f["seen_by"] as Array).has(me), "hidden, seen by the spy")
	var again := _spy(sim, me, forge)
	var rep2: Dictionary = Spy.intel(st, fam)[Spy.intel(st, fam).size() - 1]
	eq(str(rep2["secrets"][0]), str(rep["secrets"][0]), "a second look finds the same fact, not a new one")
	check(not _of(again, "spy_done").is_empty(), "")


func test_a_household_keeps_a_secret_sometimes() -> void:
	_easy_checks()
	var sim := _game()
	var st := sim.state
	var with_secret := ""
	var n := 0
	for f: String in Festivals._sorted_keys(st.families):
		if Spy.is_household(st, f):
			n += 1
			if Spy.household_secret(sim, f) != "" and with_secret == "":
				with_secret = f
	check(n >= 4, "the town has its households (%d)" % n)
	check(with_secret != "", "one of them keeps a secret")
	_no_guards_near(sim)
	var me := _me(sim)
	_spy(sim, me, _bld_of(sim, with_secret))
	var rep: Dictionary = Spy.intel(st, SimQuery.player_family(st)).back()
	eq(str(rep["about"]), with_secret, "his house spied")
	eq(str(Tribunal.fact(st, str(rep["secrets"][0]))["charge"]), Spy.household_secret(sim, with_secret), "its secret found")


func test_the_jobs_of_the_den() -> void:
	_easy_checks()
	var sim := _game()
	var st := sim.state
	var me := _me(sim)
	var fam := SimQuery.player_family(st)
	_no_guards_near(sim)
	Spy._post_jobs(sim)
	var jobs := Spy.jobs_for(sim, fam)
	check(not jobs.is_empty(), "a job on the first dawn")
	var j: Dictionary = jobs[0]
	var pay: Array = cat.rogue["spy"]["jobs"]["pay"]
	check(int(j["pay"]) >= int(pay[0]) and int(j["pay"]) <= int(pay[1]), "its pay (%d)" % int(j["pay"]))
	st.characters[me]["location"] = Rogue.den_of(st, fam)
	eq(Spy.deliver_reason(sim, me, str(j["id"])), "no_report", "no report yet")
	_spy(sim, me, _bld_of(sim, str(j["about"])))
	eq(Spy.deliver_reason(sim, me, str(j["id"])), "not_at_den", "delivered at the den")
	st.characters[me]["location"] = Rogue.den_of(st, fam)
	var gold := Money.gold(st, fam)
	var r := Orders.apply(sim, {"type": "deliver_intel", "actor": me, "job": str(j["id"])})
	check(bool(r["ok"]), "delivered (%s)" % r.get("reason", ""))
	eq(Money.gold(st, fam), gold + int(j["pay"]), "paid")
	check(Spy.job(sim, str(j["id"])).is_empty(), "the job is done")


func test_blackmail_who_pays_keeps_quiet() -> void:
	_easy_checks()
	var sim := _game()
	var st := sim.state
	var me := _me(sim)
	var fam := SimQuery.player_family(st)
	_no_guards_near(sim)
	var hh := ""
	for f: String in Festivals._sorted_keys(st.families):
		if Spy.household_secret(sim, f) in ["tax_evasion", "smuggling", "adultery"]:
			hh = f
			break
	_spy(sim, me, _bld_of(sim, hh))
	var facts := Spy.usable_facts(sim, fam)
	check(not facts.is_empty(), "a secret to use")
	var fid := str(facts[0]["id"])
	cat.rogue["spy"]["blackmail"]["household_pays"] = 1.0
	var gold := Money.gold(st, fam)
	var their := Money.gold(st, hh)
	var ask := Spy.demand(sim, facts[0])
	var r := Orders.apply(sim, {"type": "blackmail", "actor": me, "fact": fid})
	check(bool(r["ok"]), "blackmail (%s)" % r.get("reason", ""))
	var paid := mini(ask, their)
	eq(Money.gold(st, fam), gold + paid, "they pay")
	eq(Money.gold(st, hh), their - paid, "out of their purse")
	var ext: Array = (st.justice["facts"] as Array).filter(func(f: Dictionary) -> bool: return str(f["kind"]) == "blackmail")
	check(not ext.is_empty() and (ext[0]["seen_by"] as Array).is_empty(), "who pays keeps quiet")
	eq(Spy.blackmail_reason(sim, me, fid), "blackmailed_this_season", "once a season")


func test_blackmail_refused_is_seen_and_exposing() -> void:
	_easy_checks()
	var sim := _game()
	var st := sim.state
	var me := _me(sim)
	var fam := SimQuery.player_family(st)
	_no_guards_near(sim)
	var forge := _bld_of(sim, "fam_0002")
	Upgrades.complete(sim, forge, "forge_secrets_1")
	_spy(sim, me, forge)
	var fid := str(Spy.usable_facts(sim, fam)[0]["id"])
	st.families["fam_0002"]["honesty"] = 10
	var gold := Money.gold(st, fam)
	check(bool(Orders.apply(sim, {"type": "blackmail", "actor": me, "fact": fid})["ok"]), "blackmail the rival")
	eq(Money.gold(st, fam), gold, "an honest family does not pay")
	var ext: Array = (st.justice["facts"] as Array).filter(func(f: Dictionary) -> bool: return str(f["kind"]) == "blackmail")
	check(not (ext[0]["seen_by"] as Array).is_empty(), "the victim saw it (it may denounce it)")
	var rep := int(st.families["fam_0002"].get("reputation", 0))
	check(bool(Orders.apply(sim, {"type": "expose_fact", "actor": me, "fact": fid})["ok"]), "exposed")
	check(bool(Tribunal.fact(st, fid)["public"]), "public now")
	eq(int(st.families["fam_0002"].get("reputation", 0)), rep + int(cat.rogue["spy"]["expose"]["reputation"]), "it costs them")
	eq(Spy.expose_reason(sim, me, fid), "fact_not_usable", "once")


func test_the_watch_arrests_a_spy_by_night() -> void:
	var sim := _game()
	var st := sim.state
	var me := _me(sim)
	var forge := _bld_of(sim, "fam_0002")
	st.clock["minute"] = Clock.MINUTES_PER_DAY + 23 * 60
	_by_door(sim, me, forge)
	check(bool(Orders.apply(sim, {"type": "spy", "actor": me, "building": forge})["ok"]), "spying at night")
	var g := str(Watch.guards(st)[0]) if not Watch.guards(st).is_empty() else ""
	if g == "":
		Watch.step(sim)
		g = str(Watch.guards(st)[0])
	var p: Array = st.characters[me]["position"]
	_out(sim, g, [int(p[0]) + 2, int(p[1])])
	var evs: Array = []
	for i: int in 70:
		_out(sim, g, [int(p[0]) + 2, int(p[1])])
		st.characters[me]["path"] = []
		evs.append_array(sim.step())
		if not _of(evs, "spy_caught").is_empty():
			break
	check(not _of(evs, "spy_caught").is_empty(), "a guard sees him by the door")
	check(not _of(evs, "rogue_arrest_card").is_empty(), "the arrest card (trespass)")


func test_adultery_is_never_tried() -> void:
	var sim := _game()
	check(not Tribunal.triable(sim, "adultery"), "a secret, not a charge")
	check(Tribunal.triable(sim, "tax_evasion"), "tax evasion is")
	check(not (Tribunal.accuse_options(sim, _me(sim), "chr_0002")["charges"] as Array).has("adultery"), "not offered")


func test_difficulty_pays_the_spy_less_when_hard() -> void:
	var easy := _game("easy")
	var hard := _game("hard")
	check(Rogue._lever(easy, "intel_mult", 1.0) > Rogue._lever(hard, "intel_mult", 1.0), "easy pays more")
