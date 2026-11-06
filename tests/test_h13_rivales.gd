extends "res://tests/test_case.gd"
## H13 (04c 4.21.7-4.21.12): Bellcaire's 5 rival families (data/world/region.json ai_families: Ferrer and four of the
## five 04c profiles by the seed, never two ruthless), each with its workshop and its people; the rivalry
## (Hostility, town.rivalry) and the attacks with their presage: the price war, the sabotage; the gate (first year,
## cooldown); only on the maps of data/ai.json hostility_maps: Vilarrasa as always.

const START: String = "artisan_blacksmith"

var cat := Catalog.load_from()


func _capital(seed_value: int = 1) -> Sim:
	return Sim.new(NewGame.from_start(cat, START, "normal", {"city": "capital", "cast": "fixed"}, seed_value)["state"], cat)


func _ai(st: WorldState) -> Array:
	return Hostility._ai_families(st)


func _of_profile(st: WorldState, p: String) -> String:
	for f: String in _ai(st):
		if str(st.families[f]["ai_profile"]) == p:
			return f
	return ""


## Puts the game at minute `m` of day `day` (the tests' fast forward; the sim then runs minute by minute).
func _at(sim: Sim, day: int, m: int) -> void:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + m


func _run_until(sim: Sim, minute: int) -> void:
	while int(sim.state.clock["minute"]) < minute:
		sim.step()


func _dawn(sim: Sim, day: int) -> int:
	return Hostility._phase_start(sim, day, "dawn")


func test_bellcaire_has_five_rival_families_with_their_own_profiles() -> void:
	var seen := {}
	for s: int in [1, 2, 3, 4, 5]:
		var st := _capital(s).state
		var fams := _ai(st)
		eq(fams.size(), 5, "seed %d: five rival families" % s)
		var profiles := {}
		var ruthless := 0
		for f: String in fams:
			var p := str(st.families[f]["ai_profile"])
			profiles[p] = true
			ruthless += 1 if p == "ruthless" else 0
			check(Hostility._workshop_of(st, f) != "", "seed %d: %s has its workshop" % [s, f])
			check((st.families[f]["members"] as Array).size() >= 1, "seed %d: %s has its people" % [s, f])
			check(not sim_profile(p).is_empty(), "%s: a profile of data/ai_profiles" % p)
		eq(profiles.size(), 5, "seed %d: five different profiles" % s)
		check(profiles.has("rival_smith"), "seed %d: Ferrer is always the rival smith" % s)
		check(ruthless <= 1, "seed %d: never two ruthless" % s)
		seen[str(profiles.keys())] = true
	check(seen.size() > 1, "the seed changes which four")


func sim_profile(p: String) -> Dictionary:
	return cat.ai_profiles().get(p, {})


func test_vilarrasa_keeps_its_rivals_and_no_hostility() -> void:
	var sim := Sim.new(NewGame.from_start(cat, START, "normal", {"cast": "fixed"}, 1)["state"], cat)
	var profiles: Array = []
	for f: String in _ai(sim.state):
		profiles.append(str(sim.state.families[f]["ai_profile"]))
	profiles.sort()
	eq(profiles, ["rival_artisan", "rival_artisan", "rival_artisan", "rival_smith"], "Vilarrasa's four, as always")
	check(not Hostility.on(sim), "no hostility in town_e")
	for i: int in 60:
		sim.step()
	check(not sim.state.town.has("rivalry"), "nothing written")
	check(Hostility.may_accuse(sim, "fam_0002"), "Ferrer accuses there by its own rule, as always")


func test_the_rivalry_rises_with_the_market_and_wears_off() -> void:
	var sim := _capital()
	var st := sim.state
	var ferrer := _of_profile(st, "rival_smith")
	var me := "fam_0001"
	var start := Hostility.value(st, ferrer, me)
	eq(start, int(NewGame.city(cat, "capital")["ai_families"]["rival_to_player"]),
		"Ferrer looks at the newcomer from the start (region.json rival_to_player)")
	check(start > 0, "an eye on the newcomer")
	var bk := Hostility.book(st)
	bk["sales"] = {"3": {me: {"sword": 5}, ferrer: {"sword": 2}}}
	Hostility._daily(sim, 4)
	eq(Hostility.value(st, ferrer, me), start + 1, "the player sold most of the swords Ferrer also sold: +1")
	bk["sales"] = {"4": {me: {"sword": 1}, ferrer: {"sword": 5}}}
	Hostility._daily(sim, 5)
	eq(Hostility.value(st, ferrer, me), start, "a day without a reason: it wears off (−1)")
	eq(Hostility.band(sim, 0), 0, "Cordial")
	eq(Hostility.band(sim, 65), 3, "Hostil")


