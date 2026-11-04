extends "res://tests/test_case.gd"
## The way through the menus (docs/ui/02_menu_inicial.md): the game starts on the title (flags of app.gd kept),
## title → new game → game, the pause menu stops the sim and drops orders, the credits, the ending's score.

const GameScript := preload("res://game/autoload/game.gd")
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _dir() -> String:
	var d := "user://test_menu_flow_%d" % randi()
	DirAccess.make_dir_recursive_absolute(d)
	SaveSlots.dir = d
	return d


func _cleanup(d: String) -> void:
	for f: String in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	DirAccess.remove_absolute(d)
	SaveSlots.dir = "user://saves"


func _game(state: WorldState = null) -> Node:
	var g: Node = GameScript.new()
	g.start(state if state != null else NewGame.from_scenario("town_e_start")["state"], cat)
	return g


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func test_the_game_opens_on_the_title_and_the_flags_still_work() -> void:
	var a: Dictionary = GameScript.parse_args(PackedStringArray([]))
	check(bool(a["title"]), "no options: the title")
	a = GameScript.parse_args(PackedStringArray(["--new-game"]))
	check(not bool(a["title"]) and bool(a["new_game"]), "--new-game: the new game screen")
	for args: Array in [["--scenario=town_e_start"], ["--smoke", "--shots=2"], ["--smoke-script=forja"]]:
		a = GameScript.parse_args(PackedStringArray(args))
		check(not bool(a["title"]) and not bool(a["new_game"]), "%s: straight in" % [args])
	a = GameScript.parse_args(PackedStringArray(["--smoke", "--new-game"]))
	check(bool(a["new_game"]) and not bool(a["title"]), "--new-game wins over --smoke")


func test_title_without_saves_offers_new_game_first() -> void:
	var d := _dir()
	var t: TitleScreen = _scene("res://game/ui/title_screen.tscn")
	t.time_config = cat.time
	t.open()
	check(not (t.get_node("%ContinueButton") as Button).visible, "no Continue")
	check((t.get_node("%LoadButton") as Button).disabled, "Load off")
	check((t.get_node("%LoadReason") as Label).visible, "with its reason")
	eq(t.default_focus(), t.get_node("%NewGameButton"), "New game has the focus")
	var asked: Array = []
	t.new_game_pressed.connect(func() -> void: asked.append("new"))
	(t.get_node("%NewGameButton") as Button).pressed.emit()
	eq(asked, ["new"], "asks the app")
	t.free()
	_cleanup(d)


func test_title_continues_the_last_game() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var d := _dir()
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed", "name": "Hugo", "family_name": "Herrero"}, 3)["state"]
	SaveFile.save(st, SaveSlots.path_of("slot_1"))
	var t: TitleScreen = _scene("res://game/ui/title_screen.tscn")
	t.time_config = cat.time
	t.open()
	check((t.get_node("%ContinueButton") as Button).visible, "Continue")
	eq((t.get_node("%ContinueInfo") as Label).text, "Los Herrero · día 1, primavera, año 1", "its family and game date")
	eq(t.default_focus(), t.get_node("%ContinueButton"), "Continue has the focus")
	check(not (t.get_node("%LoadButton") as Button).disabled, "Load on")
	var slots: Array = []
	t.continue_pressed.connect(func(s: String) -> void: slots.append(s))
	(t.get_node("%ContinueButton") as Button).pressed.emit()
	eq(slots, ["slot_1"], "Continue loads the most recent")
	t.free()
	_cleanup(d)
	TranslationServer.set_locale(before)


func test_title_to_new_game_to_playing_with_the_keyboard() -> void:
	var g := _game()
	var ng: NewGameScreen = _scene("res://game/ui/new_game_screen.tscn")
	ng.setup(cat, 11)
	ng.open()
	eq(ng.default_focus(), ng.get_node("%NameEdit"), "the name field has the focus")
	var started: Array = []
	ng.started.connect(func(st: WorldState) -> void: started.append(st))
	(ng.get_node("%NameEdit") as LineEdit).text_submitted.emit("Hugo")  # Enter in the field
	eq(started.size(), 1, "Enter starts the game")
	g.start(started[0], cat)
	var minute := int(g.sim.state.clock["minute"])
	var steps := 0
	for i: int in 20:
		steps += g.advance(0.5, false)
	check(steps > 0 and int(g.sim.state.clock["minute"]) > minute, "the game runs")
	(ng.get_node("%NameEdit") as LineEdit).text = ""
	(ng.get_node("%NameEdit") as LineEdit).text_changed.emit("")
	check((ng.get_node("%StartButton") as Button).disabled, "no name: Start off")
	check((ng.get_node("%ErrorLabel") as Label).visible, "with its reason next to it")
	ng.free()
	g.free()


