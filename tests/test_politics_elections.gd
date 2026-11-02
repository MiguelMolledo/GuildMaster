extends "res://tests/test_case.gd"
## H10 elections (GDD 4.12.3-4.12.4, ap. A; docs/contratos/h10_cargos.md): registering, the campaign in the last
## season of the term, the vote at the year change (relation, reputation, emotions, campaign; deterministic),
## incumbents, vacancies and the rival AI running.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL_FAM: String = "fam_0002"
const RIVAL: String = "chr_0002"
const INSPECTOR: String = "market_inspector"

var cat := Catalog.load_from()


func _new_game() -> Sim:
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"], cat)
	sim.state.families[FAM]["title"] = "citizen"
	sim.state.families[FAM]["gold"] = 500
	return sim


func _outdoors(sim: Sim, chr: String, tile: Array) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	ch["location"] = ""
	ch["position"] = tile.duplicate()
	ch["path"] = []


func _run_to(sim: Sim, minute: int) -> Array:
	var all: Array = []
	while int(sim.state.clock["minute"]) < minute:
		all.append_array(sim.step([]))
	return all


## Criterion of H10: the campaign takes the last season of the term (winter) and the vote falls on the year change.
func test_campaign_is_the_last_season_and_the_vote_falls_on_the_year_change() -> void:
	var sim := _new_game()
	var st := sim.state
	var r := Orders.apply(sim, {"type": "run_for_office", "actor": HERO, "office": INSPECTOR, "level": "medium"})
	check(r["ok"], "Hugo runs for inspector (%s)" % r["reason"])
	eq(Money.gold(st, FAM), 450, "the medium campaign costs 50 (politics)")
	var el := Elections.open_election(st, INSPECTOR)
	var dpy := Clock.days_per_year(cat.time)
	eq(int(el["day"]), dpy, "the vote is on the first day of year 2 (the year change)")
	eq(int(el["campaign_day"]), dpy - int(cat.time["days_per_season"]), "the campaign starts one season before")
	var seasons: Array = cat.time["seasons"]
	eq(Clock.season(int(el["campaign_day"]) * Clock.MINUTES_PER_DAY, cat.time), str(seasons[seasons.size() - 1]),
		"the campaign is winter, the last season of the year")
	eq(Clock.season((int(el["day"]) - 1) * Clock.MINUTES_PER_DAY + 1439, cat.time), str(seasons[seasons.size() - 1]),
		"winter lasts until the vote")
	eq(int(st.offices[INSPECTOR]["seats"][0]["until"]), int(el["day"]), "the vote is the end of the term")
	_outdoors(sim, HERO, Titles.service(sim))
	eq(Elections.action_status(sim, HERO, "speech", ""), "campaign_not_started", "no campaign before winter")
	_run_to(sim, Clock.MINUTES_PER_DAY)
	st.clock["minute"] = (int(el["campaign_day"]) - 1) * Clock.MINUTES_PER_DAY + 23 * 60  # the end of autumn
	_run_to(sim, int(el["campaign_day"]) * Clock.MINUTES_PER_DAY + 10 * 60)
	check(Elections.in_campaign(sim, el), "winter: the campaign is on")
	_outdoors(sim, HERO, Titles.service(sim))
	eq(Elections.action_status(sim, HERO, "speech", ""), "", "a speech in winter")
	eq(Elections.run_status(sim, RIVAL, INSPECTOR, "basic"), "office_needs_title", "Bernat is common")
	st.families[RIVAL_FAM]["title"] = "citizen"
	eq(Elections.run_status(sim, RIVAL, INSPECTOR, "basic"), "registration_closed", "too late in winter")
	_run_to(sim, int(el["day"]) * Clock.MINUTES_PER_DAY - 1)
	eq(str(el["status"]), "open", "not voted on the last minute of the year")
	var ev := sim.step([])
	var types: Array = ev.map(func(e: Dictionary) -> String: return str(e["type"]))
	check("year_changed" in types and "election_held" in types, "the vote is the step of the year change")
	eq(str(el["status"]), "done", "closed")
	check(bool(el["result"]["unopposed"]), "alone: no vote")
	eq(Offices.of_character(st, HERO), INSPECTOR, "Hugo is the inspector")
	eq(int(st.offices[INSPECTOR]["seats"][0]["until"]), 2 * dpy, "a 1-year term: next vote at the next year change")


