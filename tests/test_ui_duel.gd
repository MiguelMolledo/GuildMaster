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


func test_the_duel_art_is_found_with_its_names() -> void:
	# arte-fal-2 keeps its names (icon_<name>, victory / defeat, _192); VisualPaths maps the duel's ids to them
	for id: String in ["strike", "parry", "feint", "yield", "auto", "breath", "touch", "challenge"]:
		check(VisualPaths.duel_icon(id) != null, "icon %s (32)" % id)
		check(VisualPaths.duel_icon(id, true) != null, "icon %s (16)" % id)
	for id: String in ["won", "lost", "draw", "challenge"]:
		var big := VisualPaths.duel_illustration(id)
		var small := VisualPaths.duel_illustration(id, true)
		check(big != null and big.get_size() == Vector2(240, 135), "card illustration %s 240×135" % id)
		check(small != null and small.get_size() == Vector2(192, 108), "notice illustration %s 192×108" % id)
	for kind: String in ["strike", "parry", "feint", "hit"]:
		var v := VisualPaths.duel_vfx(kind)
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://assets/art/vfx/duel_%s/duel_%s.json" % [kind, kind]))
		eq((v["frames"] as Array).size(), int(meta["frames"]) - int(meta.get("start_frame", 0)), "%s: its frames" % kind)
		eq(v["size"], Vector2(int(meta["frame_w"]), int(meta["frame_h"])), "%s: the frame size of its .json" % kind)
		eq(v["offset"], Vector2(int(meta["offset"]["x"]), int(meta["offset"]["y"])), "%s: the offset from the feet" % kind)
