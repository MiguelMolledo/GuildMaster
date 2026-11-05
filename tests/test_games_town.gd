extends "res://tests/test_case.gd"
## Games and vida (docs/gdd/04f_vida_y_fiestas.md §4.24.5, §4.26.6; docs/contratos/juegos.md §5): the played rescue
## of a kidnapping (RescueMatch: unplayed it is the old chain of Incidents._fights to the last roll; played, the actor's
## bouts are his) and the bets on a brawl (priced with the incident's own duel, paid when it is fought, given back if
## it never is).

const HUGO: String = "chr_0001"

var cat := Catalog.load_from()


func _init() -> void:
	GameMatch.verbose = false
	Duel.verbose = false


func _sim(seed: int = 1) -> Sim:
	var r := NewGame.from_scenario("town_e_start", seed)
	var sim := Sim.new(r["state"], cat)
	Life.ensure(sim.state)
	return sim


func _bandits(sim: Sim, n: int, inc_id: String) -> Array:
	var rc: Dictionary = Incidents.def(sim, "kidnapping").get("rescue", {})
	Life.service_family(sim.state, Life.FAMILY_BANDITS, "family.bandits", {"primary": "#2a2a2a", "secondary": "#5a4a3a"})
	var out: Array = []
	for i: int in n:
		out.append(Life.add_person(sim, Life.FAMILY_BANDITS, "?", false, 30, rc.get("bandit_stats", {}), {}, [0, 0],
			{"bandit": {"incident": inc_id, "nest": true}}))
	return out


func test_unplayed_rescue_is_the_old_chain() -> void:
	var same := 0
	for i: int in 40:
		var s1 := _sim(1 + i)
		var s2 := _sim(1 + i)
		var side: Array = [HUGO, "chr_0002"]
		var b1 := _bandits(s1, 2 + i % 2, "k%d" % i)
		var b2 := _bandits(s2, 2 + i % 2, "k%d" % i)
		var old := Incidents._fights(s1, side, b1, "k%d|rescue" % i, Life.FAMILY_BANDITS)
		var new := Rescue.fight(s2, side, b2, "k%d|rescue" % i, Life.FAMILY_BANDITS)
		same += int(old == new and str(s1.state.emotions) == str(s2.state.emotions))
	eq(same, 40, "Rescue.fight without moves gives what Incidents._fights gave (won and frights)")


func test_preview_meets_the_real_bandits() -> void:
	var sim := _sim()
	var inc := {"id": "inc_test", "def": "kidnapping"}
	var pv := Rescue.preview(sim, inc, HUGO, 2)
	var rc: Dictionary = Incidents.def(sim, "kidnapping").get("rescue", {})
	var span: Array = rc.get("fights", [2, 3])
	var nb := Kin.randi_range(sim.state, "events_city|rescue_n|inc_test", int(span[0]), int(span[1]))
	eq((pv["players"] as Array).size() - int(pv["team_a"]), nb, "as many bandits as the incident will raise")
	var real := _bandits(sim, 1, "inc_test")
	var f_real := Duels.fighter_of(sim, str(real[0]))
	var f_prev: Dictionary = (pv["players"] as Array)[int(pv["team_a"])]["fighter"]
	for k: String in ["martial", "empathy", "constitution", "dexterity", "weapon", "armor"]:
		eq(f_prev[k], f_real[k], "the screen's bandit is the sim's (%s)" % k)


func test_played_rescue_equals_auto_when_following() -> void:
	var same := 0
	for i: int in 60:
		var sim := _sim(3)
		var pv := Rescue.preview(sim, {"id": "r%d" % i}, HUGO, 1)
		var a := RescueMatch.create(cat.games, cat.combat, str(pv["key"]), int(pv["seed"]), pv["players"], -1, {"team_a": pv["team_a"]})
		var b := RescueMatch.create(cat.games, cat.combat, str(pv["key"]), int(pv["seed"]), pv["players"], 0, {"team_a": pv["team_a"]})
		var guard := 0
		while not b.over() and guard < 80:
			guard += 1
			b.choose(0, b.ai_move(0))
		same += int(a.won() == b.won() and a.d["n"] == b.d["n"])
	eq(same, 60, "playing the AI's lances is «Resolver sin jugar»")


func test_bet_on_a_brawl() -> void:
	var sim := _sim()
	var st := sim.state
	var fam := str(st.characters[HUGO]["family"])
	st.families[fam]["gold"] = 500
	var a := "chr_0010"
	var b := "chr_0011"
	Incidents._begin_altercation(sim, {"a": a, "b": b, "tile": [20, 20], "point": "plaza", "why": "drunk"}, int(st.clock["minute"]))
	var inc: Dictionary = Incidents.active(st).back()
	eq(str(inc["phase"]), "gathering", "the brawl is coming")
	var g0 := Money.gold(st, fam)
	var ev := sim.step([{"type": "game_bet", "actor": HUGO, "incident": str(inc["id"]), "on": 0, "stake": 10}])
	for e: Dictionary in ev:
		check(str(e["type"]) != "order_refused", "a bet on a brawl: %s" % e.get("reason", ""))
	eq(Money.gold(st, fam) - g0, -10, "the stake is taken")
	eq((inc["bets"] as Array).size(), 1, "the bet rides on the incident")
	var winner_expected := int(Games.auto(cat.games, Betting.brawl_spec(sim, inc))["winner"])
	var settled := {}
	for i: int in 600:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "game_bet_settled" and str(e.get("incident", "")) == str(inc["id"]):
				settled = e
		if not settled.is_empty():
			break
	check(not settled.is_empty(), "the bet is settled when the brawl ends or cools")
	if not bool(settled.get("refunded", false)):
		eq(int(settled["winner"]), winner_expected, "the bookmaker's brawl is the incident's own")
		var odds := float((inc["bets"] as Array)[0]["odds"])
		var want := (Betting.payout(10, odds) if winner_expected == 0 else (10 if winner_expected < 0 else 0))
		eq(Money.gold(st, fam) - g0 + 10, want, "paid at its odds")
	var bad := sim.step([{"type": "game_bet", "actor": HUGO, "incident": str(inc["id"]), "on": 0, "stake": 10}])
	var reason := ""
	for e: Dictionary in bad:
		if str(e["type"]) == "order_refused":
			reason = str(e["reason"])
	check(reason in ["too_late", "unknown_incident"], "no bets once it is fought (%s)" % reason)


func test_bet_refunded_if_no_brawl() -> void:
	var sim := _sim()
	var st := sim.state
	var fam := str(st.characters[HUGO]["family"])
	Incidents._begin_altercation(sim, {"a": "chr_0010", "b": "chr_0011", "tile": [20, 20], "point": "plaza", "why": "drunk"}, int(st.clock["minute"]))
	var inc: Dictionary = Incidents.active(st).back()
	var g0 := Money.gold(st, fam)
	sim.step([{"type": "game_bet", "actor": HUGO, "incident": str(inc["id"]), "on": 1, "stake": 5}])
	Incidents._close(sim, inc, "cooled")
	eq(Money.gold(st, fam), g0, "the stake comes back when they cool down")