func test_no_attack_in_the_first_year_nor_under_the_threshold() -> void:
	var sim := _capital()
	var st := sim.state
	var ferrer := _of_profile(st, "rival_smith")
	Hostility.book(st)["values"][ferrer + "|fam_0001"] = 95
	Hostility.book(st)["sales"] = {"3": {"fam_0001": {"sword": 5}}}
	var m := Hostility._mem(sim, ferrer)
	Hostility._decide(sim, ferrer, m, 4)
	check(not m.has("presage"), "day 4: the first year protects the player")
	Hostility.book(st)["values"][ferrer + "|fam_0001"] = 40
	Hostility._decide(sim, ferrer, m, 9)
	check(not m.has("presage"), "rivalry 40 under Ferrer's 60: no attack")


func test_a_price_war_is_announced_then_fought_for_a_season() -> void:
	var sim := _capital()
	var st := sim.state
	var ferrer := _of_profile(st, "rival_smith")
	var me := "fam_0001"
	var day := 9
	_at(sim, day, 0)
	st.families[ferrer]["gold"] = 600  # over its reserve: not in austerity
	var bk := Hostility.book(st)
	bk["values"][ferrer + "|" + me] = 90
	bk["sales"] = {str(day - 1): {me: {"sword": 6}, ferrer: {"sword": 1}}}
	var k := _ai(st).find(ferrer)
	_run_until(sim, _dawn(sim, day) + 3 * k + 1)
	var m := Hostility._mem(sim, ferrer)
	check(m.get("presage") is Dictionary and str(m["presage"]["kind"]) == "price_war", "the presage of a price war")
	if not m.get("presage") is Dictionary:
		return
	eq(str(m["presage"]["item"]), "sword", "on the swords the player sells")
	eq(Hostility.sell_floor(sim, ferrer, "sword"), 99.0, "meanwhile it keeps its swords")
	var keys: Array = st.notices.filter(func(n: Dictionary) -> bool: return str(n["family"]) == me).map(
		func(n: Dictionary) -> String: return str(n["key"]))
	check("notice.ai_presage_price_war" in keys, "the player hears the rumour")
	_run_until(sim, int(m["presage"]["at"]) + 1)
	check(m.get("price_war") is Dictionary, "then the war")
	eq(Hostility.sell_floor(sim, ferrer, "sword"), 0.5, "it sells swords down to demand 0.5")
	var attacks: Array = bk["attacks"]
	eq(attacks.size(), 1, "one attack")
	check(bool(attacks[0]["player"]) and str(attacks[0]["kind"]) == "price_war", "on the player")
	m["price_war"]["until"] = int(st.clock["minute"]) + 1
	_run_until(sim, int(st.clock["minute"]) + 2)
	check(not m.has("price_war"), "a season and it is over")
	eq(Hostility.sell_floor(sim, ferrer, "sword"), -1.0, "back to its own rule")


func test_a_sabotage_is_seen_coming_damages_the_workshop_and_is_repaired() -> void:
	var sim := _capital(1)
	var st := sim.state
	var me := "fam_0001"
	var bad := _of_profile(st, "ruthless")
	check(bad != "", "seed 1 has the ruthless family")
	if bad == "":
		return
	var forge := Hostility._workshop_of(st, me)
	st.families[me]["gold"] = 5000  # its upkeep paid: the damage is the sabotage's only
	var day := 9
	_at(sim, day, 0)
	Hostility.book(st)["values"][bad + "|" + me] = 90
	st.families[bad]["gold"] = 600  # over its reserve: not in austerity
	var k := _ai(st).find(bad)
	_run_until(sim, _dawn(sim, day) + 3 * k + 1)
	var m := Hostility._mem(sim, bad)
	check(m.get("presage") is Dictionary and str(m["presage"]["kind"]) == "sabotage", "the ruthless family plans a sabotage")
	if not m.get("presage") is Dictionary:
		return
	eq(str(m["presage"]["building"]), forge, "on the player's forge")
	_run_until(sim, Hostility._phase_start(sim, day, "night") + 1)
	var keys: Array = st.notices.filter(func(n: Dictionary) -> bool: return str(n["family"]) == me).map(
		func(n: Dictionary) -> String: return str(n["key"]))
	check("notice.ai_presage_sabotage" in keys, "the night before: somebody was seen round the forge")
	eq(str(st.buildings[forge].get("state", "normal")), "normal", "not yet")
	_run_until(sim, Hostility._phase_start(sim, day + 1, "night") + 31)
	var done := bool(Hostility.book(st)["attacks"].back().get("kind", "") == "sabotage")
	check(done, "the next night, the sabotage")
	eq(str(st.buildings[forge].get("state", "")), "damaged", "the forge damaged: no work there")
	var facts := Tribunal.facts_against(sim, bad)
	var seen: bool = not facts.is_empty()
	if seen:
		check(Hostility.value(st, me, bad) >= 30, "seen: the player's rivalry towards them")
	var until := int(st.buildings[forge]["sabotaged_until"])
	_run_until(sim, _dawn(sim, Clock.day(until) + 1) + 1)
	eq(str(st.buildings[forge].get("state", "")), "normal", "repaired after its days")