func test_registering_rules() -> void:
	var sim := _new_game()
	var st := sim.state
	eq(Elections.run_status(sim, HERO, "judge", "basic"), "office_needs_title", "a citizen cannot be judge")
	eq(Elections.run_status(sim, HERO, "nope", "basic"), "unknown_office", "unknown office")
	eq(Elections.run_status(sim, HERO, INSPECTOR, "gold"), "unknown_level", "unknown level")
	st.families[FAM]["gold"] = 10
	eq(Elections.run_status(sim, HERO, INSPECTOR, "medium"), "not_enough_gold", "50 gold for a medium campaign")
	eq(Elections.run_status(sim, HERO, INSPECTOR, "basic"), "", "the basic one is free")
	st.families[FAM]["title"] = "patrician"
	eq(Elections.run_status(sim, HERO, "judge", "basic"), "no_election", "the judge votes at the end of year 2")
	check(Orders.apply(sim, {"type": "run_for_office", "actor": HERO, "office": INSPECTOR, "level": "basic"})["ok"], "runs")
	eq(Elections.run_status(sim, HERO, "tax_collector", "basic"), "already_candidate", "one election at a time")
	check(Orders.is_management("run_for_office"), "registering is a management order (the chart)")


func _eve() -> Sim:
	return Sim.new(NewGame.from_scenario("office_election_eve", 1)["state"], cat)


func test_the_vote_counts_relation_and_reputation() -> void:
	var sim := _eve()
	var el := Elections.open_election(sim.state, INSPECTOR)
	_run_to(sim, 8 * Clock.MINUTES_PER_DAY)
	eq(str(el["status"]), "done", "voted")
	var votes: Dictionary = el["result"]["votes"]
	eq(int(votes[HERO]), 6, "six voters for Hugo (more reputation)")
	eq(int(votes[RIVAL]), 4, "four friends of Bernat (relation)")
	eq(el["result"]["winners"], [HERO], "Hugo wins")
	eq(Offices.of_character(sim.state, HERO), INSPECTOR, "and takes the office")
	var again := _eve()
	_run_to(again, 8 * Clock.MINUTES_PER_DAY)
	eq(Elections.last_result(again.state, INSPECTOR)["result"], el["result"], "the same vote twice: deterministic")


func test_emotions_turn_votes() -> void:
	var sim := _eve()
	var vs := Elections.voters(sim, [HERO, RIVAL])
	for i: int in 4:  # two offended with Hugo's family: never vote him; two grateful to Bernat's: vote him
		Emotions.add(sim, str(vs[vs.size() - 1 - i]), "offended" if i < 2 else "grateful", FAM if i < 2 else RIVAL_FAM)
	var el := Elections.open_election(sim.state, INSPECTOR)
	_run_to(sim, 8 * Clock.MINUTES_PER_DAY)
	eq(int(el["result"]["votes"][RIVAL]), 8, "four friends + two offended with Hugo + two grateful to Bernat")
	eq(el["result"]["winners"], [RIVAL], "Bernat wins")
	eq(Offices.of_character(sim.state, RIVAL), INSPECTOR, "the rival is the inspector")


