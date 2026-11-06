extends "res://tests/test_case.gd"
## D19 (docs/decisiones.json, 2026-11-05): «Retirarse» in the pause menu, with a confirmation, ends the game and opens
## the final screen with the score of 4.17. The whole way: the button, the confirmation, the order, the ending screen.

const GameScript := preload("res://game/autoload/game.gd")

var cat := Catalog.load_from()


func test_retire_from_the_pause_menu_to_the_score() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var g: Node = GameScript.new()
	g.start(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)
	g.advance(2.0, false)
	var p: PauseMenu = (load("res://game/ui/pause_menu.tscn") as PackedScene).instantiate()
	p.game = g
	p.open()
	var b := p.get_node("%CloseDynastyButton") as Button
	eq(b.text.begins_with("Retirarse"), true, "the button says «Retirarse…» (%s)" % b.text)
	check(not b.disabled, "on")
	var fired := [false]
	p.close_dynasty_confirmed.connect(func() -> void: fired[0] = true)
	b.pressed.emit()
	check(not bool(fired[0]), "it asks first")
	p._on_confirm("cancel")
	check(not bool(fired[0]), "cancel does nothing")
	b.pressed.emit()
	p._on_confirm("close")
	check(bool(fired[0]), "confirmed")
	# what app.gd does on the signal: the order of the head (Orders.apply)
	var sim: Sim = g.get("sim")
	var fam := SimQuery.player_family(sim.state)
	var r := Orders.apply(sim, {"type": "close_dynasty", "actor": str(sim.state.families[fam]["head"])})
	eq(r["ok"], true, "the order goes through")
	eq(str(sim.state.ending.get("kind", "")), "closed", "the game ends")
	var e: EndingScreen = (load("res://game/ui/ending_screen.tscn") as PackedScene).instantiate()
	e.show_ending(sim.state, sim)
	eq((e.get_node("%Title") as Label).text, "La dinastía se retira", "the final screen")
	var total := int(Dynasty.score(sim, fam)["total"])
	check((e.get_node("%TotalValue") as Label).text.contains(str(total)), "with the score of 4.17 (%d)" % total)
	e.free()
	p.free()
	g.free()
	TranslationServer.set_locale(before)
