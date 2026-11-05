extends "res://tests/test_case.gd"
## Games 1 (docs/gdd/04f_vida_y_fiestas.md §4.26.7, §4.26.9; docs/contratos/juegos.md): «azar», «tres dados a la mayor»
## and pulso: their rules, determinism, «Resolver sin jugar» equal to playing well, and the order game_play (the game
## replayed by the sim, its money and its refusals).

const HUGO: String = "chr_0001"
const BERNAT: String = "chr_0006"

var cat := Catalog.load_from()
var g: Dictionary = cat.games


func _init() -> void:
	GameMatch.verbose = false


func _p(preset: String = "regular_even", over: Dictionary = {}) -> Dictionary:
	var p := Games.preset_player(g, "preset:" + preset)
	(p["stats"] as Dictionary).merge(over, true)
	return p


func _sim(seed: int = 1) -> Sim:
	var r := NewGame.from_scenario("town_e_start", seed)
	return Sim.new(r["state"], cat)


func _refused(events: Array) -> String:
	for e: Dictionary in events:
		if str(e["type"]) == "order_refused":
			return str(e["reason"])
	return ""


func _played(events: Array) -> Dictionary:
	for e: Dictionary in events:
		if str(e["type"]) == "game_played":
			return e
	return {}


func test_azar_rules() -> void:
	eq(GameRules.total(GameRules.WAYS_3D6.values()), 216, "three dice: 216 ways")
	var saw := {}
	for i: int in 400:
		var m := AzarMatch.create(g, "t%d" % i, 11, [_p(), _p()], -1, 10)
		var r := m.result()
		check(m.over(), "azar always ends")
		var how := str(r["how"])
		saw[how] = true
		var first := int((m.d["throws"] as Array)[0]["total"])
		if how == "azar":
			check(m.is_azar(first), "an azar game ends on an azar first throw")
			eq(int(r["winner"]), m.thrower(), "azar: the thrower wins")
		if how == "reazar":
			eq(int(r["winner"]), 1 - m.thrower(), "reazar: the thrower loses")
		if how == "chance":
			var last := int((m.d["throws"] as Array)[-1]["total"])
			eq(last, int((m.d["chances"] as Array)[int(r["winner"])]), "the last throw is the winner's chance")
		eq(int((r["net"] as Array)[0]) + int((r["net"] as Array)[1]), 0, "azar is zero-sum")
		check(abs(int((r["net"] as Array)[0])) in [10, 20], "the stake or its double")
	for how: String in ["azar", "reazar", "chance"]:
		check(saw.has(how), "azar ends sometimes by %s" % how)


func test_azar_doubling_and_cap() -> void:
	# a played side: offered the double when it is the thrower and both chances are known
	var found := false
	for i: int in 200:
		var m := AzarMatch.create(g, "dbl%d" % i, 3, [_p(), _p()], 0, 10, {"thrower": 0})
		if m.over():
			continue
		var v := m.view(0)
		eq(str(v["phase"]), "offer", "the thrower decides first")
		eq(m.allowed(0), ["double", "pass"], "double or pass")
		check(bool(m.choose(0, "double")["ok"]), "doubling is accepted as a move")
		found = true
		if str(m.result()["how"]) == "refused":
			eq(int((m.result()["net"] as Array)[0]), 10, "a refused double wins the stake as it was")
		else:
			eq(int(m.d["stake_now"]), 20, "an accepted double plays at 20")
			eq(absi(int((m.result()["net"] as Array)[0])), 20, "and is won or lost at 20")
		break
	check(found, "some game reaches the decision")
	var m50 := AzarMatch.create(g, "cap", 3, [_p(), _p()], 0, 50, {"thrower": 0})
	if not m50.over():
		eq(m50.allowed(0), ["pass"], "at the cap (50) one cannot double")


func test_azar_same_seed_same_game() -> void:
	var a := AzarMatch.create(g, "same", 5, [_p(), _p()], -1, 10)
	var b := AzarMatch.create(g, "same", 5, [_p(), _p()], -1, 10)
	eq(a.d["throws"], b.d["throws"], "same seed, same throws")
	eq(a.result(), b.result(), "same result")
	var c := AzarMatch.create(g, "other", 5, [_p(), _p()], -1, 10)
	check(c.d["throws"] != a.d["throws"], "another match id, other dice")


