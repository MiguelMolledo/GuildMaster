extends Node
## Scripted capture of the tutorial (--smoke-script=tutorial, docs/ui/05_tutorial.md §8; run it through
## `grimoire heavy` with --dev-time and the engine's --always-on-top): the new game screen with «Con tutorial» ticked,
## then chapters 1 (first steps) and 2 (producing) played as a player would, doing what each step asks through the
## same calls the clicks and keys make (Game.give for the orders, the card's buttons for «Siguiente»), a shot per step
## once its focus has settled (reports/shots/tut_<chapter>_<nn>_<step>.png) and one of each end card. Prints where the
## focus fell (rect and what was lit) for every shot. Quits with 1 on a timeout.

const STEP_TIMEOUT: float = 60.0

var app: Node = null
var timeout: float = 300.0
var _tut: Tutorial = null
var _total: float = 0.0
var _t: float = 0.0
var _stage: String = "start"
var _pending: String = ""      # the shot whose action is due (chapter_nn_step, or chapter_fin)
var _pending_id: String = ""   # its step id ("fin" for the end card)
var _acted: bool = false
var _shots: Array = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeTutorial] start (timeout=%.0f s)" % timeout)


func _process(delta: float) -> void:
	_total += delta
	_t += delta
	if _total > timeout or (_stage == "play" and _t > STEP_TIMEOUT):
		print("[SmokeTutorial] TIMEOUT (stage=%s, chapter=%s, step=%s, phase=%s)" % [_stage, _tut.chapter_id if _tut else "",
			_tut.step().get("id", "") if _tut else "", _tut.phase if _tut else ""])
		app.save_shot("tut_timeout")
		get_tree().quit(1)
		return
	match _stage:
		"start":
			if _t > 0.5:
				_tut = app.tutorial()
				_tut.step_shown.connect(func(ch: String, i: int, id: String) -> void:
					_pending = "%s_%02d_%s" % [ch, i + 1, id]
					_pending_id = id
					_acted = false
					_t = 0.0)
				_tut.chapter_finished.connect(func(ch: String) -> void:
					_pending = "%s_fin" % ch
					_pending_id = "fin"
					_acted = false
					_t = 0.0)
				app.show_new_game()
				_go("new_game")
		"new_game":
			if _t > 0.8:
				var ng: NewGameScreen = app.new_game_screen()
				(ng.get_node("%TutorialCheck") as CheckBox).button_pressed = true
				app.save_shot("tut_00_partida_nueva")
				ng.start_game()
				_go("play")
		"play":
			_play()
		"extras":
			_extras()


func _go(s: String) -> void:
	print("[SmokeTutorial] %s -> %s (t=%.1f)" % [_stage, s, _total])
	_stage = s
	_t = 0.0


func _play() -> void:
	if _pending == "" or _acted:
		return
	# the panel's slide, the fade into a building and the camera have settled; the master touch cannot wait
	if _t < (0.25 if _pending_id == "touch" else 0.9):
		return
	_acted = true
	var name := _pending
	_shots.append(name)
	var f: Dictionary = _tut.focus
	print("[SmokeTutorial] shot %s (found=%s, opener=%s, rect=%s, target=%s)" % [name, f.get("found", false),
		f.get("opener", false), f.get("rect", Rect2()), f.get("target", {})])
	app.save_shot("tut_" + name)
	_act(_pending_id)


## What the player does at each step (the step's action, or «Siguiente»).
func _act(id: String) -> void:
	var sim: Sim = Game.sim
	var head := Kin.head(sim.state, SimQuery.player_family(sim.state))
	var interior: InteriorView = app.interior()
	var card := _tut.overlay.card
	match id:
		"camera":
			app.world().camera().pan(Vector2(64, 24))
		"zoom":
			app.world().camera().zoom_step(1, Vector2(420, 270))
		"resume":
			Game.set_paused(false)
		"speed":
			Game.set_speed(2)
		"walk":
			var p: Array = sim.state.characters[head]["position"]
			app.world().command_move(Vector2i(int(p[0]) + 1, int(p[1])))
		"workshop":
			app.world().select(head)
			app.world().command_enter(str(_tut.ctx.symbol("$workshop")))
		"furnace_menu":
			interior.open_station_menu("furnace", interior.station_screen("furnace"))
		"ingot":
			interior.station_menu().choose_mode("normal")
			interior.station_menu().choose_recipe("forge_ingot")
			Game.set_speed(1)   # slow enough for the shot of the next step
		"anvil_menu":
			interior.open_station_menu("anvil", interior.station_screen("anvil"))
		"careful":
			interior.station_menu().choose_mode("careful")
		"sword":
			interior.station_menu().choose_recipe("forge_sword")
		"touch":
			interior.click_station("anvil")
		"storage":
			interior.show_storage(true)
		"wait_ingots":
			Game.set_speed(4)   # the furnace works: the step passes by itself
		"fin":
			if _tut.chapter_id == "produce" or not card.press("next_chapter"):
				_finish()
		_:
			if not card.press("next"):
				print("[SmokeTutorial] %s: no «Siguiente» and no action known" % id)


func _finish() -> void:
	print("[SmokeTutorial] chapters done: %d shots (%s)" % [_shots.size(), ", ".join(_shots)])
	_tut.stop()
	app.interior().show_storage(false)
	_tut.memory["game/tutorial_hints"] = true
	_go("extras")


var _extra: int = 0


## After the chapters: the first-time hints (the station's, then the storage's), the help's chapters, the options.
func _extras() -> void:
	if _t < 0.9:
		return
	_t = 0.0
	_extra += 1
	var hud: CanvasLayer = app.hud()
	match _extra:
		1:
			_hint_shot("tut_pista_puesto")
			_tut.overlay.card.press("got_it")
			app.interior().show_storage(true)
		2:
			_hint_shot("tut_pista_almacen")
			_tut.overlay.card.press("got_it")
			app.interior().show_storage(false)
		3:
			hud.toggle_help()
		4:
			app.save_shot("tut_ayuda_capitulos")
			hud.toggle_help()
			app.options_screen().open()
		5:
			app.save_shot("tut_opciones")
			app.options_screen().close()
		_:
			print("[SmokeTutorial] done: %d shots" % (_shots.size() + 4))
			get_tree().quit()


func _hint_shot(name: String) -> void:
	print("[SmokeTutorial] %s (hint=%s, focus=%s)" % [name, _tut.hint.get("id", ""), _tut.focus.get("rect", Rect2())])
	app.save_shot(name)
