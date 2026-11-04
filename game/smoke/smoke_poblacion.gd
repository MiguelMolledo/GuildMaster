extends Node
## Scripted capture of the generated cast (--smoke-script=poblacion; through `grimoire heavy` with --always-on-top,
## best with --seed=<n>): the new game screen with its first proposal, then «Otra familia» twice (another name, family
## name and look), then the game started from it: the sheet of a townsman, of a townswoman and of the rival smith,
## each with its base portrait in its identity colours. Shots reports/shots/poblacion_<what>.png. Prints
## "[SmokePoblacion] ok|FAIL ..."; quits with 1 on a FAIL or a timeout.

var app: Node = null
var timeout: float = 90.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1
var _fails: int = 0
var _steps: Array = []  # [shot name, prepare: Callable]
var _names: Array = []  # the proposals seen (they must differ)


func _ready() -> void:
	_steps = [
		["partida_nueva", func() -> void: _screen()],
		["otra_familia_1", func() -> void: _reroll()],
		["otra_familia_2", func() -> void: _reroll()],
		["vecino", func() -> void: _start_and_open(false)],
		["vecina", func() -> void: _open_townsperson(true)],
		["rival", func() -> void: _open_rival()],
	]
	print("[SmokePoblacion] start (%d shots)" % _steps.size())


func _screen() -> void:
	app.show_new_game()
	var s: NewGameScreen = app.new_game_screen()
	_names.append((s.get_node("%NameEdit") as LineEdit).text + " " + (s.get_node("%FamilyEdit") as LineEdit).text)
	_check((s.get_node("%RerollButton") as Button).visible, "the «Otra familia» button (%s)" % _names[-1])


func _reroll() -> void:
	var s: NewGameScreen = app.new_game_screen()
	(s.get_node("%RerollButton") as Button).pressed.emit()
	var now := (s.get_node("%NameEdit") as LineEdit).text + " " + (s.get_node("%FamilyEdit") as LineEdit).text
	_check(not now in _names, "another family: %s (roll %d)" % [now, s.cast_roll])
	_names.append(now)


func _start_and_open(female: bool) -> void:
	var s: NewGameScreen = app.new_game_screen()
	s.start_game()
	Game.set_paused(true)
	var st: WorldState = Game.sim.state
	_check(str(st.cast.get("mode", "")) == "random", "a generated cast (seed %s)" % st.cast.get("seed", ""))
	_check(str(st.families[SimQuery.player_family(st)]["name"]) == _names[-1].get_slice(" ", 1),
		"the family proposed: %s" % st.families[SimQuery.player_family(st)]["name"])
	_open_townsperson(female)


func _open_townsperson(female: bool) -> void:
	var st: WorldState = Game.sim.state
	var ids: Array = Population.townsfolk(st)
	for id: String in ids:
		if bool(st.characters[id].get("female", false)) == female:
			_show(id)
			return
	_check(false, "a townsperson (female=%s)" % female)


func _open_rival() -> void:
	var st: WorldState = Game.sim.state
	for f: String in st.families:
		if str(st.families[f].get("ai_profile", "")) == "rival_smith":
			_show(str(st.families[f]["head"]))
			return
	_check(false, "the rival smith")


func _show(id: String) -> void:
	var st: WorldState = Game.sim.state
	var who := Identity.of(st, id)
	var tex := Identity.portrait_texture(who, 32)
	_check(tex != null, "%s «%s» (%s %s, %s): base portrait %s" % [id, st.characters[id]["name"], who["portrait"]["type"],
		who["portrait"]["stage"], "f" if bool(who["female"]) else "m", tex.resource_path if tex != null else "none"])
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(st.characters[id]["position"][0]),
		int(st.characters[id]["position"][1]))))
	app.hud().open_npc(id)


func _check(cond: bool, what: String) -> void:
	print("[SmokePoblacion] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokePoblacion] TIMEOUT at %d" % _i)
		get_tree().quit(1)
		return
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < 1.0:
		return
	else:
		app.save_shot("poblacion_" + str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokePoblacion] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
