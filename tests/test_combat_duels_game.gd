extends "res://tests/test_case.gd"
## Duels in the game (docs/gdd/04e_combate.md §4e.3-§4e.5, docs/contratos/duelo.md, sim/combat/duels.gd): save v15,
## the challenge and its refusals, the three causes, the NPC's answer, the call to the ground at dawn, the played duel,
## the no-show, NPC against NPC, the brawl, the consequences and determinism.

const HUGO: String = "chr_0001"
const BERNAT: String = "chr_0006"

var cat := Catalog.load_from()


func _init() -> void:
	Duel.verbose = false


func _sim(seed: int = 1) -> Sim:
	var r := NewGame.from_scenario("town_e_start", seed)
	var sim := Sim.new(r["state"], cat)
	# Bernat out in the street, next to Hugo (the challenge is in person)
	var b: Dictionary = sim.state.characters[BERNAT]
	b["location"] = ""
	b["position"] = [21, 21]
	b["path"] = []
	var h: Dictionary = sim.state.characters[HUGO]
	h["location"] = ""
	h["path"] = []
	return sim


func _challenge(sim: Sim, actor: String = HUGO, target: String = BERNAT, cause: String = "rivalry") -> Array:
	return sim.step([{"type": "duel_challenge", "actor": actor, "target": target, "cause": cause,
		"kind": "first_blood"}])


func _refused(events: Array) -> String:
	for e: Dictionary in events:
		if str(e["type"]) == "order_refused":
			return str(e["reason"])
	return ""


func _the_duel(sim: Sim) -> Dictionary:
	var o: Dictionary = Duels.open_duels(sim.state)
	return o[o.keys()[0]] if not o.is_empty() else {}


## Runs until the open duel is fighting (or closed), at most `limit` minutes.
func _until_fighting(sim: Sim, limit: int = 2 * 1440) -> Dictionary:
	for i in limit:
		var d := _the_duel(sim)
		if d.is_empty() or str(d["status"]) == "fighting":
			return d
		sim.step()
	return _the_duel(sim)


func test_save_v15_round_trip_and_migration() -> void:
	check(WorldState.VERSION >= 15, "duels come with v15")
	var sim := _sim()
	_challenge(sim)
	var back: WorldState = SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(sim.state.to_dict()), "an open duel comes back")
	var d := sim.state.to_dict()
	d["version"] = 14
	d.erase("duels")
	var r := SaveFile.from_text(JSON.stringify(d))
	check(r["ok"], "a v14 game loads")
	eq((r["state"] as WorldState).duels, {"open": {}, "closed": []}, "and gets an empty book of duels")


func test_refusals() -> void:
	var sim := _sim()
	eq(Duels.challenge_status(sim, HUGO, BERNAT, "rivalry"), "", "the rival of the trade, at hand")
	eq(Duels.challenge_status(sim, HUGO, BERNAT, "offense"), "no_cause", "no insult between them")
	eq(Duels.challenge_status(sim, HUGO, "chr_0002", ""), "same_family", "not one of your own")
	eq(Duels.challenge_status(sim, HUGO, BERNAT, "rivalry", "surrender"), "kind_locked", "O-C11: first blood only")
	eq(Duels.challenge_status(sim, HUGO, BERNAT, "rivalry", "to_death"), "kind_locked", "O-C3: never to the death")
	var town := ""
	for id: String in sim.state.characters:
		if str(sim.state.characters[id].get("family", "")) not in ["fam_0001", "fam_0003"] and Kin.is_adult(sim, id):
			town = id
			break
	eq(Duels.challenge_status(sim, HUGO, town, ""), "no_cause", "a townsperson with no quarrel: no cause")
	sim.state.characters[BERNAT]["position"] = [35, 21]
	eq(Duels.challenge_status(sim, HUGO, BERNAT, "rivalry"), "too_far", "in person")
	eq(_refused(_challenge(sim)), "too_far", "the order says why")
	sim.state.characters[BERNAT]["position"] = [21, 21]
	var young := ""
	for id: String in sim.state.characters:
		if Kin.alive(sim.state, id) and Kin.age(sim, id) < 16:
			young = id
			break
	if young != "":
		eq(Duels.challenge_status(sim, HUGO, young, ""), "too_young", "nobody under 16")
	_challenge(sim)
	eq(Duels.challenge_status(sim, HUGO, BERNAT, "rivalry"), "busy", "one duel at a time")