func test_the_security_upgrades_count_against_a_sabotage() -> void:
	var sim := _capital(1)
	var st := sim.state
	var forge := Hostility._workshop_of(st, "fam_0001")
	eq(Hostility._security_level(sim, forge), 0, "no security at the start")
	var sec := ""
	for id: String in cat.upgrades():
		if str(cat.upgrade(id).get("branch", "")) == "security" and id.begins_with("forge"):
			sec = id
			break
	check(sec != "", "the forge has a security branch")
	if sec == "":
		return
	if not st.buildings[forge].get("upgrades") is Array:
		st.buildings[forge]["upgrades"] = []
	(st.buildings[forge]["upgrades"] as Array).append(sec)
	eq(Hostility._security_level(sim, forge), 1, "one level of Security: a sabotage stopped 20 % of the times")


func test_the_same_seed_the_same_town_also_after_a_save() -> void:
	var a := _capital(2)
	var b := _capital(2)
	for i: int in 700:
		a.step()
		b.step()
	var d: Dictionary = JSON.parse_string(JSON.stringify(b.state.to_dict()))
	var c := Sim.new(WorldState.from_dict(SaveFile.migrate(d)["data"]), cat)
	for i: int in 700:
		a.step()
		c.step()
	eq(a.state_hash(), c.state_hash(), "the same game after saving and loading in the middle")


# --- The AI's economy (AIEconomy) ---------------------------------------------------------------------------------------

func test_the_economy_runs_only_in_bellcaire() -> void:
	var v := Sim.new(NewGame.from_start(cat, START, "normal", {"cast": "fixed"}, 1)["state"], cat)
	check(not AIEconomy.on(v), "not in Vilarrasa")
	eq(AIEconomy.orders(v, "fam_0002", Kin.head(v.state, "fam_0002"), Hostility._workshop_of(v.state, "fam_0002"),
		cat.ai_profiles()["rival_smith"]), [], "no orders of its own there")
	check(AIEconomy.on(_capital()), "on in Bellcaire")


func test_the_spouse_works_at_the_family_workshop() -> void:
	var sim := _capital()
	var st := sim.state
	var worked := {}
	for i: int in Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "work_started" or str(e.get("type", "")) == "work_done":
				var who := str(e.get("actor", e.get("character", "")))
				var f := str(st.characters.get(who, {}).get("family", ""))
				if f != "" and who != Kin.head(st, f) and str(st.families[f].get("controlled_by", "")) == "ai":
					worked[f] = true
	check(worked.size() >= 3, "the spouses of the rival families work (%d families)" % worked.size())


func test_it_makes_what_is_cheaper_to_make_than_to_buy() -> void:
	var sim := _capital()
	var st := sim.state
	var carp := ""
	for f: String in _ai(st):
		if str(st.buildings[Hostility._workshop_of(st, f)]["type"]) == "carpentry":
			carp = f
	var home := Hostility._workshop_of(st, carp)
	var need := {"planks": 4}
	AIEconomy.make_or_buy(sim, Kin.head(st, carp), home, need)
	check(not need.has("planks"), "no planks bought: %s" % need)
	check(int(need.get("wood", 0)) > 0, "the wood to make them")


func test_it_buys_only_what_the_market_takes() -> void:
	var sim := _capital()
	var st := sim.state
	var f := _of_profile(st, "rival_smith")
	var home := Hostility._workshop_of(st, f)
	check(AIEconomy.cycles_for(sim, f, home, "forge_sword", 3) == 3, "an empty store: as many as asked")
	var store := RivalAI._storage(sim, home)
	for i: int in 30:
		Inventory.add(store, cat, "sword", 0, 1)
	check(Inventory.count(store, "sword") >= 30, "30 swords in store (%d)" % Inventory.count(store, "sword"))
	eq(AIEconomy.cycles_for(sim, f, home, "forge_sword", 3), 0, "more than the market takes in two days: none more")


