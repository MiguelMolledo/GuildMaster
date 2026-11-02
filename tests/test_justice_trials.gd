extends "res://tests/test_case.gd"
## H11 court (GDD 4.12.5, ap. A; docs/contratos/h11_tribunal.md): the trial from an inspection, the preparation of 1
## season with the witness actions, the hearing (questioning, resting, the judge), the verdict by the formula, the
## sentences (fine, confiscation, office and title, banishment: no orders until it ends), accusations with a fact or
## fabricated, the constable's and judge's powers, deterministic.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"
const RIVAL_FAM: String = "fam_0002"
const RIVAL: String = "chr_0002"

var cat := Catalog.load_from()


func _sim(id: String) -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


func _trial(sim: Sim) -> Dictionary:
	return Tribunal.of_family(sim, FAM)


func _near(sim: Sim, a: String, b: String) -> void:
	var st := sim.state
	for c: String in [a, b]:
		st.characters[c]["location"] = ""
		st.characters[c]["path"] = []
		st.characters[c]["position"] = [20, 20]


func test_inspection_opens_an_automatic_trial() -> void:
	var sim := _sim("office_campaign")
	(sim.state.buildings[FORGE]["upgrades"] as Array).append("forge_secrets_1")
	sim.events = [{"type": "inspection", "family": FAM, "building": FORGE, "caught": true}]
	Tribunal.step(sim)
	var t := _trial(sim)
	check(not t.is_empty(), "GDD 4.8: «multa y juicio automático»")
	eq(str(t["accused"]), HERO, "against the head")
	eq(str(t["accuser"]), "", "the town accuses (no inspector)")
	eq(str(t["source"]), "inspection", "from the inspection")
	var n := (t["witnesses"] as Array).size()
	check(n >= 3 and n <= 5, "3-5 witnesses (%d)" % n)
	eq(int(t["prep_until"]) - int(t["start"]), int(cat.time["days_per_season"]) * Clock.MINUTES_PER_DAY,
		"a preparation of 1 season")
	check(Tribunal.fact(sim.state, str(t["fact"]))["tried"], "its fact is tried")
	var keys := sim.state.notices.map(func(x: Dictionary) -> String: return str(x.get("key", "")))
	check("notice.trial_accused" in keys, "the family is told")
	sim.events = [{"type": "inspection", "family": FAM, "building": FORGE, "caught": true}]
	Tribunal.step(sim)
	eq(Tribunal.open_trials(sim).size(), 1, "a second inspection adds a charge to the same trial")
	eq(t["extra"], ["tax_evasion"], "the extra charge")


func test_scale_is_the_formula_of_appendix_a() -> void:
	var sim := _sim("accused_player")
	var t := _trial(sim)
	var sc := Tribunal.scale(sim, t)
	var favor := 0
	var against := 0
	for w: Dictionary in t["witnesses"]:
		favor += 1 if str(w["disposition"]) == "favor" else 0
		against += 1 if str(w["disposition"]) == "against" else 0
	var r := SkillCheck.stat(sim, HERO, "rhetoric")
	eq(int(sc["defense"]), r * 2 + favor * 15 + roundi(Reputation.of(sim.state, FAM) * 0.1), "defense")
	eq(int(sc["accusation"]), 5 * 2 + against * 15 + 1 * 20, "accusation: the town's rhetoric 5, 1 proof")


func test_witness_actions() -> void:
	var sim := _sim("accused_player")
	var st := sim.state
	var t := _trial(sim)
	var against: Array = (t["witnesses"] as Array).filter(func(w: Dictionary) -> bool: return str(w["disposition"]) == "against")
	var w0 := str(against[0]["character"])
	eq(Tribunal.witness_status(sim, HERO, str(t["id"]), w0, "convince"), "too_far" if not NpcActions.in_range(sim, HERO, w0)
		else "", "in person")
	_near(sim, HERO, w0)
	var gold := Money.gold(st, FAM)
	var price := Tribunal.bribe_gold(sim, w0)
	check(Orders.apply(sim, {"type": "witness_action", "actor": HERO, "trial": str(t["id"]), "witness": w0,
		"kind": "bribe"})["ok"], "bribe")
	eq(Money.gold(st, FAM), gold - price, "the witness's price (justice)")
	eq(str(Tribunal._witness(t, w0)["disposition"]), "favor", "a bribe buys the testimony for sure")
	eq(int(st.families[FAM]["attitudes"]["honesty"]), -5, "a bribe costs honesty (provisional)")
	eq(Tribunal.witness_status(sim, HERO, str(t["id"]), w0, "convince"), "already_favor", "nothing more to do")
	var w1 := str(against[1]["character"])
	_near(sim, HERO, w1)
	check(Orders.apply(sim, {"type": "witness_action", "actor": HERO, "trial": str(t["id"]), "witness": w1,
		"kind": "convince"})["ok"], "convince")
	eq(Tribunal.witness_status(sim, HERO, str(t["id"]), w1, "convince") in ["already_today", "already_favor"], true,
		"once a day")
	eq(Tribunal.witness_status(sim, RIVAL, str(t["id"]), w1, "convince"), "not_your_trial", "only the accused's family")


