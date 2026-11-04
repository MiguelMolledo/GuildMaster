extends "res://tests/test_case.gd"
## Games 6 (docs/gdd/04f_vida_y_fiestas.md §4.26.3; docs/contratos/juegos.md): running at the ring. Three runs per rider
## with the ring of each run, the pace and its points, the moment and the sway, the scoreboard and the ranking,
## «Resolver sin jugar» equal to following the sway, and the order with its entry fee.

const HUGO: String = "chr_0001"

var cat := Catalog.load_from()
var g: Dictionary = cat.games


func _init() -> void:
	GameMatch.verbose = false


func _field(dex: int = 4) -> Array:
	var p := Games.preset_player(g, "preset:regular_even")
	(p["stats"] as Dictionary)["dexterity"] = dex
	var ps: Array = [p]
	for r: Variant in g["sortija"]["riders"]:
		ps.append(Games.preset_player(g, "preset:" + str(r)))
	return ps


func test_runs_and_points() -> void:
	for i: int in 100:
		var m := SortijaMatch.create(g, "s%d" % i, 1, _field(), -1)
		check(m.over(), "the sortija ends")
		eq(m.log_entries().size(), 3 * 4, "three runs of four riders")
		var sum := GameMatch._zeros(4)
		for e: Dictionary in m.log_entries():
			var pts := int(m.pace_cfg(str(e["pace"]))["points"])
			eq(int(e["got"]), pts if bool(e["hit"]) else 0, "a threaded ring is worth its pace's points")
			if str(e["moment"]) != str(e["right"]):
				check(not bool(e["hit"]), "a wrong moment never threads")
			sum[int(e["rider"])] = int(sum[int(e["rider"])]) + int(e["got"])
		eq(sum, m.d["points"], "the scoreboard adds up")
		var w := int(m.result()["winner"])
		for j: int in 4:
			check(int(m.d["points"][w]) >= int(m.d["points"][j]), "the winner has the most points")


func test_each_pace_is_best_on_a_ring() -> void:
	var m := SortijaMatch.create(g, "best", 1, _field(3), 0)
	var best := {}
	for ring: String in ["small", "medium", "large"]:
		m.d["rings"] = [ring, ring, ring]
		best[ring] = m.ai_pace_ev(0)
	eq(best, {"small": "prudent", "medium": "firm", "large": "gallop"}, "dexterity 3: each pace is the best on one ring")


func test_follow_equals_auto_and_random_loses() -> void:
	var same := 0
	var w_auto := 0
	var w_rand := 0
	for i: int in 300:
		var a := SortijaMatch.create(g, "f%d" % i, 2, _field(), -1)
		var b := SortijaMatch.create(g, "f%d" % i, 2, _field(), 0)
		var c := SortijaMatch.create(g, "f%d" % i, 2, _field(), 0)
		var guard := 0
		while not b.over() and guard < 20:
			guard += 1
			b.choose(0, b.ai_move(0))
		guard = 0
		while not c.over() and guard < 20:
			guard += 1
			c.choose(0, GameRules.pick(c.allowed(0), 3, "r%d" % i, guard, "x"))
		same += int(a.d["log"] == b.d["log"])
		w_auto += int(int(a.result()["winner"]) == 0)
		w_rand += int(int(c.result()["winner"]) == 0)
	eq(same, 300, "following the sway and the best pace is exactly «Resolver sin jugar»")
	check(w_rand < w_auto, "playing at random loses (%d < %d)" % [w_rand, w_auto])


func test_order_sortija() -> void:
	var r := NewGame.from_scenario("town_e_start", 1)
	var sim := Sim.new(r["state"], cat)
	var fam := str(sim.state.characters[HUGO]["family"])
	var g0 := Money.gold(sim.state, fam)
	var refs: Array = []
	for x: Variant in g["sortija"]["riders"]:
		refs.append("preset:" + str(x))
	var played := {}
	for e: Dictionary in sim.step([{"type": "game_play", "actor": HUGO, "game": "sortija", "opponents": refs}]):
		check(str(e["type"]) != "order_refused", "anyone may run the ring: %s" % e.get("reason", ""))
		if str(e["type"]) == "game_played":
			played = e
	var prize := int(g["sortija"]["prize"]["gold"]) if bool(played.get("won", false)) else 0
	eq(Money.gold(sim.state, fam) - g0, prize - int(g["sortija"]["entry_fee"]), "the horse's rent (and the prize if won)")
