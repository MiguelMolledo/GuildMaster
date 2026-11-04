extends "res://tests/test_case.gd"
## The duel «a tres tiempos» (docs/gdd/04e_combate.md, data/combat.json): the triangle, the gesture's reading, the
## breath, the end at the touches or the lances, determinism, and that the automatic way and a played duel give similar
## chances with the same attributes. Pure rules: no Sim, no world.

const N: int = 2000

var cat := Catalog.load_from()
var cfg: Dictionary = cat.combat


func _f(id: String, martial: int = 3, empathy: int = 3, constitution: int = 5, weapon: String = "fists",
		armor: bool = false) -> Dictionary:
	return CombatRules.fighter(id, {"martial": martial, "empathy": empathy, "constitution": constitution}, weapon, armor)


## Plays a duel with the player on side 0 choosing with `policy` (Callable(view: Dictionary, duel: Duel) -> String).
func _play(seed: int, a: Dictionary, b: Dictionary, policy: Callable, kind: String = "first_blood") -> Dictionary:
	var du := Duel.create(cfg, "t%d" % seed, seed, a, b, kind, 0)
	var guard := 0
	while not du.over() and guard < 64:
		var act := str(policy.call(du.view(0), du))
		var r := du.choose(0, act)
		if not bool(r["ok"]):
			du.choose(0, "parry")
		guard += 1
	return du.result()


## Wins / losses / draws of side 0 over N seeds.
func _rate(a: Dictionary, b: Dictionary, policy: Variant = null, kind: String = "first_blood") -> Dictionary:
	var w := 0
	var l := 0
	for s in N:
		var r: Dictionary
		if policy == null:
			r = Duel.auto(cfg, "t%d" % s, 1000 + s, a, b, kind)
		else:
			r = _play(1000 + s, a, b, policy as Callable, kind)
		if int(r["winner"]) == 0:
			w += 1
		elif int(r["winner"]) == 1:
			l += 1
	return {"win": float(w) / N, "lose": float(l) / N, "draw": float(N - w - l) / N}


func _follower(v: Dictionary, du: Duel) -> String:
	if str(v["role"]) == "read":
		return CombatRules.ai_choice(cfg, du.fighter(0), du.breath(0), "read", str(v["cue"]), [], 0, "", 0, 0)
	return CombatRules.ai_choice(cfg, du.fighter(0), du.breath(0), str(v["role"]), "", du.d["history"][1],
		int(du.d["seed"]), str(du.d["id"]), int(du.d["lance"]), 0)


func _random(v: Dictionary, du: Duel) -> String:
	var opts: Array = v["allowed"]
	return str(opts[floori(CombatRules.roll(int(du.d["seed"]), "rnd", int(v["lance"]), "pick") * opts.size())])


func _init() -> void:
	Duel.verbose = false  # thousands of duels: no logs (one duel's logs: the smoke script)


func test_data_loaded() -> void:
	check(not cfg.is_empty(), "data/combat.json is in the catalog")
	eq(CombatRules.ACTIONS.size(), (cfg["actions"] as Dictionary).size(), "three actions")


func test_triangle() -> void:
	check(CombatRules.beats(cfg, "strike", "feint"), "strike beats feint")
	check(CombatRules.beats(cfg, "feint", "parry"), "feint beats parry")
	check(CombatRules.beats(cfg, "parry", "strike"), "parry beats strike")
	for a: String in CombatRules.ACTIONS:
		check(not CombatRules.beats(cfg, a, a), "%s does not beat itself" % a)
		eq(CombatRules.counter_of(cfg, CombatRules.counter_of(cfg, CombatRules.counter_of(cfg, a))), a, "a cycle")
	# the winner of the exchange is the one the triangle says, whatever the touch roll does
	var a := _f("a")
	var b := _f("b")
	for s in 50:
		var r := CombatRules.resolve_lance(cfg, a, b, "parry", "strike", s, "tri", 0)
		eq(int(r["exchange"]), 0, "parry wins the exchange against strike")
		check(int(r["winner"]) in [0, -1], "only the parry can touch")
		r = CombatRules.resolve_lance(cfg, a, b, "strike", "feint", s, "tri", 1)
		eq(int(r["exchange"]), 0, "strike wins against feint")
		r = CombatRules.resolve_lance(cfg, a, b, "parry", "feint", s, "tri", 2)
		eq(int(r["exchange"]), 1, "feint wins against parry")
		r = CombatRules.resolve_lance(cfg, a, b, "feint", "feint", s, "tri", 3)
		eq(int(r["winner"]), -1, "feint against feint with no edge: nothing")
		r = CombatRules.resolve_lance(cfg, a, b, "strike", "strike", s, "tri", 4)
		check(int(r["winner"]) in [0, 1] and str(r["how"]) == "clash", "strike against strike: a clash, someone touches")


