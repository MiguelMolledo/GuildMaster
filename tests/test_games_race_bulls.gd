extends "res://tests/test_case.gd"
## Games 7-8 (docs/gdd/04f_vida_y_fiestas.md §4.26.4, §4.26.5; docs/contratos/juegos.md): the horse race (four
## stretches, the wind, the bend's stumble, the exact plan) and running the bull (the sign, the payoff, no wounds:
## O-V5 a), each with «Resolver sin jugar» equal to following what the screen shows, and their orders.

const HUGO: String = "chr_0001"

var cat := Catalog.load_from()
var g: Dictionary = cat.games


func _init() -> void:
	GameMatch.verbose = false


func _riders(list: String) -> Array:
	var p := Games.preset_player(g, "preset:regular_even")
	(p["stats"] as Dictionary)["dexterity"] = 4
	var ps: Array = [p]
	for r: Variant in g[list]["riders" if list == "race" else "mozos"]:
		ps.append(Games.preset_player(g, "preset:" + str(r)))
	return ps


func test_race_stretches_and_wind() -> void:
	for i: int in 100:
		var m := RaceMatch.create(g, "r%d" % i, 1, _riders("race"), -1)
		check(m.over(), "the race ends")
		eq(m.log_entries().size(), 4, "four stretches")
		for e: Dictionary in m.log_entries():
			for k: int in m.n_players():
				var w := int((e["wind"] as Array)[k])
				check(w >= 0 and w <= int(m.horse(k)["wind"]), "the wind stays within the horse's")
			if bool((e["stumbles"] as Array).has(true)):
				eq(str(e["id"]), "bend", "one stumbles only in the bend")
		var w0 := int(m.result()["winner"])
		for k: int in m.n_players():
			check(float(m.d["dist"][w0]) >= float(m.d["dist"][k]), "the longest run wins")


func test_race_no_wind_only_reserve() -> void:
	var m := RaceMatch.create(g, "nw", 1, _riders("race"), 0)
	(m.d["wind"] as Array)[0] = 0
	eq(m.allowed(0), ["reserve"], "a horse without wind can only reserve")
	(m.d["wind"] as Array)[0] = 2
	eq(m.allowed(0), ["reserve", "keep"], "with 2, not press")


func test_race_plan_is_auto() -> void:
	var same := 0
	for i: int in 200:
		var a := RaceMatch.create(g, "p%d" % i, 2, _riders("race"), -1)
		var b := RaceMatch.create(g, "p%d" % i, 2, _riders("race"), 0)
		var guard := 0
		while not b.over() and guard < 8:
			guard += 1
			b.choose(0, b.ai_move(0))
		same += int(a.d["log"] == b.d["log"])
	eq(same, 200, "following the plan is exactly «Resolver sin jugar»")


func test_bulls_payoff_and_no_wounds() -> void:
	for i: int in 200:
		var m := BullsMatch.create(g, "b%d" % i, 1, _riders("bulls"), -1)
		check(m.over(), "three charges and done")
		eq(m.log_entries().size(), 3 * 4, "three charges of four mozos")
		for e: Dictionary in m.log_entries():
			eq(float(e["got"]), m.payoff(str(e["action"]), str(e["bull"])), "the applause of the table")
			if str(e["action"]) == "safe":
				eq(float(e["got"]), 0.0, "behind the carts nothing is lost")
	var m2 := BullsMatch.create(g, "solo", 1, [_riders("bulls")[0]], 0)
	var v := m2.view(0)
	check(str(v["cue"].get("id", "")) in ["charge", "feint", "hook"], "the bull gives a sign")
	var t := 0.0
	for x: Variant in (v["odds"] as Dictionary).values():
		t += float(x)
	near(t, 1.0, 0.001, "the odds of the bull add up")


func test_bulls_follow_equals_auto_and_fixed_lose() -> void:
	var auto := 0.0
	var always_break := 0.0
	var same := 0
	for i: int in 300:
		var ps := [_riders("bulls")[0]]
		var a := BullsMatch.create(g, "f%d" % i, 3, ps, -1)
		var b := BullsMatch.create(g, "f%d" % i, 3, ps, 0)
		var c := BullsMatch.create(g, "f%d" % i, 3, ps, 0)
		var guard := 0
		while not b.over() and guard < 6:
			guard += 1
			b.choose(0, b.ai_move(0))
		guard = 0
		while not c.over() and guard < 6:
			guard += 1
			c.choose(0, "break")
		same += int(a.d["log"] == b.d["log"])
		auto += float((a.d["points"] as Array)[0])
		always_break += float((c.d["points"] as Array)[0])
	eq(same, 300, "following the sign is exactly «Resolver sin jugar»")
	check(always_break < auto, "always breaking away loses applause (%.1f < %.1f)" % [always_break, auto])


func test_orders_race_and_bulls() -> void:
	var r := NewGame.from_scenario("town_e_start", 1)
	var sim := Sim.new(r["state"], cat)
	var fam := str(sim.state.characters[HUGO]["family"])
	var riders: Array = []
	for x: Variant in g["race"]["riders"]:
		riders.append("preset:" + str(x))
	for e: Dictionary in sim.step([{"type": "game_play", "actor": HUGO, "game": "race", "opponents": riders}]):
		check(str(e["type"]) != "order_refused", "a race: %s" % e.get("reason", ""))
	var rep0 := Reputation.of(sim.state, fam)
	var played := {}
	for e: Dictionary in sim.step([{"type": "game_play", "actor": HUGO, "game": "bulls", "opponents": [],
			"match": "toros_test"}]):
		check(str(e["type"]) != "order_refused", "running the bull alone: %s" % e.get("reason", ""))
		if str(e["type"]) == "game_played":
			played = e
	var f: Dictionary = {}
	for x: Dictionary in played.get("facts", []):
		if str(x.get("kind", "")) == "bulls":
			f = x
	check(not f.is_empty(), "the bulls tell quiebros and frights")
	var want := int(f["breaks"]) * int(g["bulls"]["rep_per_break"]) + int(f["fails"]) * int(g["bulls"]["rep_per_fail"])
	if bool(played.get("won", false)):
		want += int(g["bulls"]["prize"]["reputation"])
	eq(Reputation.of(sim.state, fam) - rep0, want, "applause and jeers in reputation")
	if int(f["fails"]) > 0:
		var scared := false
		for em: Dictionary in sim.state.emotions.get(HUGO, []):
			scared = scared or str(em.get("state", em.get("id", ""))) == "scared"
		check(scared, "a fright leaves him scared (never wounded: O-V5 a)")
