extends "res://tests/test_case.gd"
## Vida (docs/gdd/04f_vida_y_fiestas.md §4.24.5): incidents. A brawl in the plaza (fought with the duel's rules, the
## watch parts it and fines the one who started it, or the hero parts them), a night raid (the alarm brings the watch,
## nothing ever takes more than 3 pieces or a tenth of the gold), a kidnapping (pay, negotiate, rescue or nothing;
## never the head) and the fair-risk rules (no raid nor kidnapping in the first year; off with the life off).

const DAY := 1440
const HERO := "chr_0001"
const FAM := "fam_0001"


func _sim(scenario: String, on: bool = true) -> Sim:
	var cat := Catalog.load_from()
	cat.life_tables["life"]["enabled"] = on
	var r := NewGame.from_scenario(scenario, 1)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _until(sim: Sim, type: String, max_minutes: int, def: String = "") -> Dictionary:
	for i: int in max_minutes:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == type and (def == "" or str(e.get("def", "")) == def):
				return e
	return {}


func test_a_brawl_in_the_plaza() -> void:
	var sim := _sim("life_altercation")
	var e := _until(sim, "incident_started", 30, "altercation")
	check(not e.is_empty(), "the brawl starts at 20:00")
	var inc := Incidents.find(sim.state, str(e.get("incident", "")))
	check(not inc.is_empty(), "it is active")
	check(not (inc.get("card", {}) as Dictionary).is_empty(), "the player's family gets its card")
	var f := _until(sim, "incident_fight", 40)
	check(not f.is_empty(), "they fight (the duel decides who would win)")
	var end := _until(sim, "incident_ended", 60, "altercation")
	check(str(end.get("outcome", "")) in ["watch", "fought", "separated"], "it ends (%s)" % end.get("outcome", ""))
	var last: Dictionary = sim.state.chronicle[sim.state.chronicle.size() - 1]
	eq(str(last.get("kind", "")), "altercation", "in the chronicle")


func test_the_hero_parts_them() -> void:
	var sim := _sim("life_altercation")
	var e := _until(sim, "incident_started", 30, "altercation")
	var inc := Incidents.find(sim.state, str(e["incident"]))
	var tile: Array = inc["tile"]
	sim.state.characters[HERO]["position"] = [int(tile[0]) + 1, int(tile[1]) + 1]
	sim.state.characters[HERO]["location"] = ""
	var rep := Reputation.of(sim.state, FAM)
	var r := Orders.apply(sim, {"type": "resolve_incident", "actor": HERO, "incident": str(e["incident"]), "choice": "separate"})
	check(bool(r["ok"]), "separate is allowed next to them (%s)" % r.get("reason", ""))
	var ok := Incidents.find(sim.state, str(e["incident"])).is_empty()
	if ok:
		eq(Reputation.of(sim.state, FAM), rep + 3, "parted: +3 reputation")
	else:
		check(bool(Incidents.find(sim.state, str(e["incident"])).get("separate_failed", false)), "or it failed")
	sim.state.characters[HERO]["position"] = [1, 1]
	var far := _sim("life_altercation")
	var e2 := _until(far, "incident_started", 30, "altercation")
	far.state.characters[HERO]["position"] = [2, 2]
	far.state.characters[HERO]["location"] = ""
	var r2 := Orders.apply(far, {"type": "resolve_incident", "actor": HERO, "incident": str(e2["incident"]), "choice": "separate"})
	eq(str(r2.get("reason", "")), "too_far", "too far to part them")


func test_the_alarm_brings_the_watch_to_the_raid() -> void:
	var sim := _sim("life_bandits")
	var gold := Money.gold(sim.state, FAM)
	var e := _until(sim, "incident_raid_at_door", 120)
	check(not e.is_empty(), "the band reaches the forge")
	var inc := Incidents.find(sim.state, str(e["incident"]))
	eq(str(inc.get("family", "")), FAM, "the hero's forge")
	var r := Orders.apply(sim, {"type": "resolve_incident", "actor": HERO, "incident": str(e["incident"]), "choice": "alarm"})
	check(bool(r["ok"]), "alarm raised")
	var arrived := _until(sim, "guard_arrived", 60)
	check(not arrived.is_empty(), "a guard gets there")
	var end := _until(sim, "incident_ended", 120, "bandit_raid")
	check(not end.is_empty(), "the raid ends")
	var closed: Dictionary = (sim.state.town["incidents"]["closed"] as Array).back()
	var took := 0
	for it: Dictionary in closed.get("took", []):
		took += int(it["qty"])
	check(took <= 3, "at most 3 pieces (%d)" % took)
	check(int(closed.get("gold", 0)) <= ceili(float(gold) * 0.1), "at most a tenth of the gold")
	if str(closed.get("outcome", "")) == "repelled_watch":
		check(Incidents.nest_route(sim) != "r4", "the Coll de la Venta is «escarmentado»")
	for c: String in sim.state.characters:
		check(not sim.state.characters[c].get("bandit") is Dictionary, "the band is gone")