func test_it_hires_with_gold_and_lets_go_without() -> void:
	var sim := _capital()
	var st := sim.state
	var f := _of_profile(st, "rival_smith")
	var head := Kin.head(st, f)
	var home := Hostility._workshop_of(st, f)
	var prof: Dictionary = cat.ai_profiles()["rival_smith"]
	st.families[f]["ai_state"]["recipe"] = "forge_sword"
	st.families[f]["gold"] = 500
	var o := AIEconomy._manage(sim, f, head, home, prof, 5)
	var kinds: Array = o.map(func(x: Dictionary) -> String: return str(x["type"]))
	check("hire" in kinds and "queue_add" in kinds, "with gold: an apprentice and its queue (%s)" % [kinds])
	for x: Dictionary in o:
		var r := Orders.apply(sim, x)
		check(bool(r["ok"]), "%s accepted (%s)" % [x["type"], r])
	st.families[f]["gold"] = 1
	var o2 := AIEconomy._manage(sim, f, head, home, prof, 6)
	eq(o2.size(), 1, "without gold for the wages")
	if o2.size() == 1:
		eq(str(o2[0]["type"]), "fire", "it lets the apprentice go")


func test_a_family_in_austerity_does_not_attack() -> void:
	var sim := _capital()
	var st := sim.state
	var ferrer := _of_profile(st, "rival_smith")
	Hostility.book(st)["values"][ferrer + "|fam_0001"] = 95
	Hostility.book(st)["sales"] = {"8": {"fam_0001": {"sword": 5}}}
	st.families[ferrer]["gold"] = 1
	var m := Hostility._mem(sim, ferrer)
	Hostility._decide(sim, ferrer, m, 9)
	check(not m.has("presage"), "under its reserve: no attack")
	st.families[ferrer]["gold"] = 600
	Hostility._decide(sim, ferrer, m, 9)
	check(m.has("presage"), "with gold: it attacks")



func test_a_family_short_of_gold_borrows_repays_and_is_never_ruined() -> void:
	var sim := _capital()
	var st := sim.state
	var ferrer := _of_profile(st, "rival_smith")
	var credit := func() -> String:
		for id: String in Loans.of_family(sim, ferrer):
			if str(st.loans[id].get("kind", "")) == AIEconomy.CREDIT:
				return id
		return ""
	_run_until(sim, _dawn(sim, 1) - 5)
	st.families[ferrer]["gold"] = 0
	_run_until(sim, _dawn(sim, 1) + 2)
	var id: String = credit.call()
	check(id != "", "without gold for tomorrow: a credit from the moneylender")
	check(Money.gold(st, ferrer) > 0, "the gold comes in (%d)" % Money.gold(st, ferrer))
	var owed := int(st.loans.get(id, {}).get("outstanding", 0))
	check(owed >= 144 and owed <= 360, "120 and the upkeep it owed, owing it + 20 %% (%d)" % owed)
	eq(int(st.buildings[Hostility._workshop_of(st, ferrer)].get("upkeep_debt", 0)), 0, "the upkeep paid at once")
	st.families[ferrer]["gold"] = 1000
	_run_until(sim, _dawn(sim, 2) + 2)
	check(not Loans.is_open(st.loans[id]), "with gold over its reserve it repays it")
	_run_until(sim, _dawn(sim, 7) - 5)
	st.families[ferrer]["gold"] = 0
	_run_until(sim, _dawn(sim, 7) + 2)
	var id2: String = credit.call()
	check(id2 != "" and id2 != id, "another one after gap_days")
	if id2 != "":
		st.loans[id2]["state"] = Loans.EXTENDED
		st.loans[id2]["due_minute"] = int(st.clock["minute"]) + 1
		st.families[ferrer]["gold"] = 0
		_run_until(sim, int(st.clock["minute"]) + 3)
		eq(str(st.loans[id2]["state"]), Loans.SEIZED, "due unpaid: seized")
		check(st.ending.is_empty(), "never a ruin: the player's game goes on")
	var v := Sim.new(NewGame.from_start(cat, START, "normal", {"cast": "fixed"}, 1)["state"], cat)
	v.state.families["fam_0002"]["gold"] = 0
	_run_until(v, _dawn(v, 1) + 2)
	for lid: String in v.state.loans:
		check(str(v.state.loans[lid].get("kind", "")) != AIEconomy.CREDIT, "no credit in Vilarrasa")
