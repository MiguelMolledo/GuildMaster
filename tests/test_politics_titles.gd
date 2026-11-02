extends "res://tests/test_case.gd"
## H9 titles (GDD 4.12.2, 4.9, 4.17, 4.19; docs/contratos/h9_titulos.md): request_title at the town hall with its
## requirements and refusals, the ceremony (gold in the ledger, title, chronicle and score, event, notices), the
## approval of an office holder, the limits a title opens and the upgrades that ask for a title.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("title_ready", 1)["state"], cat)


func _ask(sim: Sim, title: String = "") -> Dictionary:
	var o := {"type": "request_title", "actor": HERO}
	if title != "":
		o["title"] = title
	return Orders.apply(sim, o)


func test_ceremony_grants_citizen() -> void:
	var sim := _sim()
	var st := sim.state
	var gold := Money.gold(st, FAM)
	var entries := (st.ledger["entries"] as Array).size()
	sim.events = []
	var r := _ask(sim)
	check(r["ok"], "granted (%s)" % r["reason"])
	eq(str(st.families[FAM]["title"]), "citizen", "the family is citizen")
	eq(Money.gold(st, FAM), gold - 100, "100 gold")
	var e: Dictionary = st.ledger["entries"][entries]
	eq([e["category"], e["amount"], e["ref"]], ["titles", -100, "title_citizen"], "ledger: titles (4.19)")
	var fact: Dictionary = st.chronicle[st.chronicle.size() - 1]
	eq([fact["kind"], fact["family"], fact["title"]], ["title", FAM, "citizen"], "the chronicle")
	eq(int(Dynasty.score(sim, FAM)["by_kind"].get("title", 0)), 25, "25 points (4.17)")
	check(sim.events.any(func(x: Dictionary) -> bool: return str(x["type"]) == "title_granted" \
		and str(x["title"]) == "citizen" and str(x["from"]) == "common"), "title_granted")
	check(Notices.list(sim, FAM).any(func(n: Dictionary) -> bool: return str(n["key"]) == "notice.title_granted"),
		"a notice")
	eq(Titles.max_buildings(sim, FAM), 2, "citizen: 2 buildings (4.9)")
	eq(str(Titles.status(sim, HERO)["next"]), "patrician", "next: patrician")


func test_refusals() -> void:
	var sim := _sim()
	var st := sim.state
	eq(_ask(sim, "patrician")["reason"], "wrong_title", "only the next one")
	st.characters[HERO]["position"] = [20, 21]
	eq(_ask(sim)["reason"], "not_at_town_hall", "in person at the town hall")
	var svc := Titles.service(sim)
	st.characters[HERO]["position"] = [int(svc[0]), int(svc[1])]
	st.families[FAM]["reputation"] = 49
	eq(_ask(sim)["reason"], "title_needs_reputation", "50 of reputation")
	st.families[FAM]["reputation"] = 60
	st.families[FAM]["gold"] = 99
	eq(_ask(sim)["reason"], "not_enough_gold", "100 of gold")
	st.families[FAM]["gold"] = 400
	st.buildings[FORGE]["owner"] = ""
	eq(_ask(sim)["reason"], "title_needs_businesses", "a business")
	st.buildings[FORGE]["owner"] = FAM
	eq(str(st.families[FAM]["title"]), "common", "nothing changed on refusal")
	check(_ask(sim)["ok"], "now citizen")
	st.families[FAM]["reputation"] = 250
	st.families[FAM]["gold"] = 900
	eq(_ask(sim)["reason"], "title_needs_employees", "patrician: 2 employees (1 now)")
	st.families[FAM]["title"] = "baron"
	st.families[FAM]["reputation"] = 5000
	st.families[FAM]["gold"] = 20000
	eq(_ask(sim)["reason"], "title_needs_event", "noble needs a special event that does not exist yet")
	st.families[FAM]["title"] = "noble"
	eq(_ask(sim)["reason"], "max_title", "nothing above noble")
	eq(Titles.max_buildings(sim, FAM), -1, "noble: no limit")
	var kid := ""
	for c: String in st.characters:
		if str(st.characters[c].get("family", "")) == FAM and c != HERO:
			kid = c
	if kid != "":
		st.characters[kid]["birth_day"] = Clock.day(int(st.clock["minute"]))
		eq(Orders.apply(sim, {"type": "request_title", "actor": kid})["reason"], "too_young", "a child cannot ask")


