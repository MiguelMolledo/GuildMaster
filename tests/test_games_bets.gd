extends "res://tests/test_case.gd"
## Games 3 (docs/gdd/04f_vida_y_fiestas.md §4.26.6, §4.26.7; O-V8, O-V10 b; docs/contratos/juegos.md): the bookmaker's
## odds from the sim's chances with the house's margin and the cap, the order game_bet, bets on one's own game and
## the fraud of betting against oneself, and the loaded dice (their advantage and being caught: «trampa»).

const HUGO: String = "chr_0001"
const BERNAT: String = "chr_0006"

var cat := Catalog.load_from()
var g: Dictionary = cat.games


func _init() -> void:
	GameMatch.verbose = false


func _sim(seed: int = 1) -> Sim:
	var r := NewGame.from_scenario("town_e_start", seed)
	return Sim.new(r["state"], cat)


func _ev(events: Array, type: String) -> Dictionary:
	for e: Dictionary in events:
		if str(e["type"]) == type:
			return e
	return {}


func _refused(events: Array) -> String:
	return str(_ev(events, "order_refused").get("reason", ""))


func test_quote_has_the_margin() -> void:
	var q := Betting.quote(g, {0: 0.5, 1: 0.5})
	near(float(q[0]), 1.8, 0.001, "an even game pays 1.80 (10 % margin)")
	var q2 := Betting.quote(g, {0: 0.8, 1: 0.2})
	near(float(q2[0]), 1.1, 0.001, "the favourite: 0.9 / 0.8 rounded down to 1.10")
	near(float(q2[1]), 4.5, 0.001, "the outsider: 4.50")
	var q3 := Betting.quote(g, {0: 0.999})
	check(float(q3[0]) >= 1.05, "never below min_odds")
	# expected return of every bet: chance × odds <= 1 − margin
	for p: float in [0.1, 0.25, 0.4, 0.5, 0.65, 0.9]:
		var o := float(Betting.quote(g, {0: p})[0])
		check(p * o <= 0.9 + 0.001 or o == 1.05, "chance %.2f × odds %.2f <= 0.90" % [p, o])


func test_market_from_the_sim() -> void:
	var spec := {"game": "pulso", "match": "mk", "seed": 3, "player": -1, "stake": 0, "opts": {},
		"players": [Games.preset_player(g, "preset:regular_even"),
			Games.preset_player(g, "preset:regular_boastful")]}
	(spec["players"][1]["stats"] as Dictionary)["constitution"] = 7
	var mk := Betting.market(g, spec, 200)
	check(float(mk[1]["chance"]) > float(mk[0]["chance"]), "the stronger arm is the favourite")
	check(float(mk[1]["odds"]) < float(mk[0]["odds"]), "and pays less")
	eq(Betting.market(g, spec, 200), mk, "the same market every time (keyed)")


func test_order_game_bet() -> void:
	var sim := _sim()
	var fam := str(sim.state.characters[HUGO]["family"])
	var g0 := Money.gold(sim.state, fam)
	var o := {"type": "game_bet", "actor": HUGO, "game": "pulso", "players": [BERNAT, "preset:regular_even"],
		"match": "plaza|pulso|1", "on": 0, "stake": 10}
	var ev := sim.step([o])
	eq(_refused(ev), "", "a valid bet")
	var e := _ev(ev, "game_bet_settled")
	check(not e.is_empty(), "settled at once")
	eq(Money.gold(sim.state, fam) - g0, int(e["net"]), "the gold moves by the bet's net")
	var spec := {"game": "pulso", "match": "plaza|pulso|1", "seed": maxi(sim.state.world_seed, 1), "player": -1,
		"stake": 0, "opts": {}, "players": [Games.player_of(sim.state, BERNAT), Games.preset_player(g, "preset:regular_even")]}
	eq(int(e["winner"]), int(Games.auto(g, spec)["winner"]), "the same winner the fiestas would get with that id")
	var bad := [[{"stake": 60}, "bad_stake"], [{"stake": 7}, "bad_stake"], [{"on": 2}, "bad_bet"], [{"match": ""}, "bad_bet"],
		[{"players": [HUGO, BERNAT]}, "bad_players"], [{"game": "chess"}, "unknown_game"]]
	for c: Array in bad:
		var o2: Dictionary = o.duplicate(true)
		o2.merge(c[0], true)
		eq(_refused(sim.step([o2])), str(c[1]), "refused: %s" % c[1])