func test_hiding_loses_at_most_the_cap() -> void:
	var sim := _sim("life_bandits")
	var inv: Dictionary = sim.state.buildings["bld_0001"]["inventory"]
	Inventory.add(inv, sim.catalog, "sword", 0, 6)
	var e := _until(sim, "incident_raid_at_door", 120)
	Orders.apply(sim, {"type": "resolve_incident", "actor": HERO, "incident": str(e["incident"]), "choice": "hide"})
	for g: String in Watch.guards(sim.state):
		Watch.release(sim.state, str(e["incident"]))
	var loot := _until(sim, "incident_raid_loot", 120)
	if loot.is_empty():
		return  # a patrol drove them away first
	var n := 0
	for it: Dictionary in loot.get("items", []):
		n += int(it["qty"])
	check(n <= 3, "3 pieces at most (%d)" % n)
	check(Inventory.count(inv, "sword", 0) >= 3, "the rest stays")


func test_a_kidnapping_and_its_ransom() -> void:
	var sim := _sim("life_kidnap")
	var e := _until(sim, "incident_started", 30, "kidnapping")
	check(not e.is_empty(), "the kidnapping happens at 18:50")
	var v := str(e["victim"])
	check(v != Kin.head(sim.state, FAM), "never the head")
	check(Region.is_away(sim.state, v), "the victim is off the map, held")
	var inc := Incidents.find(sim.state, str(e["incident"]))
	eq(inc["card"]["choices"], ["pay", "negotiate", "rescue", "nothing"], "pay, negotiate, rescue or nothing")
	var ransom := int(inc["ransom"])
	Orders.apply(sim, {"type": "resolve_incident", "actor": HERO, "incident": str(e["incident"]), "choice": "negotiate"})
	inc = Incidents.find(sim.state, str(e["incident"]))
	check(int(inc["ransom"]) in [roundi(ransom * 0.7), roundi(ransom * 1.5)], "the ransom moves (−30 % or +50 %)")
	check(not "negotiate" in (inc["card"]["choices"] as Array), "negotiate only once")
	sim.state.families[FAM]["gold"] = 1000
	var gold := Money.gold(sim.state, FAM)
	var r := Orders.apply(sim, {"type": "resolve_incident", "actor": HERO, "incident": str(e["incident"]), "choice": "pay"})
	check(bool(r["ok"]), "paid")
	eq(Money.gold(sim.state, FAM), gold - int(inc["ransom"]), "the ransom")
	check(not Region.is_away(sim.state, v), "back home")
	check(Incidents.find(sim.state, str(e["incident"])).is_empty(), "over")


func test_nobody_pays_for_their_own() -> void:
	var sim := _sim("life_kidnap")
	var e := _until(sim, "incident_started", 30, "kidnapping")
	var v := str(e["victim"])
	var rep := Reputation.of(sim.state, FAM)
	Orders.apply(sim, {"type": "resolve_incident", "actor": HERO, "incident": str(e["incident"]), "choice": "nothing"})
	var end := _until(sim, "incident_ended", 5 * DAY, "kidnapping")
	eq(str(end.get("outcome", "")), "abandoned", "back on their own")
	check(Region.is_away(sim.state, v) == false, "on the map again")
	check(Emotions.has(sim, v, "scared", Life.FAMILY_BANDITS), "scared")
	eq(Reputation.of(sim.state, FAM), rep - 10, "«no pagó por los suyos»")


func test_no_raid_nor_kidnapping_in_the_first_year() -> void:
	var sim := _sim("town_e_start")
	sim.state.town["incidents"] = {}
	Life.ensure(sim.state)
	sim.state.town["incidents"]["mult"] = 20.0
	var seen := {}
	for i: int in 7 * DAY:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "incident_started":
				seen[str(e["def"])] = true
	check(not seen.has("bandit_raid"), "no raid in year 1")
	check(not seen.has("kidnapping"), "no kidnapping in year 1")
	check(seen.has("altercation"), "brawls do happen")


func test_off_no_incidents() -> void:
	var sim := _sim("life_bandits", false)
	for i: int in 180:
		for e: Dictionary in sim.step():
			check(not str(e.get("type", "")).begins_with("incident"), "no incidents with the life off")