func test_patrician_with_two_employees() -> void:
	var sim := _sim()
	var st := sim.state
	check(_ask(sim)["ok"], "citizen")
	st.families[FAM]["reputation"] = 200
	st.families[FAM]["gold"] = 600
	var ids: Array = st.characters.keys()
	ids.sort()
	for c: String in ids:
		if Staff.is_unemployed(sim, c) and str(st.characters[c]["rank"]) != "":
			st.characters[c]["job"] = Staff.new_job(sim, FORGE, 0, "any")
			break
	eq(Titles.employees(sim, FAM), 2, "two employees")
	check(_ask(sim)["ok"], "patrician")
	eq(Money.gold(st, FAM), 100, "500 gold")
	eq(Titles.max_buildings(sim, FAM), 4, "4 buildings")
	eq(int(Dynasty.score(sim, FAM)["by_kind"]["title"]), 100, "25 + 75 points")


func test_office_holder_must_approve() -> void:
	var sim := _sim()
	var st := sim.state
	var mayor := ""
	var ids: Array = st.characters.keys()
	ids.sort()
	for c: String in ids:
		if TownLife.is_townsperson(st, c) and Kin.is_adult(sim, c):
			mayor = c
			break
	st.offices = {"mayor": {"holder": mayor}}
	eq(_ask(sim)["reason"], "title_not_approved", "the mayor's affinity is 0 < 30")
	st.relationships[Ids.pair_key(mayor, HERO)] = {"relation": 0, "affinity": 30}
	check(_ask(sim)["ok"], "affinity 30: approved")
	st.offices = {}
	check(Titles.approved(sim, HERO), "vacant: approved by itself")


func test_the_title_opens_an_upgrade() -> void:
	var sim := _sim()
	var st := sim.state
	var need := ""
	for id: String in cat.upgrades():
		if str(cat.upgrade(id).get("requires", {}).get("title", "")) == "citizen":
			need = id
	check(need != "", "an upgrade asks for citizen (Fachada noble, 4.8)")
	var reqs: Dictionary = cat.upgrade(need).get("requires", {})
	for u: Variant in reqs.get("upgrades", []):
		Upgrades.complete(sim, FORGE, str(u))
	check(Upgrades.status_of(sim, HERO, FORGE, need) == "title_too_low" or \
		Upgrades.status_of(sim, HERO, FORGE, need) == "not_inside", "common: too low")
	check(_ask(sim)["ok"], "citizen")
	check(Upgrades.status_of(sim, HERO, FORGE, need) != "title_too_low", "citizen: the title no longer stops it")


func test_ceremony_through_a_real_step_and_save() -> void:
	var sim := _sim()
	sim.step([{"type": "request_title", "actor": HERO}])
	eq(str(sim.state.families[FAM]["title"]), "citizen", "given as an order in a step")
	var r := SaveFile.from_text(JSON.stringify(sim.state.to_dict()))
	check(r["ok"], "saved and loaded")
	eq(str((r["state"] as WorldState).families[FAM]["title"]), "citizen", "the title is kept (and inherited with the family)")


func test_rival_ai_asks_for_its_title() -> void:
	var sim := _sim()
	var st := sim.state
	var rival := ""
	for f: String in st.families:
		if str(st.families[f].get("ai_profile", "")) != "":
			rival = f
	check(rival != "", "the rival family")
	var profile: Dictionary = cat.ai_profiles()[str(st.families[rival]["ai_profile"])]
	check(bool(profile["title_rule"]["requests"]), "its profile asks for titles [provisional]")
	st.families[rival]["reputation"] = 50
	st.families[rival]["gold"] = 100 + int(profile["title_rule"]["spare_gold"]) - 1
	check(not RivalAI.wants_title(sim, rival, profile), "1 gold short of its spare: it does not go")
	st.families[rival]["gold"] = 400
	check(RivalAI.wants_title(sim, rival, profile), "ready with gold to spare")
	for i: int in 8 * 60:
		sim.step()
		if str(st.families[rival]["title"]) == "citizen":
			break
	eq(str(st.families[rival]["title"]), "citizen", "it walked to the town hall and got citizen")
	eq(Money.gold(st, rival) <= 300, true, "it paid 100")
	check(Notices.list(sim, FAM).any(func(n: Dictionary) -> bool: return str(n["key"]) == "notice.rival_title"),
		"the player hears of it")