func test_offense_and_courtship_causes() -> void:
	var sim := _sim()
	sim.step([{"type": "npc_insult", "actor": BERNAT, "target": HUGO}])
	var causes := Duels.causes(sim, HUGO, BERNAT).map(func(c: Dictionary) -> String: return str(c["cause"]))
	check("offense" in causes, "an insult is a cause (%s)" % [causes])
	check(not "offense" in Duels.causes(sim, BERNAT, HUGO).map(func(c: Dictionary) -> String: return str(c["cause"])),
		"for the insulted, not for who insulted")
	var lady := ""
	for id: String in sim.state.characters:
		if Kin.alive(sim.state, id) and Kin.is_single(sim.state, id) and Kin.is_adult(sim, id) and \
				bool(sim.state.characters[id].get("female", false)) and id != HUGO and id != BERNAT:
			lady = id
			break
	check(lady != "", "a single adult in town")
	Courtship.relation(sim.state, HUGO, lady)["affinity"] = 60
	Courtship.relation(sim.state, BERNAT, lady)["affinity"] = 45
	eq(Duels.courted_by_both(sim, HUGO, BERNAT), lady, "two suitors of the same person")
	_challenge(sim, HUGO, BERNAT, "courtship")
	var d := _the_duel(sim)
	eq(str(d["cause"]), "courtship", "a duel for love")
	eq(str(d["about"]), lady, "for her")


func test_npc_answers_and_the_duel_at_dawn() -> void:
	var sim := _sim()
	var ev := _challenge(sim)
	eq(_refused(ev), "", "the challenge is made")
	check(ev.any(func(e: Dictionary) -> bool: return str(e["type"]) == "duel_challenged"), "duel_challenged")
	sim.step()  # the NPC answers in the next minute
	var d := _the_duel(sim)
	check(not d.is_empty(), "the rival accepts (an even duel, witnesses saw it)")
	eq(str(d["status"]), "accepted", "accepted")
	eq(Clock.minute_of_day(int(d["at"])), 360, "at dawn")
	check(Clock.day(int(d["at"])) == Clock.day(int(sim.state.clock["minute"])) + 1, "the next day")
	d = _until_fighting(sim)
	eq(str(d["status"]), "fighting", "both came to the plaza at the hour (%s)" % [d.get("outcome", "")])
	eq(int(d["player_side"]), 0, "Hugo is the player's side")
	var rep0 := Reputation.of(sim.state, "fam_0001")
	var guard := 0
	while not Duels.open_duels(sim.state).is_empty() and guard < 30:
		var v := Duel.wrap(cat.combat, d["duel"]).view(0)
		var act: String = "parry" if not "strike" in (v["allowed"] as Array) else "strike"
		var r := sim.step([{"type": "duel_move", "actor": HUGO, "duel": d["id"], "action": act}])
		eq(_refused(r), "", "lance %d accepted" % guard)
		guard += 1
	check(Duels.open_duels(sim.state).is_empty(), "the duel closes")
	var closed: Dictionary = Duels.book(sim.state)["closed"][0]
	check(str(closed["outcome"]) in ["fought", "draw"], "fought to the end (%s)" % closed["outcome"])
	check(Reputation.of(sim.state, "fam_0001") != rep0 or str(closed["outcome"]) == "draw", "honour moved")
	var told := false
	for e: Dictionary in sim.state.chronicle:
		told = told or (str(e["kind"]) == "duel" and str(e.get("family", "")) == "fam_0001")
	check(told, "the chronicle tells it")
	check(sim.state.notices.any(func(n: Dictionary) -> bool: return str(n["key"]).begins_with("notice.duel_")),
		"a notice")
	eq(Duels.challenge_status(sim, HUGO, BERNAT, "rivalry"), "cooldown", "not again this season")


func test_resolve_without_playing_and_no_show() -> void:
	var sim := _sim()
	_challenge(sim)
	sim.step()
	var d := _until_fighting(sim)
	sim.step([{"type": "duel_auto", "actor": HUGO, "duel": d["id"]}])
	check(Duels.open_duels(sim.state).is_empty(), "«Resolver sin jugar» ends it at once")
	var sim2 := _sim()
	_challenge(sim2)
	sim2.step()
	var d2 := _the_duel(sim2)
	var at := int(d2["at"])
	while int(sim2.state.clock["minute"]) < at - 1:
		sim2.step()
	sim2.state.characters[HUGO]["position"] = [2, 20]  # the player went elsewhere instead
	sim2.state.characters[HUGO]["path"] = []
	var rep0 := Reputation.of(sim2.state, "fam_0001")
	while int(sim2.state.clock["minute"]) <= at + 1:
		sim2.step()
	var c: Dictionary = Duels.book(sim2.state)["closed"][0]
	eq(str(c["outcome"]), "no_show", "Hugo did not come")
	eq(str(c["winner"]), BERNAT, "and loses it")
	check(Reputation.of(sim2.state, "fam_0001") < rep0, "it costs honour")


