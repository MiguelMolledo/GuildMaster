extends Node
## Scripted capture of the menus (--smoke-script=menu; through `grimoire heavy` with --always-on-top), against
## docs/ui/02_menu_inicial.md and its mock-ups: the title the first time (menu_titulo_primera), the new game screen
## (menu_partida_nueva), the game started from it, the pause menu (menu_pausa), saving in slot 1 (menu_guardar) and
## the overwrite question (menu_guardar_confirmar), loading with the autosave, a slot and a broken one (menu_cargar),
## the options (menu_opciones), quitting with something unsaved (menu_salir), the title with Continue (menu_titulo),
## the credits (menu_creditos) and the ending (menu_fin, menu_fin_pueblo). The saves go to user://smoke_menu_saves
## (the player's are not touched). Everything through the screens' own signals and buttons.

const SAVES: String = "user://smoke_menu_saves"

var app: Node = null
var timeout: float = 120.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	_clean()
	SaveSlots.dir = SAVES
	print("[SmokeMenu] start (timeout=%.0f s, saves=%s)" % [timeout, SAVES])


func _clean() -> void:
	if DirAccess.dir_exists_absolute(SAVES):
		for f: String in DirAccess.get_files_at(SAVES):
			DirAccess.remove_absolute(SAVES.path_join(f))
	else:
		DirAccess.make_dir_recursive_absolute(SAVES)


func _go(step: String) -> void:
	print("[SmokeMenu] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _shot(n: String) -> void:
	app.save_shot("menu_hoy_" + n)


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeMenu] TIMEOUT in step %s" % _step)
		app.save_shot("menu_timeout")
		get_tree().quit(1)
		return
	var title: TitleScreen = app.title_screen()
	var pause: PauseMenu = app.pause_menu()
	var saves: SaveScreen = app.save_screen()
	match _step:
		"start":
			if _t > 0.5:
				app.show_title()
				_go("title_first")
		"title_first":
			if _t > 1.0:
				_shot("titulo_primera")
				(title.get_node("%NewGameButton") as Button).pressed.emit()
				_go("new_game")
		"new_game":
			if _t > 0.6:
				var ng: NewGameScreen = app.new_game_screen()
				ng.add_point("craft", 2)
				ng.add_point("charisma", 1)
				ng.show_stat_help("craft")
				_go("new_game_shot")
		"new_game_shot":
			if _t > 0.4:
				_shot("partida_nueva")
				(app.new_game_screen().get_node("%StartButton") as Button).pressed.emit()
				_go("playing")
		"playing":
			if _t > 2.0:
				app.open_pause()
				_go("pause")
		"pause":
			if _t > 0.6:
				_shot("pausa")
				(pause.get_node("%SaveButton") as Button).pressed.emit()
				_go("save")
		"save":
			if _t > 0.6:
				_shot("guardar")
				(saves.row("slot_1").find_child("Save", true, false) as Button).pressed.emit()
				_go("saved")
		"saved":
			if _t > 0.6:
				(pause.get_node("%SaveButton") as Button).pressed.emit()
				_go("overwrite")
		"overwrite":
			if _t > 0.4:
				(saves.row("slot_1").find_child("Save", true, false) as Button).pressed.emit()
				_go("overwrite_shot")
		"overwrite_shot":
			if _t > 0.5:
				_shot("guardar_confirmar")
				(saves.get_node("%Confirm") as ConfirmDialog).button("cancel").pressed.emit()
				saves.back_requested.emit()
				Game.save_slot("auto")
				var f := FileAccess.open(SaveSlots.path_of("slot_3"), FileAccess.WRITE)
				f.store_string(JSON.stringify({"version": WorldState.VERSION + 1}))
				f.close()
				(pause.get_node("%LoadButton") as Button).pressed.emit()
				_go("load")
		"load":
			if _t > 0.6:
				_shot("cargar")
				saves.back_requested.emit()
				(pause.get_node("%OptionsButton") as Button).pressed.emit()
				_go("options")
		"options":
			if _t > 0.6:
				_shot("opciones")
				app.options_screen().back_requested.emit()
				(pause.get_node("%ResumeButton") as Button).pressed.emit()
				_go("play_more")
		"play_more":
			if _t > 1.5:
				app.open_pause()
				_go("quit_ask")
		"quit_ask":
			if _t > 0.4:
				(pause.get_node("%TitleButton") as Button).pressed.emit()
				_go("quit_shot")
		"quit_shot":
			if _t > 0.5:
				_shot("salir")
				(pause.get_node("%Confirm") as ConfirmDialog).button("discard").pressed.emit()
				_go("title")
		"title":
			if _t > 1.0:
				_shot("titulo")
				(title.get_node("%CreditsButton") as Button).pressed.emit()
				_go("credits")
		"credits":
			if _t > 0.6:
				_shot("creditos")
				app.credits_screen().back_requested.emit()
				(title.get_node("%ContinueButton") as Button).pressed.emit()
				_go("continued")
		"continued":
			if _t > 1.0:
				var st: WorldState = Game.sim.state
				st.ending = {"kind": "game_over", "family": SimQuery.player_family(st), "minute": int(st.clock["minute"])}
				_go("ending")
		"ending":
			if _t > 0.8:
				_shot("fin")
				(app.ending_screen().get_node("%ViewTownButton") as Button).pressed.emit()
				_go("ending_town")
		"ending_town":
			if _t > 0.6:
				_shot("fin_pueblo")
				_clean()
				_go("done")
				get_tree().quit()