func test_touch_threshold_uses_martial_weapon_and_armor() -> void:
	var t: Dictionary = cfg["touch"]
	var base := int(t["base"]) + int(t["advantage"])
	eq(CombatRules.touch_threshold(cfg, _f("a"), _f("b"), "strike"), base, "equal martial: base + advantage")
	eq(CombatRules.touch_threshold(cfg, _f("a", 7), _f("b", 3), "parry"), base + 4 * int(t["step"]), "martial counts")
	eq(CombatRules.touch_threshold(cfg, _f("a", 3, 3, 5, "sword"), _f("b"), "strike"),
		base + int(cfg["weapons"]["sword"]["touch"]), "the sword's edge helps its strike")
	eq(CombatRules.touch_threshold(cfg, _f("a", 3, 3, 5, "sword"), _f("b"), "feint"), base, "not its feint")
	eq(CombatRules.touch_threshold(cfg, _f("a"), _f("b", 3, 3, 5, "fists", true), "strike"),
		base + int(cfg["armor"]["against"]), "armour makes the touch harder")


func test_reading_chance_by_attributes() -> void:
	var r: Dictionary = cfg["read"]
	near(CombatRules.read_chance(cfg, _f("r", 3, 3), _f("l", 3, 3)), float(r["base"]), 0.0001, "equal: the base")
	check(CombatRules.read_chance(cfg, _f("r", 3, 7), _f("l", 3)) > CombatRules.read_chance(cfg, _f("r"), _f("l")),
		"more empathy reads better")
	check(CombatRules.read_chance(cfg, _f("r"), _f("l", 7)) < CombatRules.read_chance(cfg, _f("r"), _f("l")),
		"more martial hides better")
	near(CombatRules.read_chance(cfg, _f("r", 3, 10), _f("l", 1)), float(r["max"]), 0.0001, "never sure")
	near(CombatRules.read_chance(cfg, _f("r", 3, 1), _f("l", 10)), float(r["min"]), 0.0001, "never blind")


func test_cue_tells_the_truth_as_often_as_the_chance_says() -> void:
	for p: float in [0.34, 0.5, 0.7, 0.9]:
		var hits := 0
		var lies_ok := true
		for s in N:
			var act: String = CombatRules.ACTIONS[s % 3]
			var c := CombatRules.cue(p, act, s, "cue", s % 9)
			if c == act:
				hits += 1
			lies_ok = lies_ok and c in CombatRules.ACTIONS
		near(float(hits) / N, p, 0.035, "the cue is true %.0f %% of the time" % (p * 100))
		check(lies_ok, "a lie is one of the actions")


func test_reading_wins_more_with_more_empathy() -> void:
	var low := _rate(_f("a", 3, 1), _f("b"))
	var high := _rate(_f("a", 3, 8), _f("b"))
	print("[TestDuel] empatía 1: %.3f · empatía 8: %.3f" % [low["win"], high["win"]])
	check(float(high["win"]) > float(low["win"]) + 0.08, "reading the gesture matters")


func test_martial_wins_more() -> void:
	var even := _rate(_f("a"), _f("b"))
	var strong := _rate(_f("a", 7), _f("b"))
	print("[TestDuel] 3 vs 3: %s · 7 vs 3: %s" % [even, strong])
	check(absf(float(even["win"]) - float(even["lose"])) < 0.08, "equal fighters: close to even")
	check(float(strong["win"]) > 0.6, "martial 7 against 3 wins most duels")


func test_breath_costs_and_limits() -> void:
	var f := _f("a", 3, 3, 5)
	var mx := CombatRules.breath_max(cfg, f)
	var fists := int(cfg["weapons"]["fists"]["breath"])
	eq(mx, int(cfg["breath"]["base"]) + floori(5 * float(cfg["breath"]["per_constitution"])) + fists, "fists: extra breath")
	eq(CombatRules.breath_max(cfg, _f("a", 3, 3, 5, "sword")), mx - fists, "a sword: no extra breath")
	eq(CombatRules.allowed(cfg, 0), ["parry"] as Array[String], "without breath, only parry")
	check(not CombatRules.can_afford(cfg, 1, "strike"), "strike needs 2")
	check(CombatRules.can_afford(cfg, 1, "feint"), "feint needs 1")
	eq(CombatRules.breath_after(cfg, f, 3, "strike"), 1, "strike spends 2")
	eq(CombatRules.breath_after(cfg, f, mx, "parry"), mx, "parry recovers, never above the max")
	eq(CombatRules.breath_after(cfg, f, 0, "parry"), 1, "parry recovers 1")
	var du := Duel.create(cfg, "br", 7, _f("a", 3, 3, 0, "sword"), _f("b"), "first_blood", 0)
	du.d["breath"][0] = 1
	eq(str(du.choose(0, "strike")["reason"]), "no_breath", "the duel refuses a strike without breath")