func test_npc_against_npc_is_played_by_the_ai() -> void:
	var sim := _sim()
	var other := ""
	for id: String in sim.state.characters:
		var f := str(sim.state.characters[id].get("family", ""))
		if f != "fam_0001" and f != "fam_0003" and Kin.is_adult(sim, id) and Kin.alive(sim.state, id):
			other = id
			break
	sim.state.characters[other]["location"] = ""
	sim.state.characters[other]["position"] = [22, 21]
	sim.step([{"type": "npc_insult", "actor": BERNAT, "target": other}])
	_challenge(sim, other, BERNAT, "offense")
	sim.step()
	var d := _the_duel(sim)
	if d.is_empty():
		var c: Dictionary = Duels.book(sim.state)["closed"][0]
		eq(str(c["outcome"]), "refused", "Bernat refused")
		return
	sim.run_minutes(1440 + 400)
	check(Duels.open_duels(sim.state).is_empty(), "nobody of the player: the AI plays it at the hour")
	var c: Dictionary = Duels.book(sim.state)["closed"][0]
	check(str(c["outcome"]) in ["fought", "draw", "no_show"], "it was decided (%s)" % c["outcome"])


func test_title_far_above_refuses_for_free() -> void:
	var sim := _sim()
	sim.state.families["fam_0003"]["title"] = "baron"
	_challenge(sim)
	var rep0 := Reputation.of(sim.state, "fam_0003")
	sim.step()
	var c: Dictionary = Duels.book(sim.state)["closed"][0]
	eq(str(c["outcome"]), "refused", "a baron does not stoop to a commoner (O-C8)")
	eq(Reputation.of(sim.state, "fam_0003"), rep0, "and it costs him nothing")


func test_brawl_is_a_crime_with_witnesses() -> void:
	var sim := _sim()
	var facts0: int = (sim.state.justice.get("facts", []) as Array).size()
	var r := sim.step([{"type": "duel_brawl", "actor": HUGO, "target": BERNAT}])
	eq(_refused(r), "", "a fight on the spot")
	var e: Array = r.filter(func(x: Dictionary) -> bool: return str(x["type"]) == "duel_brawl")
	eq(e.size(), 1, "duel_brawl")
	if int(e[0]["witnesses"]) > 0:
		eq((sim.state.justice["facts"] as Array).size(), facts0 + 1, "seen: a brawl fact against Hugo's family")
		eq(str((sim.state.justice["facts"] as Array).back()["charge"]), "brawl", "charge brawl")


func test_the_held_duellists_are_not_taken_away() -> void:
	var sim := _sim()
	_challenge(sim)
	sim.step()
	var d := _until_fighting(sim)
	eq(str(d["status"]), "fighting", "Bernat came although his AI runs his forge")
	check(Duels.holds(sim.state, BERNAT), "held while fighting")


func test_same_seed_same_duel_and_replay() -> void:
	var runs: Array = []
	for i in 2:
		var sim := _sim(7)
		_challenge(sim)
		sim.step()
		var d := _until_fighting(sim)
		sim.step([{"type": "duel_move", "actor": HUGO, "duel": d["id"], "action": "parry"}])
		sim.step([{"type": "duel_auto", "actor": HUGO, "duel": d["id"]}])
		runs.append(sim.state_hash())
	eq(runs[0], runs[1], "same seed, same orders: same game")
	var a := _sim(9)
	a.record = true
	var start := JSON.stringify(a.state.to_dict())
	_challenge(a)
	for i in 1500:
		a.step()
	var b := Sim.new(SaveFile.from_text(start)["state"], cat)
	var rec: Array = a.recording
	var j := 0
	for i in 1501:
		var orders: Array = []
		while j < rec.size() and int(rec[j]["minute"]) == int(b.state.clock["minute"]):
			orders.append(rec[j]["order"])
			j += 1
		b.step(orders)
	eq(b.state_hash(), a.state_hash(), "the replay of the recorded orders gives the same duel")