func test_bets_lose_the_margin_on_average() -> void:
	# many bets on even pulsos: the bettor loses about the margin, neither more nor less
	var net := 0
	var staked := 0
	var n := 400
	for i: int in n:
		var spec := {"game": "pulso", "match": "avg|%d" % i, "seed": 5, "player": -1, "stake": 0, "opts": {},
			"players": [Games.preset_player(g, "preset:regular_even"), Games.preset_player(g, "preset:regular_even")]}
		var mk := Betting.market(g, spec, 40)
		var on := i % 2
		var w := int(Games.auto(g, spec)["winner"])
		net += Betting.settle(10, float(mk[on]["odds"]), on, w)
		staked += 10
	var r := float(net) / staked
	check(r < -0.02 and r > -0.25, "the bettor loses about the margin (%.3f per gold)" % r)


func test_bet_on_oneself_and_fraud() -> void:
	var sim := _sim()
	var fam := str(sim.state.characters[HUGO]["family"])
	sim.state.families[fam]["gold"] = 2000
	var ev := sim.step([{"type": "game_play", "actor": HUGO, "game": "pulso", "opponents": [BERNAT],
		"bets": [{"on": 0, "stake": 10}]}])
	eq(_refused(ev), "", "betting on oneself is allowed")
	var e := _ev(ev, "game_played")
	check(int(e["bets_net"]) != 0, "the bet is settled with the game")
	# against oneself and losing having played: fraud, sometimes seen
	var frauds := 0
	for i: int in 30:
		var ev2 := sim.step([{"type": "game_play", "actor": HUGO, "game": "pulso", "opponents": [BERNAT],
			"bets": [{"on": 1, "stake": 10}], "moves": ["give", "give", "give"], "auto": true}])
		var p := _ev(ev2, "game_played")
		if not _ev(ev2, "game_cheat_caught").is_empty():
			frauds += 1
			eq(int(p["winner"]), 1, "only when he lost")
	check(frauds > 0, "losing on purpose is noticed some times")
	var seen := false
	for f: Dictionary in sim.state.justice.get("facts", []):
		seen = seen or (str(f["kind"]) == "cheat" and str(f["charge"]) == "cheat" and str(f["family"]) == fam)
	check(seen, "a public fact «trampa» against the family")


func test_loaded_dice_need_the_item_and_win_more() -> void:
	var sim := _sim()
	var o := {"type": "game_play", "actor": HUGO, "game": "azar", "opponents": ["preset:regular_even"], "stake": 5,
		"opts": {"loaded": 0}}
	eq(_refused(sim.step([o])), "no_loaded_dice", "without the item, no loaded dice")
	var o2: Dictionary = o.duplicate(true)
	o2["game"] = "pulso"
	o2["stake"] = 0
	Inventory.add(sim.state.characters[HUGO]["inventory"], cat, "loaded_dice", 0, 1)
	eq(_refused(sim.step([o2])), "bad_option", "loaded dice only in the dice games")
	# the advantage, in pure rules (azar, the cheat throws)
	var won := 0
	var won_fair := 0
	for i: int in 600:
		var ps := [Games.preset_player(g, "preset:regular_even"), Games.preset_player(g, "preset:regular_even")]
		won += int(int(AzarMatch.create(g, "ld%d" % i, 2, ps, -1, 10, {"loaded": 0}).result()["winner"]) == 0)
		won_fair += int(int(AzarMatch.create(g, "ld%d" % i, 2, ps, -1, 10, {"thrower": 0}).result()["winner"]) == 0)
	check(won > won_fair + 30, "loaded dice win more (%d vs %d of 600)" % [won, won_fair])


func test_loaded_dice_caught() -> void:
	var sim := _sim()
	var fam := str(sim.state.characters[HUGO]["family"])
	sim.state.families[fam]["gold"] = 2000
	var caught := 0
	var games := 0
	for i: int in 40:
		var inv: Dictionary = sim.state.characters[HUGO]["inventory"]
		if Inventory.count(inv, "loaded_dice") == 0:
			Inventory.add(inv, cat, "loaded_dice", 0, 1)
		var rep0 := int(sim.state.families[fam].get("reputation", 0))
		var g0 := Money.gold(sim.state, fam)
		var ev := sim.step([{"type": "game_play", "actor": HUGO, "game": "azar", "opponents": ["preset:regular_cheat"],
			"stake": 10, "opts": {"loaded": 0}}])
		eq(_refused(ev), "", "a game with loaded dice")
		games += 1
		var c := _ev(ev, "game_cheat_caught")
		if not c.is_empty():
			caught += 1
			eq(Money.gold(sim.state, fam) - g0, -10, "caught: the stake is lost")
			eq(Inventory.count(sim.state.characters[HUGO]["inventory"], "loaded_dice"), 0, "and the dice")
			check(int(sim.state.families[fam].get("reputation", 0)) < rep0, "and reputation")
			eq(str(_ev(ev, "game_played")["how"]), "caught", "the game says how it ended")
	check(caught > 0 and caught < games, "sometimes caught (%d of %d against a sharp eye)" % [caught, games])