func test_ends_at_touches_or_lances() -> void:
	var k: Dictionary = cfg["kinds"]["first_blood"]
	for s in 300:
		var r := Duel.auto(cfg, "end%d" % s, s, _f("a"), _f("b"), "first_blood")
		check(int(r["lances"]) <= int(k["lances"]), "never more lances than the kind")
		if str(r["end"]) == "touches":
			eq(maxi(int(r["touches"][0]), int(r["touches"][1])), int(k["touches"]), "ends at the touches")
		elif str(r["end"]) == "lances":
			eq(int(r["lances"]), int(k["lances"]), "or at the last lance")
			if int(r["winner"]) < 0:
				eq(int(r["touches"][0]), int(r["touches"][1]), "a draw is equal touches")
		else:
			eq(str(r["end"]), "yield", "or someone yields")
	eq(str(Duel.create(cfg, "x", 1, _f("a"), _f("b"), "to_death", 0).result()["end"]), "locked", "to the death: locked")


func test_yield() -> void:
	var du := Duel.create(cfg, "y", 3, _f("a"), _f("b"), "surrender", 0)
	check(bool(du.view(0)["can_yield"]), "a duel to surrender lets you yield")
	du.choose(0, "yield")
	var r := du.result()
	eq(int(r["winner"]), 1, "who yields loses")
	eq(int(r["yielded"]), 0, "and it says so")
	check(not bool(r["wound"]), "yielding spares the wound")


func test_same_seed_same_duel() -> void:
	var a := _f("a", 4, 5, 6, "sword")
	var b := _f("b", 5, 3, 4, "fists", true)
	var x := Duel.create(cfg, "det", 42, a, b, "first_blood", -1)
	var y := Duel.create(cfg, "det", 42, a, b, "first_blood", -1)
	eq(JSON.stringify(x.lances_log()), JSON.stringify(y.lances_log()), "same seed, same lances")
	var played := _play(42, a, b, _follower)
	var p2 := _play(42, a, b, _follower)
	eq(JSON.stringify(played), JSON.stringify(p2), "same seed and same choices, same played duel")
	var diff := 0
	for s in 20:
		var z := Duel.create(cfg, "det", 100 + s, a, b, "first_blood", -1)
		diff += int(JSON.stringify(z.lances_log()) != JSON.stringify(x.lances_log()))
	check(diff >= 18, "another seed, another duel")


func test_auto_equals_follower_policy() -> void:
	# a side the AI plays is the same duel as a player choosing what the AI policy would choose
	var a := _f("a", 4, 5, 6, "sword")
	var b := _f("b", 5, 3, 4, "fists", true)
	for s in 50:
		var auto := Duel.create(cfg, "t%d" % (1000 + s), 1000 + s, a, b, "first_blood", -1)
		var played := _play(1000 + s, a, b, _follower)
		eq(JSON.stringify(played), JSON.stringify(auto.result()), "seed %d: same result" % s)


func test_auto_and_played_give_similar_chances() -> void:
	var pairs := [[_f("a"), _f("b")], [_f("a", 5, 4), _f("b", 3, 3)], [_f("a", 3, 6, 5, "sword"), _f("b", 6, 3)]]
	for pr: Array in pairs:
		var auto := _rate(pr[0], pr[1])
		var fol := _rate(pr[0], pr[1], _follower)
		var rnd := _rate(pr[0], pr[1], _random)
		print("[TestDuel] %s vs %s · auto %s · sigue la pista %s · al azar %s" % [pr[0], pr[1], auto, fol, rnd])
		near(float(fol["win"]), float(auto["win"]), 0.03, "following the gesture = the automatic way")
		check(float(rnd["win"]) < float(auto["win"]), "choosing at random is worse than reading")
		check(float(auto["win"]) - float(rnd["win"]) < 0.2, "but not hopeless: the gap stays under 20 points")


func test_fixed_policies_do_not_beat_the_ai() -> void:
	for act: String in CombatRules.ACTIONS:
		var fixed := func(v: Dictionary, _du: Duel) -> String: return act if act in (v["allowed"] as Array) else "parry"
		var r := _rate(_f("a"), _f("b"), fixed)
		print("[TestDuel] siempre %s: %s" % [act, r])
		check(float(r["win"]) < 0.42, "always %s loses more than it wins against the AI" % act)


func test_weapon_from_equipment() -> void:
	eq(CombatRules.weapon_for(cfg, {"tool": {"item": "sword", "quality": 0}}), "sword", "an equipped sword")
	eq(CombatRules.weapon_for(cfg, {"tool": {"item": "hammer", "quality": 0}}), "tool", "a hammer is a tool")
	eq(CombatRules.weapon_for(cfg, {"tool": null}), "fists", "nothing: fists")
	check(CombatRules.armored(cfg, {"clothes": {"item": "armor", "quality": 0}}), "armour")