func test_hearing_questioning_and_resting() -> void:
	var sim := _sim("trial_hearing")
	var t := _trial(sim)
	eq(Tribunal.cross_status(sim, HERO, str(t["id"]), str(t["witnesses"][0]["character"])), "trial_not_in_hearing",
		"not before the hearing")
	sim.run_minutes(6)
	eq(str(t["status"]), "hearing", "the hearing")
	var types := []
	var w := ""
	for x: Dictionary in t["witnesses"]:
		if str(x["disposition"]) == "against":
			w = str(x["character"])
			break
	check(Orders.apply(sim, {"type": "trial_cross", "actor": HERO, "trial": str(t["id"]), "witness": w})["ok"], "questioned")
	check(str(Tribunal._witness(t, w)["cross"]) in ["ok", "fail"], "its testimony changes")
	eq(Tribunal.cross_status(sim, HERO, str(t["id"]), w), "already_crossed", "once")
	var sc := Tribunal.scale(sim, t)
	check(Orders.apply(sim, {"type": "trial_rest", "actor": HERO, "trial": str(t["id"])})["ok"], "the defense rests")
	eq(str(t["status"]), "done", "the verdict now")
	eq(str(t["verdict"]), "innocent" if int(sc["defense"]) > int(sc["accusation"]) else "guilty", "by the scale")
	types.append(1)
	var again := _sim("trial_hearing")
	again.run_minutes(6)
	Orders.apply(again, {"type": "trial_cross", "actor": HERO, "trial": str(t["id"]), "witness": w})
	Orders.apply(again, {"type": "trial_rest", "actor": HERO, "trial": str(t["id"])})
	eq(Tribunal.trial(again.state, str(t["id"]))["verdict"], t["verdict"], "deterministic")


func test_hearing_ends_by_itself() -> void:
	var sim := _sim("trial_hearing")
	var t := _trial(sim)
	sim.run_minutes(5 + 2 * 60 + 2)
	eq(str(t["status"]), "done", "without orders, the verdict at the end of the hearing")
	eq(str(t["verdict"]), "guilty", "nobody worked the witnesses: guilty (6 + 15 + 6 against 10 + 30 + 20)")
	eq(str(t["sentence"]["kind"]), "confiscation", "tax evasion is medium: confiscation")
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword"), 0, "the forge's goods for sale are taken")
	check(Inventory.count(sim.state.buildings[FORGE]["inventory"], "iron") > 0, "the raw materials stay")
	var facts := sim.state.chronicle.filter(func(f: Dictionary) -> bool: return str(f.get("kind", "")) == "sentence")
	eq(str(facts[0]["severity"]), "medium", "the sentence in the chronicle (dynasty score -60)")


func test_sentences() -> void:
	var sim := _sim("accused_player")
	var st := sim.state
	var t := _trial(sim)
	t["severity"] = "light"
	var gold := Money.gold(st, FAM)
	Tribunal.rule(sim, t)
	var fine := int(t["sentence"]["gold"])
	check(fine >= 10 and fine <= 50, "light: a fine of 10-50 (%d)" % fine)
	eq(Money.gold(st, FAM), gold - fine, "paid (justice)")
	sim = _sim("accused_player")
	st = sim.state
	t = _trial(sim)
	t["severity"] = "grave"
	Offices.take(sim, "market_inspector", 0, HERO)
	Tribunal.rule(sim, t)
	eq(Offices.of_character(st, HERO), "", "grave: the office is lost")
	eq(str(st.families[FAM]["title"]), "common", "and the title drops a level")


func test_banishment() -> void:
	var sim := _sim("accused_player")
	var st := sim.state
	var t := _trial(sim)
	t["severity"] = "maximum"
	Tribunal.rule(sim, t)
	check(Tribunal.is_banished(st, HERO), "banished")
	eq(int(st.characters[HERO]["banished_until"]), Offices.today(sim) + 7, "for a year (8 days)")
	eq(str(st.characters[HERO]["location"]), "", "out of the forge")
	sim.step([{"type": "move_to", "actor": HERO, "tile": [20, 20]}])
	var refused := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "order_refused")
	eq(str(refused[0]["reason"]), "banished", "his orders are refused")
	st.clock["minute"] = (Offices.today(sim) + 8) * Clock.MINUTES_PER_DAY
	while not Ledger.is_dawn(sim):
		sim.step([])
	check(not Tribunal.is_banished(st, HERO), "back after a year, at dawn")


