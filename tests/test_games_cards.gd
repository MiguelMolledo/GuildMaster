extends "res://tests/test_case.gd"
## Games 2 (docs/gdd/04f_vida_y_fiestas.md §4.26.8; docs/contratos/juegos.md): the envite. The deck and its order, the
## bazas and who wins, the raises within the cap, the gesture and its reliability, the odds the screen shows (exact
## counts), determinism and the order game_play.

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


func test_deck_and_order() -> void:
	var m := EnviteMatch.create(g, "deck", 1, [_p(), _p()], -1, 5)
	eq(m.deck().size(), 40, "a deck of 40")
	var counts := m.level_counts()
	var total := 0
	for c: Variant in counts:
		total += int(c)
	eq(total, 40, "every card has a level")
	check(m.level("espadas_1") > m.level("bastos_1"), "the ace of swords is the top")
	check(m.level("oros_7") > m.level("copas_3"), "the seven of coins is a brava")
	check(m.level("copas_7") < m.level("copas_10"), "the other sevens are below the jack")
	eq(m.level("oros_4"), 0, "the four is the lowest")
	eq(m.level("copas_1"), m.level("oros_1"), "the false aces are equal")
	var all: Array = m.hand(0) + m.hand(1)
	var uniq := {}
	for c: Variant in all:
		uniq[str(c)] = true
	eq(uniq.size(), 6, "six different cards dealt")


func test_hand_winner() -> void:
	eq(EnviteMatch.hand_winner([9, 5, 2], [8, 4, 1], 1), 0, "three bazas")
	eq(EnviteMatch.hand_winner([9, 3, 2], [8, 4, 3], 0), 1, "two of three")
	eq(EnviteMatch.hand_winner([9, 4, 2], [9, 4, 2], 1), 1, "all parda: the mano")
	eq(EnviteMatch.hand_winner([9, 4, 2], [9, 5, 1], 1), 1, "parda, then one each: the first that was not parda")


func test_hands_of_counts_every_combination() -> void:
	var m := EnviteMatch.create(g, "cnt", 1, [_p(), _p()], -1, 5)
	var counts := m.level_counts()
	var w := 0.0
	for e: Array in EnviteMatch.hands_of(counts, 3, counts.size() - 1):
		w += float(e[1])
	near(w, 9880.0, 0.01, "C(40, 3) hands")
	var w2 := 0.0
	for e: Array in EnviteMatch.hands_of(counts, 2, counts.size() - 1):
		w2 += float(e[1])
	near(w2, 780.0, 0.01, "C(40, 2)")


func test_odds_are_a_chance_and_gesture_moves_them() -> void:
	var moved := 0
	for i: int in 60:
		var m := EnviteMatch.create(g, "o%d" % i, 3, [_p(), _p()], 0, 5)
		if m.over():
			continue
		var v := m.view(0)
		check(float(v["win"]) >= 0.0 and float(v["win"]) <= 1.0, "a chance")
		check(str(v["gesture"]) in ["pleased", "uneasy"], "the rival shows a gesture")
		near(float(v["read"]), 0.7, 0.001, "equal empathy and rhetoric: 7 in 10")
		if absf(float(v["win_gesture"]) - float(v["win"])) > 0.02:
			moved += 1
		eq((v["hands"] as Array)[1], [], "the rival's cards are hidden")
	check(moved > 30, "the gesture changes the odds most of the times (%d)" % moved)


func test_raises_and_cap() -> void:
	var m := EnviteMatch.create(g, "cap", 5, [_p(), _p("regular_boastful")], 0, 25, {"mano": 0})
	eq(str(m.view(0)["phase"]), "bet", "the mano speaks first")
	eq(m.allowed(0), ["raise", "pass"], "raise or pass")
	m.choose(0, "raise")
	if not m.over() and int(m.d["turn"]) == 0:
		check(not "reraise" in m.allowed(0) or int(m.d["level"]) + 50 <= 50, "no raise over the cap")
	for i: int in 30:
		var m2 := EnviteMatch.create(g, "c%d" % i, 5, [_p("regular_boastful"), _p("regular_boastful")], -1, 10)
		check(int(m2.d["level"]) <= 50, "nobody plays more than 50 (O-V8)")
		eq(int(m2.result()["net"][0]) + int(m2.result()["net"][1]), 0, "zero-sum")


func test_fold_loses_what_was_put() -> void:
	var done := false
	for i: int in 80:
		var m := EnviteMatch.create(g, "f%d" % i, 7, [_p(), _p("regular_boastful")], 0, 5, {"mano": 1})
		if m.over() or str(m.d["phase"]) != "answer":
			continue
		var lv := int(m.d["level"])
		m.choose(0, "fold")
		eq(str(m.result()["how"]), "fold", "folding ends the hand")
		eq(int(m.result()["net"][0]), -lv, "and loses what was put")
		done = true
		break
	check(done, "some hand where the boastful raises first")


func test_same_seed_same_hand() -> void:
	var a := EnviteMatch.create(g, "same", 9, [_p(), _p()], -1, 5)
	var b := EnviteMatch.create(g, "same", 9, [_p(), _p()], -1, 5)
	eq(a.d["hands"], b.d["hands"], "same deal")
	eq(a.d["log"], b.d["log"], "same hand")


func test_auto_equals_ai_move_and_fixed_lose() -> void:
	var ev := {"auto": 0.0, "follow": 0.0, "always_want": 0.0, "always_raise": 0.0}
	var n := 300
	for i: int in n:
		var ps := [_p(), _p()]
		ev["auto"] += float(EnviteMatch.create(g, "b%d" % i, 11, ps, -1, 5).result()["net"][0])
		for pol: String in ["follow", "always_want", "always_raise"]:
			var m := EnviteMatch.create(g, "b%d" % i, 11, ps, 0, 5)
			var guard := 0
			while not m.over() and guard < 20:
				guard += 1
				var ok := m.allowed(0)
				var act := m.ai_move(0)
				if pol == "always_want":
					act = "pass" if "pass" in ok else "want"
				elif pol == "always_raise":
					act = "raise" if "raise" in ok else ("reraise" if "reraise" in ok else ("want" if "want" in ok else "pass"))
				m.choose(0, act)
			ev[pol] += float(m.result()["net"][0])
	eq(ev["follow"], ev["auto"], "playing the AI's move is exactly «Resolver sin jugar»")
	check(ev["always_want"] < ev["auto"], "never raising and always wanting loses (%s < %s)" % [ev["always_want"], ev["auto"]])
	check(ev["always_raise"] < ev["auto"], "always raising loses (%s < %s)" % [ev["always_raise"], ev["auto"]])


func test_order_envite() -> void:
	var r := NewGame.from_scenario("town_e_start", 1)
	var sim := Sim.new(r["state"], cat)
	var ev := sim.step([{"type": "game_play", "actor": HUGO, "game": "envite", "opponents": ["preset:regular_prudent"],
		"stake": 5}])
	var played := {}
	for e: Dictionary in ev:
		check(str(e["type"]) != "order_refused", "the envite is played: %s" % e.get("reason", ""))
		if str(e["type"]) == "game_played":
			played = e
	eq(str(played.get("game", "")), "envite", "game_played")