func test_azar_auto_equals_playing_well_and_fixed_lose() -> void:
	var ev := {"auto": 0.0, "good": 0.0, "never": 0.0, "random": 0.0}
	var n := 800
	for i: int in n:
		var ps := [_p(), _p()]
		ev["auto"] += float(AzarMatch.create(g, "b%d" % i, 9, ps, -1, 10).result()["net"][0])
		for pol: String in ["good", "never", "random"]:
			var m := AzarMatch.create(g, "b%d" % i, 9, ps, 0, 10)
			var guard := 0
			while not m.over() and guard < 10:
				guard += 1
				var v := m.view(0)
				var act := ""
				if pol == "good":
					if str(v["phase"]) == "offer":
						act = "double" if float(v["win"]) > float(v["double_at"]) and "double" in m.allowed(0) else "pass"
					else:
						act = "accept" if float(v["win"]) >= float(v["accept_at"]) else "refuse"
				elif pol == "never":
					act = "pass" if str(v["phase"]) == "offer" else "refuse"
				else:
					act = GameRules.pick(m.allowed(0), 1, "r%d" % i, guard, "x")
				m.choose(0, act)
			ev[pol] += float(m.result()["net"][0])
	eq(ev["good"], ev["auto"], "«Resolver sin jugar» is exactly playing what the screen says, game by game")
	check(ev["never"] < ev["auto"], "never doubling nor accepting loses gold (%s < %s)" % [ev["never"], ev["auto"]])
	check(ev["random"] < ev["auto"], "playing at random loses gold (%s < %s)" % [ev["random"], ev["auto"]])


func test_mayor_showdown_and_pot() -> void:
	for i: int in 200:
		var m := MayorMatch.create(g, "m%d" % i, 4, [_p(), _p(), _p()], -1, 10)
		check(m.over(), "the AI decides at once")
		var net: Array = m.result()["net"]
		var dec: Array = m.d["decisions"]
		var stayers := 0
		var sum := 0
		for j: int in 3:
			sum += int(net[j])
			if str(dec[j]) == "stay":
				stayers += 1
			else:
				eq(int(net[j]), -5, "who retires loses half the stake")
		if stayers > 0:
			eq(sum, 0, "with someone going on, the pot is shared out (zero-sum)")
		else:
			eq(sum, -15, "nobody goes on: all lose half")
	var m2 := MayorMatch.create(g, "seen", 4, [_p(), _p()], 0, 10)
	var v := m2.view(0)
	eq((v["dice"][1] as Array)[2], 0, "the rival's die under the cup is hidden")
	check(int((v["dice"][0] as Array)[2]) > 0, "one's own hidden die is seen")
	eq(m2.allowed(0), ["stay", "retire"], "stay or retire")
	m2.choose(0, "stay")
	check(m2.over(), "the game ends when the played side decides")
	check(int((m2.view(0)["dice"][1] as Array)[2]) > 0, "at the end every die is shown")


func test_mayor_boastful_always_stays() -> void:
	for i: int in 50:
		var m := MayorMatch.create(g, "bo%d" % i, 4, [_p(), _p("regular_boastful")], -1, 10)
		eq(str((m.d["decisions"] as Array)[1]), "stay", "el atrevido dobla siempre")


func test_pulso_rules() -> void:
	for i: int in 300:
		var m := PulsoMatch.create(g, "p%d" % i, 2, [_p(), _p()], -1)
		check(m.over(), "pulso always ends")
		var r := m.result()
		var pts: Array = m.d["points"]
		check(int(pts[0]) + int(pts[1]) <= 3 and maxi(int(pts[0]), int(pts[1])) == 2, "two pushes of three win")
		eq(int(r["winner"]), 0 if int(pts[0]) == 2 else 1, "who takes two wins")
		for rec: Dictionary in m.log_entries():
			check(int(rec["winner"]) in [0, 1], "every push has a winner")
	var m2 := PulsoMatch.create(g, "pp", 2, [_p(), _p()], 0)
	eq(str(m2.view(0)["role"]), "blind", "the first push is blind")
	m2.choose(0, "push")
	if not m2.over():
		eq(str(m2.view(0)["role"]), "lead", "the second push: side 0 leads")
		check(float(m2.view(0)["read_by"]) > 0.0, "and the screen says how well the rival reads it")


func test_pulso_follow_the_cue_equals_auto() -> void:
	var same := 0
	for i: int in 300:
		var ps := [_p(), _p()]
		var a := PulsoMatch.create(g, "f%d" % i, 8, ps, -1)
		var b := PulsoMatch.create(g, "f%d" % i, 8, ps, 0)
		var guard := 0
		while not b.over() and guard < 10:
			guard += 1
			var v := b.view(0)
			b.choose(0, b.ai_choice(0, str(v["role"]), str((v["cue"] as Dictionary).get("id", ""))))
		same += int(a.result()["winner"] == b.result()["winner"] and a.d["log"] == b.d["log"])
	eq(same, 300, "following the gesture is exactly «Resolver sin jugar», push by push")