func test_pause_menu_stops_the_sim_and_drops_orders() -> void:
	var g := _game()
	var p: PauseMenu = _scene("res://game/ui/pause_menu.tscn")
	p.game = g
	p.open()
	check(p.is_open() and g.paused and g.orders_locked, "paused and locked")
	var minute := int(g.sim.state.clock["minute"])
	eq(g.advance(5.0, false), 0, "the sim does not run")
	g.give({"type": "move_to", "actor": HUGO, "tile": [24, 18]})
	eq(g.pending().size(), 0, "an order is not queued")
	eq(int(g.sim.state.clock["minute"]), minute, "the clock waits")
	p.close()
	check(not g.paused and not g.orders_locked, "back as it was (running)")
	check(g.advance(1.0, false) > 0, "the sim runs again")
	g.set_paused(true)
	p.open()
	p.close()
	check(g.paused, "a game paused before stays paused")
	g.free()
	p.free()


func test_pause_menu_asks_before_quitting_unsaved_and_keys() -> void:
	var g := _game()
	g.advance(2.0, false)
	var p: PauseMenu = _scene("res://game/ui/pause_menu.tscn")
	p.game = g
	p.open()
	check((p.get_node("%CloseDynastyButton") as Button).disabled, "D19 off in data: End the dynasty off")
	check((p.get_node("%CloseReason") as Label).visible, "with its reason")
	var quits: Array = []
	p.quit_requested.connect(func(where: String, save_first: bool) -> void: quits.append([where, save_first]))
	(p.get_node("%TitleButton") as Button).pressed.emit()
	var confirm := p.get_node("%Confirm") as ConfirmDialog
	check(confirm.visible, "unsaved: asks first")
	for id: String in ["cancel", "discard", "save"]:
		check(confirm.button(id) != null, "button %s" % id)
	confirm.button("save").pressed.emit()
	eq(quits, [["title", true]], "Save and quit")
	var keys: Array = []
	p.save_requested.connect(func() -> void: keys.append("save"))
	p.load_requested.connect(func() -> void: keys.append("load"))
	for k: Key in [KEY_F5, KEY_F9]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.pressed = true
		p._key(ev)
	eq(keys, ["save", "load"], "F5 and F9")
	var d := _dir()
	g.save_slot("slot_1")
	(p.get_node("%QuitButton") as Button).pressed.emit()
	eq(quits.back(), ["quit", false], "saved: quits without asking")
	p.close()
	g.free()
	p.free()
	_cleanup(d)


func test_credits_name_the_fonts_and_their_licences() -> void:
	var c: CreditsScreen = _scene("res://game/ui/credits_screen.tscn")
	c.open()
	var texts: PackedStringArray = []
	for n: Node in (c.get_node("%Sections") as Node).get_children():
		if n is Label:
			texts.append((n as Label).text)
	var all := "\n".join(texts)
	for want: String in ["Pixel Operator", "(CC0)", "Jacquard 24", "(OFL)", "Silkscreen", "Miguel Molledo"]:
		check(all.contains(want), "credits mention %s" % want)
	c.free()


func test_ending_title_by_kind_and_rows_add_up_to_the_total() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := Sim.new(NewGame.from_scenario("founder_no_heir")["state"], cat)
	sim.run_minutes(15)
	eq(str(sim.state.ending.get("kind", "")), "game_over", "game over")
	var e: EndingScreen = _scene("res://game/ui/ending_screen.tscn")
	e.show_ending(sim.state, sim)
	eq((e.get_node("%Title") as Label).text, "Fin de la dinastía", "the title of game_over")
	var sum := 0
	for row: Node in (e.get_node("%ScoreRows") as Node).get_children():
		sum += int((row.get_node("Points") as Label).text)
	var total := int(Dynasty.score(sim, str(sim.state.ending["family"]))["total"])
	eq(sum, total, "the rows add up to the total")
	check((e.get_node("%TotalValue") as Label).text.contains(str(total)), "the total shown")
	check(not e.esc_goes_back, "Esc does nothing: you have to choose")
	e.view_town(true)
	check(e.is_viewing_town() and not (e.get_node("%Center") as Control).visible, "See the town hides the parchment")
	e.view_town(false)
	check((e.get_node("%Center") as Control).visible, "and Back to the end shows it")
	sim.state.ending["kind"] = "ruin"
	e.show_ending(sim.state, sim)
	eq((e.get_node("%Title") as Label).text, "Ruina", "the title of the ruin")
	e.free()
	TranslationServer.set_locale(before)
