extends "res://tests/test_case.gd"
## Games 5 (docs/gdd/04f_vida_y_fiestas.md §4.26.1; docs/contratos/juegos.md): the joust. The triangle of stances, the
## points (helm unhorses, chest 2, shield 1 and its half point for sure), the passes and the draw, the reading of the
## seat, «Resolver sin jugar» equal to following the gesture, who may enter (Ciudadano), the entry fee, the prize and
## the favour.

const HUGO: String = "chr_0001"

var cat := Catalog.load_from()
var g: Dictionary = cat.games


func _init() -> void:
	GameMatch.verbose = false


func _p(over: Dictionary = {}) -> Dictionary:
	var p := Games.preset_player(g, "preset:regular_even")
	(p["stats"] as Dictionary).merge(over, true)
	return p


func test_triangle() -> void:
	var m := JoustMatch.create(g, "tri", 1, [_p(), _p()], 0)
	check(m.beats("shield", "helm"), "al escudo beats al yelmo")
	check(m.beats("helm", "chest"), "al yelmo beats al pecho")
	check(m.beats("chest", "shield"), "al pecho beats al escudo")
	for s: String in JoustMatch.STANCES:
		check(not m.beats(s, s), "a stance does not beat itself")
		eq(m.beats(m.counter_of(s), s), true, "the counter of %s beats it" % s)


func test_points_and_end() -> void:
	var saw := {}
	for i: int in 300:
		var m := JoustMatch.create(g, "j%d" % i, 2, [_p(), _p()], -1)
		check(m.over(), "the joust ends")
		var r := m.result()
		saw[str(r["how"])] = true
		for rec: Dictionary in m.log_entries():
			var st: Array = rec["stances"]
			for s: int in [0, 1]:
				var aim := m.aim_of(str(st[s]))
				var covered := m.cover_of(str(st[1 - s])) == aim
				var gp := float((rec["got"] as Array)[s])
				if covered:
					eq(gp, 0.5 if aim == "shield" else 0.0, "a covered %s gives its safe part" % aim)
				elif aim == "shield":
					check(gp in [0.5, 1.0], "the shield: half a point for sure")
				elif aim == "chest":
					check(gp in [0.0, 2.0], "the chest: 2 or nothing")
		if str(r["how"]) == "unhorsed":
			check(int(r["winner"]) >= 0, "unhorsing wins")
		if str(r["how"]) == "points":
			var pts: Array = m.d["points"]
			eq(int(r["winner"]), 0 if float(pts[0]) > float(pts[1]) else 1, "the most points win")
			check(int(m.d["pass"]) >= 2, "after three passes at least")
	for how: String in ["unhorsed", "points"]:
		check(saw.has(how), "a joust ends sometimes by %s" % how)


func test_reading_and_follow_equals_auto() -> void:
	var m := JoustMatch.create(g, "rd", 3, [_p(), _p()], 0)
	eq(str(m.view(0)["role"]), "blind", "the first pass is blind")
	m.choose(0, "shield")
	if not m.over():
		eq(str(m.view(0)["role"]), "lead", "then side 0 leads")
	var same := 0
	for i: int in 200:
		var a := JoustMatch.create(g, "f%d" % i, 5, [_p(), _p()], -1)
		var b := JoustMatch.create(g, "f%d" % i, 5, [_p(), _p()], 0)
		var guard := 0
		while not b.over() and guard < 10:
			guard += 1
			b.choose(0, b.ai_move(0))
		same += int(a.d["log"] == b.d["log"])
	eq(same, 200, "following the gesture is exactly «Resolver sin jugar»")


func test_fixed_stances_lose() -> void:
	var won := {"auto": 0, "shield": 0, "helm": 0}
	for i: int in 400:
		won["auto"] += int(int(JoustMatch.create(g, "x%d" % i, 6, [_p(), _p()], -1).result()["winner"]) == 0)
		for st: String in ["shield", "helm"]:
			var m := JoustMatch.create(g, "x%d" % i, 6, [_p(), _p()], 0)
			var guard := 0
			while not m.over() and guard < 10:
				guard += 1
				m.choose(0, st)
			won[st] += int(int(m.result()["winner"]) == 0)
	check(int(won["shield"]) < int(won["auto"]), "always at the shield loses (%d < %d)" % [won["shield"], won["auto"]])
	check(int(won["helm"]) < int(won["auto"]), "always at the helm loses (%d < %d)" % [won["helm"], won["auto"]])


func test_entry_title_fee_prize_and_favor() -> void:
	var r := NewGame.from_scenario("town_e_start", 1)
	var sim := Sim.new(r["state"], cat)
	var fam := str(sim.state.characters[HUGO]["family"])
	var o := {"type": "game_play", "actor": HUGO, "game": "joust", "opponents": ["preset:knight_young"]}
	var ev := sim.step([o])
	var reason := ""
	for e: Dictionary in ev:
		if str(e["type"]) == "order_refused":
			reason = str(e["reason"])
	eq(reason, "no_title", "a commoner may not joust (Ciudadano or more)")
	sim.state.families[fam]["title"] = "citizen"
	(sim.state.characters[HUGO]["stats"] as Dictionary).merge({"dexterity": 9, "empathy": 8}, true)
	var won := false
	for i: int in 15:
		var g0 := Money.gold(sim.state, fam)
		var rep0 := Reputation.of(sim.state, fam)
		var o2: Dictionary = o.duplicate()
		o2["match"] = "joust_test|%d" % i
		var played := {}
		for e: Dictionary in sim.step([o2]):
			check(str(e["type"]) != "order_refused", "a citizen may joust: %s" % e.get("reason", ""))
			if str(e["type"]) == "game_played":
				played = e
		var fee := int(g["joust"]["entry_fee"])
		if bool(played.get("won", false)):
			won = true
			eq(Money.gold(sim.state, fam) - g0, int(g["joust"]["prize"]["gold"]) - fee, "the purse minus the horse's rent")
			eq(Reputation.of(sim.state, fam) - rep0, int(g["joust"]["prize"]["reputation"]), "reputation +10")
		else:
			eq(Money.gold(sim.state, fam) - g0, -fee, "the horse and the lance are paid anyway")
	check(won, "a skilled rider wins some joust in 15")