func test_order_game_play_money_and_replay() -> void:
	var sim := _sim()
	var fam := str(sim.state.characters[HUGO]["family"])
	var gold0 := Money.gold(sim.state, fam)
	var o := {"type": "game_play", "actor": HUGO, "game": "azar", "opponents": [BERNAT], "stake": 10, "moves": [],
		"auto": true}
	var ev := sim.step([o])
	eq(_refused(ev), "", "a valid game is played")
	var e := _played(ev)
	check(not e.is_empty(), "game_played is emitted")
	eq(Money.gold(sim.state, fam) - gold0, int(e["net"]), "the family's gold moves by the game's net")
	# the same game resolved by hand gives the same
	var spec := Games.spec_of(sim, o)
	check(not spec.has("reason"), "a spec for a valid order")
	# replay: the sim replays the moves of the screen
	var sim2 := _sim()
	var o2 := o.duplicate()
	var spec2 := Games.spec_of(sim2, o2)
	var m := Games.create(cat.games, spec2)
	var moves: Array = []
	while not m.over():
		var v := m.view(0)
		var act := str(m.allowed(0)[0])
		moves.append(act)
		m.choose(0, act)
	o2["moves"] = moves
	o2["auto"] = false
	var ev2 := sim2.step([o2])
	eq(_refused(ev2), "", "a finished game with its moves is accepted")
	eq(int(_played(ev2)["net"]), int(m.result()["net"][0]), "the sim's replay gives the screen's result")


func test_order_game_play_refusals() -> void:
	var sim := _sim()
	var base := {"type": "game_play", "actor": HUGO, "game": "azar", "opponents": [BERNAT], "stake": 10}
	var cases := [
		[{"game": "chess"}, "unknown_game"],
		[{"actor": "chr_nobody"}, "unknown_actor"],
		[{"opponents": []}, "bad_players"],
		[{"opponents": [HUGO]}, "bad_players"],
		[{"stake": 7}, "bad_stake"],
		[{"stake": 100}, "bad_stake"],
		[{"moves": ["fly"]}, "bad_move"],
		[{"opts": {"house": "bld_nowhere"}}, "unknown_house"],
		[{"game": "mayor", "opponents": [BERNAT, "preset:regular_even", "preset:regular_even#2", "preset:regular_cheat"]},
			"bad_players"],
	]
	for c: Array in cases:
		var o: Dictionary = base.duplicate(true)
		o.merge(c[0], true)
		eq(_refused(sim.step([o])), str(c[1]), "refused: %s" % c[1])
	var fam := str(sim.state.characters[HUGO]["family"])
	sim.state.families[fam]["gold"] = 15
	eq(_refused(sim.step([base])), "not_enough_gold", "one must be able to pay the double")
	sim.state.families[fam]["gold"] = 1000
	var o3: Dictionary = base.duplicate(true)
	o3["game"] = "mayor"
	o3["auto"] = false
	eq(_refused(sim.step([o3])), "unfinished", "without auto a game must come finished")


func test_house_takes_its_rake() -> void:
	var sim := _sim()
	var fam := str(sim.state.characters[HUGO]["family"])
	var house := ""
	for b: String in sim.state.buildings:
		if Money.family_of(sim.state, b) != "" and Money.family_of(sim.state, b) != fam:
			house = b
			break
	check(house != "", "a building of another family to play in")
	var owner := Money.family_of(sim.state, house)
	var won := false
	for i: int in 40:
		var g0 := Money.gold(sim.state, owner)
		var ev := sim.step([{"type": "game_play", "actor": HUGO, "game": "azar", "opponents": ["preset:regular_even"],
			"stake": 10, "opts": {"house": house}}])
		var e := _played(ev)
		if int(e.get("house_cut", 0)) > 0:
			eq(Money.gold(sim.state, owner) - g0, int(e["house_cut"]), "the house's owner takes the rake")
			check(int(e["net"]) < 10 or int(e["net"]) < 20, "the winner gets less than the stake")
			won = true
			break
	check(won, "Hugo wins some game in 40")


func test_daily_losses_warn() -> void:
	var sim := _sim()
	var fam := str(sim.state.characters[HUGO]["family"])
	sim.state.families[fam]["gold"] = 5000
	var warned := false
	for i: int in 60:
		sim.step([{"type": "game_play", "actor": HUGO, "game": "mayor", "opponents": ["preset:regular_boastful"],
			"stake": 50, "moves": ["retire"], "auto": true}])
		for n: Dictionary in sim.state.notices:
			if str(n.get("key", "")) == "notice.games_losses":
				warned = true
	check(warned, "losing more than 100 in a day warns (O-V8)")
	var count := 0
	for n: Dictionary in sim.state.notices:
		count += int(str(n.get("key", "")) == "notice.games_losses")
	eq(count, 1, "once a day")
