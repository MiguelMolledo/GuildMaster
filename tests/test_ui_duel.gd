extends "res://tests/test_case.gd"
## The duel in the UI (docs/ui/mecanicas/combate.md): the «Retar a duelo…» button of the townsperson's sheet and the
## duel screen in the game (open_game: it reads the duel of the state and gives duel_move / duel_auto, applied at once).

const HUGO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var cat := Catalog.load_from()


func _init() -> void:
	Duel.verbose = false


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("duel_ready")["state"], cat)


func test_the_sheet_has_the_duel_button() -> void:
	var sim := _sim()
	var panel: NpcPanel = (load("res://game/ui/npc_panel.tscn") as PackedScene).instantiate()
	panel.setup(sim, HUGO, RIVAL)
	panel.open()
	var b := panel.get_node("%Actions").get_node("DuelButton") as Button
	check(b != null, "«Retar a duelo…» on the rival's sheet")
	check(not b.disabled, "he insulted Hugo and is his trade's rival: it can")
	var folk := Population.townsfolk(sim.state)
	panel.setup(sim, HUGO, str(folk[0]))
	var c := panel.get_node("%Actions").get_node("DuelButton") as Button
	check(c.disabled, "a townsperson with no quarrel: off")
	eq(c.tooltip_text, SimQuery.reason_text("no_cause"), "with its reason")
	panel.free()


func test_the_screen_plays_a_duel_of_the_game() -> void:
	var sim := _sim()
	sim.step([{"type": "duel_challenge", "actor": HUGO, "target": RIVAL, "cause": "offense", "kind": "first_blood"}])
	var id := ""
	for i in 3 * 1440:
		sim.step()
		var o: Dictionary = Duels.open_duels(sim.state)
		if not o.is_empty() and str(o[o.keys()[0]]["status"]) == "fighting":
			id = str(o.keys()[0])
			break
		if o.is_empty():
			break
	check(id != "", "the rival accepted and both came at dawn")
	if id == "":
		return
	var screen: DuelScreen = (load("res://game/ui/duel_screen.tscn") as PackedScene).instantiate()

	screen.open_game(sim, id, func(o: Dictionary) -> Array: return sim.step([o]))
	check(screen.visible and screen.game_mode, "open in the game mode")
	eq(screen.player, 0, "Hugo's side")
	var before := Duel.wrap(cat.combat, Duels.duel_of(sim.state, id)["duel"]).lances_log().size()
	screen._choose("parry")
	var after := Duel.wrap(cat.combat, Duels.duel_of(sim.state, id)["duel"]).lances_log().size()
	eq(after, before + 1, "a click is one lance in the state")
	screen.busy = false  # the test does not wait for the animation
	screen._auto_finish()
	check(Duels.open_duels(sim.state).is_empty(), "«Resolver sin jugar» closes it in the sim")
	screen.free()