func test_accuse_with_a_fact_or_fabricated() -> void:
	var sim := _sim("rival_accused")
	var st := sim.state
	var o := Tribunal.accuse_options(sim, HERO, RIVAL)
	eq(Orders.apply(sim, {"type": "accuse", "actor": HERO, "target": RIVAL})["reason"], "needs_fact", "with something")
	check(Orders.apply(sim, {"type": "accuse", "actor": HERO, "target": RIVAL, "fact": str(o["facts"][0])})["ok"], "accuses")
	var t := Tribunal.of_family(sim, RIVAL_FAM)
	eq(str(t["charge"]), "bribery", "the fact's charge")
	eq(str(t["accuser"]), HERO, "Hugo accuses")
	eq(Tribunal.accuse_status(sim, HERO, RIVAL, "", "", false), "already_on_trial", "one trial at a time")
	sim = _sim("rival_accused")
	st = sim.state
	st.families[FAM]["title"] = "common"
	eq(Tribunal.accuse_status(sim, HERO, RIVAL, str(o["facts"][0]), "", false), "title_too_low", "citizens accuse")
	st.families[FAM]["title"] = "citizen"
	Orders.apply(sim, {"type": "accuse", "actor": HERO, "target": RIVAL, "fabricate": true, "charge": "treason"})
	var opened := not Tribunal.of_family(sim, RIVAL_FAM).is_empty()
	var failed := sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "accusation_failed")
	check(opened != failed, "fabricating: a trial with a fabricated proof, or found out")
	eq(int(st.families[FAM]["attitudes"]["honesty"]), -10, "fabricating costs honesty (provisional)")
	if opened:
		check(bool(Tribunal.of_family(sim, RIVAL_FAM)["fabricated"]), "marked fabricated")


func test_fabricated_and_innocent_costs_the_accuser() -> void:
	var sim := _sim("rival_accused")
	var st := sim.state
	var id := Tribunal.open(sim, RIVAL, HERO, FAM, "treason", "accusation", "", true)
	var t := Tribunal.trial(st, id)
	for w: Dictionary in t["witnesses"]:
		w["disposition"] = "favor"
	var rep := Reputation.of(st, FAM)
	Tribunal.rule(sim, t)
	eq(str(t["verdict"]), "innocent", "the witnesses defend him")
	eq(Reputation.of(st, FAM), rep - 50, "a false accusation found out: -50 (4.12.1)")
	eq(Tribunal.facts_against(sim, FAM).size(), 1, "and a fact against the accuser")


func test_judge_and_constable_powers() -> void:
	var sim := _sim("trial_hearing")
	var st := sim.state
	sim.run_minutes(6)
	var t := _trial(sim)
	var judge: String = Offices.holders(sim, "judge")[0]
	eq(Tribunal.verdict_status(sim, HERO, str(t["id"]), "innocent"), "not_the_judge", "only the judge")
	var jf := str(st.characters[judge]["family"])
	check(Orders.apply(sim, {"type": "trial_verdict", "actor": judge, "trial": str(t["id"]), "verdict": "innocent"})["ok"],
		"the judge rules")
	eq(str(t["verdict"]), "innocent", "his verdict")
	eq(int(st.families[jf]["attitudes"]["honesty"]), -20, "against the scale: -20 honesty (4.12.5)")
	sim = _sim("rival_accused")
	st = sim.state
	var constable: String = Offices.holders(sim, "constable")[0]
	var f := str(Tribunal.facts_against(sim, RIVAL_FAM)[0]["id"])
	check(Orders.apply(sim, {"type": "use_office_power", "actor": constable, "power": "arrest", "args": {"fact": f}})["ok"],
		"the constable arrests")
	eq(str(Tribunal.of_family(sim, RIVAL_FAM)["source"]), "arrest", "a trial from the arrest")
	(st.buildings[FORGE]["upgrades"] as Array).append("forge_secrets_1")
	st.offices["constable"]["seats"][0]["cooldowns"] = {}
	Orders.apply(sim, {"type": "use_office_power", "actor": constable, "power": "investigate", "args": {"family": FAM}})
	eq(Tribunal.facts_against(sim, FAM).size(), 1, "an investigation finds the Secrets upgrade")
	var c := "chr_0003"
	st.characters[c]["banished_until"] = 30
	check(Orders.apply(sim, {"type": "use_office_power", "actor": judge, "power": "pardon", "args": {"character": c}})["ok"],
		"the judge pardons")
	check(not Tribunal.is_banished(st, c), "no longer banished")


func test_bribe_scandal_is_a_fact() -> void:
	var sim := _sim("office_election_eve")
	var st := sim.state
	st.characters[HERO]["stats"]["stealth"] = 1
	var v := str(Elections.voters(sim, [HERO, RIVAL])[0])
	for c: String in [HERO, v]:
		st.characters[c]["location"] = ""
		st.characters[c]["position"] = [20, 20]
	st.clock["minute"] = 7 * Clock.MINUTES_PER_DAY + 10 * 60
	var found := false
	for i: int in 1:
		Orders.apply(sim, {"type": "campaign_action", "actor": HERO, "kind": "bribe", "target": v})
		found = not Tribunal.facts_against(sim, FAM).is_empty()
	var scandal := sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "campaign_action" and not bool(e["ok"]))
	eq(found, scandal, "a bribe found out is a public fact (bribery)")


func test_double_accounting_lowers_taxes() -> void:
	var sim := _sim("office_campaign")
	(sim.state.buildings[FORGE]["upgrades"] as Array).append("forge_secrets_1")
	near(Offices._tax_mult(sim, FAM), 0.9, 0.0001, "taxes -10 % (GDD 4.8)")
	near(Offices._tax_mult(sim, RIVAL_FAM), 1.0, 0.0001, "not the rival")