func test_campaign_actions() -> void:
	var sim := _eve()
	var st := sim.state
	st.clock["minute"] = 7 * Clock.MINUTES_PER_DAY + 10 * 60
	var vs := Elections.voters(sim, [HERO, RIVAL])
	var v0 := str(vs[0])
	_outdoors(sim, v0, [20, 20])
	_outdoors(sim, HERO, [21, 20])
	var gold := Money.gold(st, FAM)
	var r := Orders.apply(sim, {"type": "campaign_action", "actor": HERO, "kind": "bribe", "target": v0})
	check(r["ok"], "bribe (%s)" % r["reason"])
	eq(Money.gold(st, FAM), gold - 20, "20 gold")
	eq(Elections.action_status(sim, HERO, "bribe", v0), "already_bribed", "once")
	var cand: Dictionary = Elections.candidacy(st, HERO)["candidate"]
	check(v0 in (cand["secured"] as Array), "his vote is secured")
	r = Orders.apply(sim, {"type": "campaign_action", "actor": HERO, "kind": "visit", "target": v0})
	check(r["ok"], "visit (%s)" % r["reason"])
	eq(Emotions.relation(st, HERO, v0), 5, "+5 relation with the visited")
	eq(Elections.action_status(sim, HERO, "speech", ""), "campaign_busy", "busy 4 hours after a visit")
	st.clock["minute"] = int(st.clock["minute"]) + 4 * 60
	eq(Elections.action_status(sim, HERO, "speech", ""), "", "free again")
	Orders.apply(sim, {"type": "campaign_action", "actor": HERO, "kind": "speech", "target": ""})
	eq(Elections.action_status(sim, HERO, "speech", ""), "already_today", "one speech a day")
	eq(Elections.action_status(sim, HERO, "defame", HERO), "not_a_candidate", "not oneself")
	Orders.apply(sim, {"type": "campaign_action", "actor": HERO, "kind": "defame", "target": RIVAL})
	eq(Elections.action_status(sim, HERO, "defame", RIVAL), "already_today", "one defamation a day")
	eq(Elections.action_status(sim, HERO, "visit", "chr_0001"), "bad_args",
		"not one's own family")
	var el := Elections.open_election(st, INSPECTOR)
	eq(Elections._choice(sim, el["candidates"], v0), HERO, "the bribed friend of Bernat votes Hugo")


func test_incumbent_reelected_when_nobody_runs() -> void:
	var sim := _new_game()
	var judge: String = Offices.holders(sim, "judge")[0]
	sim.state.clock["minute"] = 16 * Clock.MINUTES_PER_DAY - 30
	_run_to(sim, 16 * Clock.MINUTES_PER_DAY)
	eq(Offices.holders(sim, "judge"), [judge], "the judge stays: nobody ran")
	eq(int(sim.state.offices["judge"]["seats"][0]["until"]), 32, "a new 2-year term")
	eq(Offices.holders(sim, INSPECTOR), [], "the inspector stays vacant: nobody ran")
	eq(int(sim.state.offices[INSPECTOR]["seats"][0]["until"]), 24, "it votes again next year")


func test_npc_incumbent_competes_when_the_player_runs() -> void:
	var sim := _new_game()
	var st := sim.state
	var judge: String = Offices.holders(sim, "judge")[0]
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY
	st.families[FAM]["title"] = "patrician"
	Reputation.change(sim, FAM, 150, "test")
	check(Orders.apply(sim, {"type": "run_for_office", "actor": HERO, "office": "judge", "level": "high"})["ok"], "runs")
	st.clock["minute"] = 16 * Clock.MINUTES_PER_DAY - 30
	_run_to(sim, 16 * Clock.MINUTES_PER_DAY)
	var el := Elections.last_result(st, "judge")
	eq((el["candidates"] as Array).size(), 2, "the judge defends the seat")
	check(not bool(el["result"]["unopposed"]), "a real vote")
	eq(el["result"]["winners"], [HERO], "Hugo beats the judge (reputation, campaign)")
	check(Offices.of_character(st, judge) == "", "the old judge leaves")


func test_a_death_frees_the_seat() -> void:
	var sim := _new_game()
	var judge: String = Offices.holders(sim, "judge")[0]
	sim.events = []
	Lifecycle.die(sim, judge, "test")
	Offices.step(sim)
	eq(Offices.holders(sim, "judge"), [], "vacant")
	eq(Offices.election_day(sim, "judge"), 8, "it votes at the next year change")


func test_rival_runs_with_its_rule() -> void:
	var sim := _new_game()
	var st := sim.state
	st.families[RIVAL_FAM]["title"] = "citizen"
	st.families[RIVAL_FAM]["gold"] = 300
	var ran := false
	for i: int in 24 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "office_candidate" and str(e["family"]) == RIVAL_FAM:
				ran = true
				eq(str(e["office"]), INSPECTOR, "the first office of its rule")
				eq(str(e["level"]), "medium", "its level")
	check(ran, "the rival runs for an office within a day")
	var paid := 0
	for e: Dictionary in st.ledger["entries"]:
		if str(e["family"]) == RIVAL_FAM and str(e["category"]) == Money.POLITICS:
			paid += int(e["amount"])
	eq(paid, -50, "it paid its medium campaign (politics)")
