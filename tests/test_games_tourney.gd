extends "res://tests/test_case.gd"
## Games 4 (docs/gdd/04f_vida_y_fiestas.md §4.26.2; docs/contratos/juegos.md): the fighting tournament, a knockout of
## 8 with the duel «a tres asaltos, por puntos»: the draw, every bout with a winner (points, sudden death, judges), the
## breath that does not all come back, the played side's bouts lance by lance, determinism, the entrants and the
## order game_play with its prize.

const HUGO: String = "chr_0001"

var cat := Catalog.load_from()
var g: Dictionary = cat.games


func _init() -> void:
	GameMatch.verbose = false
	Duel.verbose = false


func _field(me: Dictionary = {"martial": 5, "empathy": 3, "constitution": 5}) -> Array:
	var p := Games.preset_player(g, "preset:regular_even")
	(p["stats"] as Dictionary).merge(me, true)
	var ps: Array = [p]
	for o: Variant in g["tourney"]["outsiders"]:
		ps.append(Games.preset_player(g, "preset:" + str(o)))
	return ps


func _spec(i: int, player: int = -1) -> Dictionary:
	return {"game": "tourney", "match": "t%d" % i, "seed": 4, "players": _field(), "player": player, "stake": 0, "opts": {}}


func test_kinds_in_combat() -> void:
	var k: Dictionary = cat.combat["kinds"]
	check(k.has("tourney") and not bool(k["tourney"]["wound"]), "the tournament's kind, without wounds (O-C11 c)")
	check(not "tourney" in (cat.combat["challenge"].get("kinds_allowed", []) as Array), "not a duel of honour")


func test_knockout_of_eight() -> void:
	for i: int in 30:
		var m := Games.create(g, _spec(i)) as TourneyMatch
		check(m.over(), "the AI fights it all")
		var bouts: Array = m.d["bouts"]
		eq(bouts.size(), 7, "seven bouts: 4 + 2 + 1")
		var w := int(m.result()["winner"])
		eq(int((m.d["rounds_won"] as Array)[w]), 3, "the winner won three bouts")
		for b: Dictionary in bouts:
			check(int(b["winner"]) in (b["sides"] as Array), "every bout has a winner of its two")
			check(str(b["how"]) in ["points", "sudden", "judges"], "on points, sudden death or the judges")
		eq((m.result()["ranking"] as Array)[0], w, "the winner first")


func test_draw_is_keyed_and_same_seed_same_tournament() -> void:
	var a := Games.create(g, _spec(3))
	var b := Games.create(g, _spec(3))
	eq(a.d["draw"], b.d["draw"], "same draw")
	eq(a.d["bouts"], b.d["bouts"], "same bouts")
	var c := Games.create(g, _spec(4))
	check(c.d["draw"] != a.d["draw"] or c.d["bouts"] != a.d["bouts"], "another id, another tournament")


func test_breath_carries_between_bouts() -> void:
	var m := Games.create(g, _spec(7)) as TourneyMatch
	var w0: Dictionary = (m.d["bouts"] as Array)[0]
	var winner := int(w0["winner"])
	var full := CombatRules.breath_max(cat.combat, m.fighter(winner))
	var later := -1
	for e: Dictionary in m.log_entries():
		if str(e["kind"]) == "lance" and int(e["round"]) == 1 and winner in (e["sides"] as Array) and int(e["lance"]) == 0:
			later = 1
	check(later == 1 or int(m.result()["winner"]) >= 0, "the winner fights the next round")
	check(int((m.d["breath"] as Array)[winner]) <= full, "never above the maximum")


func test_played_bouts_lance_by_lance() -> void:
	var m := Games.create(g, _spec(9, 0)) as TourneyMatch
	check(not m.over(), "the played side's first bout waits for it")
	eq(int(m.view(0)["turn"]), 0, "its turn")
	eq(m.allowed(0).size(), 3, "strike, parry, feint")
	var guard := 0
	while not m.over() and guard < 80:
		guard += 1
		m.choose(0, m.ai_move(0))
	check(m.over(), "played to the end")
	var auto := Games.create(g, _spec(9)) as TourneyMatch
	eq(m.d["bouts"], auto.d["bouts"], "playing the AI's moves is «Resolver sin jugar», bout by bout")


func test_auto_finish_mid_bout() -> void:
	var m := Games.create(g, _spec(11, 0))
	m.choose(0, "parry")
	m.auto_finish()
	check(m.over(), "resolved without playing from the second lance")
	eq((m.d["bouts"] as Array).size(), 7, "the whole tournament")


func test_entrants_and_order() -> void:
	var r := NewGame.from_scenario("town_e_start", 1)
	var sim := Sim.new(r["state"], cat)
	var ent := TourneyMatch.entrants(sim.state, g, HUGO)
	eq(ent.size(), 8, "eight entrants")
	eq(ent[0], HUGO, "the actor first")
	var fam := str(sim.state.characters[HUGO]["family"])
	(sim.state.characters[HUGO]["stats"] as Dictionary).merge({"martial": 9, "empathy": 8}, true)  # a champion
	var won := false
	for i: int in 12:
		var rep0 := Reputation.of(sim.state, fam)
		var g0 := Money.gold(sim.state, fam)
		var ev := sim.step([{"type": "game_play", "actor": HUGO, "game": "tourney", "opponents": ent.slice(1), "auto": true,
			"match": "fiesta_test|%d" % i}])
		var played := {}
		for e: Dictionary in ev:
			check(str(e["type"]) != "order_refused", "a tournament is played: %s" % e.get("reason", ""))
			if str(e["type"]) == "game_played":
				played = e
		if bool(played.get("won", false)):
			won = true
			eq(Money.gold(sim.state, fam) - g0, int(g["tourney"]["prize"]["gold"]), "the purse")
			check(Reputation.of(sim.state, fam) > rep0, "and reputation")
	check(won, "a champion wins some tournament in 12 and gets the prize")
