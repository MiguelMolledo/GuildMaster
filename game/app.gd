extends Node
## Main scene: the town view (WorldView), the inside of a building (InteriorView), the HUD, the background and the
## fade between town and interior (GDD 4.6.4: ~0.4 s, the exterior goes black, the game does not pause).
## Opens an interior when the selected person enters a building (event building_entered) or with "Manage"
## (double click on a building or the HUD button); closes it when that person leaves (building_left) or, in
## management mode, with the door / Exit / ESC. ESC closes the top panel first.
## Options after "--" (besides Game's): --smoke --shots=<n> --shot-every=<s> takes screenshots to reports/shots/ and
## quits (needs a window: run it through `grimoire heavy`). In smoke mode the first person of the human family starts
## selected, so the capture shows the selection. --smoke-script=<id> runs a scripted capture instead
## (game/smoke/smoke_<id>.gd; "forja" = the H2 forge screenshots, "mercado" = the H3 market, board, book and new
## game screens).
## H3: without --scenario (and without --smoke / --smoke-script) the game opens on the new game screen (GDD 4.16)
## over the paused default scenario; --new-game forces it. When state.ending is set (ruin, D18) the game pauses and
## the ending screen shows. A right click on a stall or the board opens its panel on arrival (HUD); the counter of a
## shop opens the market panel; a click on a notice centres the camera on its building or person.
## H4: a notice about an employee of the player's family (promotion, unpaid wage...) opens that building in
## management mode with its staff panel (GDD 4.18: "o abre su panel"). --smoke-script=empleados: the H4 captures.
## H5: --smoke-script=mejoras: the upgrade tree, the works and the upgrade visuals. --smoke-script=rebanada: the
## vertical slice played from the new game screen through three days (game/smoke/smoke_rebanada.gd). ESC closes the
## help overlay (F1) before anything else.
## H8: the group portraits select (HUD select_requested); the ending screen shows the dynasty score (Game Over);
## --smoke-script=familia: the family tree, the routine editor and the Game Over captures.
## --smoke-script=arte: the town's art (trees, river and bridge, a block, the plaza), camera on each place.
## H7: --smoke-script=ciudad: the plaza at dusk, the town at night, a townsperson's sheet, a microevent card and a
## customer at the counter.
## H14: --smoke-script=ia_familiar: the family AI panel, a spouse trading on her own, low needs.
## H11: --smoke-script=tribunal: the accusation, the preparation, the hearing, the verdict, accusing and banishment.
## --smoke-script=menu: every menu screen (title, new game, pause, save, load, options, quit, credits, ending).
## --smoke-script=escala: the plaza, the forge street and the town hall at zoom 1 and 2 (building scale B).
## UI 1/2: --smoke-script=hud: the new HUD's zones, the book beside the forge's bar, notices, help, ESC, the interior;
## --smoke-script=paneles: every existing panel in its zone (5, wide or big modal).
## H10: --smoke-script=cargos: the offices chart, running, the campaign, the result card and the inspector's powers.
## --gallery opens game/tools/gallery.tscn instead (every visual scene of game/visuals/ on the grid; with --smoke it
## saves reports/shots/gallery_01.png and quits). The AudioDirector node plays the sounds and music by id.
## Menus (docs/ui/02_menu_inicial.md): without --scenario (and without --smoke / --smoke-script) the game opens on the
## title screen over the default town paused at dusk (--new-game opens the new game screen instead). Title: Continue
## (the most recent save), New game, Load, Options, Credits, Quit. In the game, Esc with nothing open opens the pause
## menu (it pauses and locks the orders); F5 / F9 open save / load over it; F11 toggles full screen anywhere. The
## screens of ScreensLayer stack: the last one shown is on top. Saving keeps a thumbnail of what was seen
## (user://saves/<slot>.png). When the window loses the focus the sound goes down and the game pauses (options).

const GALLERY: String = "res://game/tools/gallery.tscn"
const TITLE_TILE: Vector2i = Vector2i(20, 15)  # the camera behind the title (the plaza, docs/ui/maquetas/fondos)
const SMOKE_SCRIPTS: Dictionary = {"forja": "res://game/smoke/smoke_forja.gd",
	"mercado": "res://game/smoke/smoke_mercado.gd", "empleados": "res://game/smoke/smoke_empleados.gd",
	"mejoras": "res://game/smoke/smoke_mejoras.gd", "rebanada": "res://game/smoke/smoke_rebanada.gd",
	"familia": "res://game/smoke/smoke_familia.gd", "arte": "res://game/smoke/smoke_arte.gd",
	"ciudad": "res://game/smoke/smoke_ciudad.gd", "titulos": "res://game/smoke/smoke_titulos.gd",
	"cargos": "res://game/smoke/smoke_cargos.gd", "tribunal": "res://game/smoke/smoke_tribunal.gd",
	"escala": "res://game/smoke/smoke_escala.gd", "ia_familiar": "res://game/smoke/smoke_ia_familiar.gd",
	"hud": "res://game/smoke/smoke_hud.gd", "paneles": "res://game/smoke/smoke_paneles.gd",
	"menu": "res://game/smoke/smoke_menu.gd"}

@onready var _background: ColorRect = %Background
@onready var _world: WorldView = %WorldView
@onready var _interior: InteriorView = %InteriorView
@onready var _hud: CanvasLayer = %Hud
@onready var _fade: ColorRect = %Fade
@onready var _new_game: NewGameScreen = %NewGameScreen
@onready var _ending: EndingScreen = %EndingScreen
@onready var _audio: AudioDirector = %AudioDirector
@onready var _title: TitleScreen = %TitleScreen
@onready var _pause: PauseMenu = %PauseMenu
@onready var _saves: SaveScreen = %SaveScreen
@onready var _options: OptionsScreen = %OptionsScreen
@onready var _credits: CreditsScreen = %CreditsScreen

var interior_building: String = ""   # "" = the town is shown
var _shots_left: int = 0
var _shot_every: float = 1.0
var _shot_timer: float = 0.0
var _shot_n: int = 0
var _bg_color: Color = Color.BLACK
var _fade_tween: Tween = null
var _menu_from: String = ""        # where the save / load / options / credits screens return: "title" | "pause"
var _after_save: String = ""       # "title" | "quit": the pause menu's "Save and quit" (after the save screen)
var _pause_shot: Image = null      # what was seen when the pause menu opened (the thumbnail of a save)
var _busy: bool = false            # a load or save is under way (the hourglass is shown)


func _ready() -> void:
	_bg_color = ViewConfig.color(str(ViewConfig.value("background", "#2b221b")))
	var script_id := ""
	var args := OS.get_cmdline_user_args()
	if args.has("--gallery"):
		Log.info("App", "gallery (%s)" % GALLERY)
		Game.set_paused(true)
		get_tree().change_scene_to_file.call_deferred(GALLERY)
		return
	for a: String in args:
		if a == "--smoke":
			_shots_left = maxi(_shots_left, 1)
		elif a.begins_with("--shots="):
			_shots_left = a.substr(8).to_int()
		elif a.begins_with("--shot-every="):
			_shot_every = a.substr(13).to_float()
		elif a.begins_with("--smoke-script="):
			script_id = a.substr(15)
	_interior.order_sink = Game.give
	_interior.set_active(false)
	_world.selection_changed.connect(_on_world_selection)
	_world.building_picked.connect(func(id: String) -> void: _hud.set_building(id))
	_world.npc_picked.connect(func(id: String) -> void: _hud.open_npc(id))  # H7: a townsperson's sheet
	_world.manage_requested.connect(func(id: String) -> void:
		if _owns(id):
			open_interior(id, true))
	_hud.manage_pressed.connect(func(id: String) -> void: open_interior(id, true))
	_world.service_requested.connect(_hud.request_service)
	_interior.shop_requested.connect(_hud.open_market)
	_hud.focus_requested.connect(focus_on)
	_hud.select_requested.connect(func(id: String) -> void: _world.select(id))  # H8: the group (1-2-3, portraits)
	_hud.deselect_requested.connect(func() -> void: _world.pick_building_id(""))  # ESC forgets the picked building
	_new_game.started.connect(_on_new_game_started)
	_new_game.back_requested.connect(func() -> void:
		_new_game.close()
		show_title())
	_ending.new_game_pressed.connect(show_new_game)
	_ending.title_pressed.connect(show_title)
	_bind_menus()
	_interior.selection_changed.connect(func(id: String) -> void: _world.select(id))
	_interior.close_requested.connect(close_interior)
	Events.sim_event.connect(_on_sim_event)
	Game.started.connect(func() -> void:
		_close_now()
		_hud.close_panels())
	if script_id != "":
		_shots_left = 0
		if SMOKE_SCRIPTS.has(script_id):
			var runner: Node = (load(SMOKE_SCRIPTS[script_id]) as GDScript).new()
			runner.name = "SmokeScript"
			runner.set("app", self)
			add_child(runner)
		else:
			push_error("unknown --smoke-script=%s" % script_id)
	elif _shots_left > 0:
		_world.select(_world.first_selectable())
	var opts := Game.parse_args(args)
	if bool(opts["title"]):
		show_title()
	elif bool(opts["new_game"]):
		show_new_game()


func _bind_menus() -> void:
	var time: Dictionary = Game.sim.catalog.time if Game.sim != null else {}
	_title.time_config = time
	_saves.time_config = time
	_title.continue_pressed.connect(func(slot: String) -> void: load_game(slot))
	_title.new_game_pressed.connect(show_new_game)
	_title.load_pressed.connect(func() -> void: _open_sub("title", _saves, "load"))
	_title.options_pressed.connect(func() -> void: _open_sub("title", _options))
	_title.credits_pressed.connect(func() -> void: _open_sub("title", _credits))
	_title.quit_pressed.connect(func() -> void: get_tree().quit())
	for screen: MenuScreen in [_saves, _options, _credits]:
		var sc := screen
		sc.back_requested.connect(func() -> void: _close_sub(sc))
	_saves.load_requested.connect(load_game)
	_saves.save_requested.connect(save_game)
	_pause.save_requested.connect(func() -> void: _open_sub("pause", _saves, "save"))
	_pause.load_requested.connect(func() -> void: _open_sub("pause", _saves, "load"))
	_pause.options_requested.connect(func() -> void: _open_sub("pause", _options))
	_pause.help_requested.connect(func() -> void:
		_pause.close()
		if not _hud.help_visible():
			_hud.toggle_help())
	_pause.close_dynasty_confirmed.connect(_close_dynasty)
	_pause.quit_requested.connect(func(where: String, save_first: bool) -> void:
		if save_first:
			_after_save = where
			_open_sub("pause", _saves, "save")
		else:
			_quit_to(where))
	Game.saved.connect(_on_saved)
	_hud.pause_menu_requested.connect(open_pause)  # the HUD's Esc with nothing open and its Menu button


## A menu screen over the title or the pause menu (which hides its own column meanwhile).
func _open_sub(from: String, screen: MenuScreen, mode: String = "") -> void:
	_menu_from = from
	if from == "title":
		_title.set_covered(true)
	else:
		_pause.set_covered(true)
	if screen == _saves:
		_saves.open_mode(mode)
	else:
		screen.open()


func _close_sub(screen: MenuScreen) -> void:
	screen.close()
	_after_save = ""
	if _menu_from == "title" and _title.visible:
		_title.open()
	elif _menu_from == "pause" and _pause.visible:
		_pause.open()


## Any menu screen is shown (the game below takes no keys then).
func menu_open() -> bool:
	for c: Node in get_node("ScreensLayer").get_children():
		if (c as Control).visible:
			return true
	return false


func title_screen() -> TitleScreen:
	return _title


func pause_menu() -> PauseMenu:
	return _pause


func save_screen() -> SaveScreen:
	return _saves


func options_screen() -> OptionsScreen:
	return _options


func credits_screen() -> CreditsScreen:
	return _credits


## The title (02 §1): the default town paused at dusk behind (decision 2), the HUD hidden, the orders locked.
func show_title() -> void:
	for sc: MenuScreen in [_new_game, _ending, _pause, _saves, _options, _credits]:
		sc.close()
	var opts := Game.parse_args(OS.get_cmdline_user_args())
	var r := NewGame.from_scenario(Game.DEFAULT_SCENARIO, int(opts["seed"]))
	if r["ok"]:
		var st: WorldState = r["state"]
		var time: Dictionary = Game.sim.catalog.time
		var starts: Dictionary = time["phase_starts"][Clock.season(int(st.clock["minute"]), time)]
		var dusk := int(starts["dusk"])
		Game.set_time_of_day(st, dusk + (int(starts["night"]) - dusk) * 3 / 4)  # late dusk: torches lit
		Game.start(st, Game.sim.catalog)
		_world.camera().center_on(Iso.tile_to_world(TITLE_TILE))
	_set_signs_visible(false)
	_hud.visible = false
	Game.set_paused(true)
	Game.lock_orders(true)
	_title.open()
	Log.info("App", "title screen")


func new_game_screen() -> NewGameScreen:
	return _new_game


func ending_screen() -> EndingScreen:
	return _ending


## The new game screen over the paused town (GDD 4.16).
func show_new_game() -> void:
	var opts := Game.parse_args(OS.get_cmdline_user_args())
	var seed_value: int = opts["seed"] if int(opts["seed"]) >= 0 else randi() % 1000000 + 1
	_ending.close()
	_title.close()
	_new_game.setup(Game.sim.catalog, seed_value)
	_new_game.open()
	_hud.visible = false
	Game.set_paused(true)
	Log.info("App", "new game screen (seed=%d)" % seed_value)


func _on_new_game_started(state: WorldState) -> void:
	Log.info("App", "new game started (family=%s, difficulty=%s)" % [SimQuery.player_family(state), state.difficulty])
	_new_game.close()
	_ending.close()
	_title.close()
	Game.start(state, Game.sim.catalog)
	_enter_game()


## The signs over the buildings and the stalls (hidden behind the title, as in its mock-up).
func _set_signs_visible(on: bool) -> void:
	for table: String in ["_signs", "_service_signs"]:
		var signs: Variant = _world.get(table)
		if signs is Dictionary:
			for k: Variant in signs:
				(signs[k] as CanvasItem).visible = on


## Back in the town after a menu: every menu closed, the HUD shown, orders unlocked, the clock running.
func _enter_game() -> void:
	for sc: MenuScreen in [_title, _new_game, _ending, _pause, _saves, _options, _credits]:
		sc.close()
	_set_signs_visible(true)
	_hud.visible = true
	Game.lock_orders(false)
	Game.set_paused(false)
	_world.select(_world.first_selectable())


## Loads a slot (Continue, the load screen) and plays it at the "speed on load" of the options.
func load_game(slot: String) -> void:
	if _busy:
		return
	_busy = true
	UiFeel.wait(true)
	await get_tree().process_frame  # the hourglass shows before the work
	var r := Game.load_slot(slot)
	UiFeel.wait(false)
	_busy = false
	if not bool(r.get("ok", false)):
		Log.info("App", "load %s failed (error=%s)" % [slot, r.get("error", "")])
		if _saves.visible:
			_saves.open_mode(_saves.mode)
		elif _title.visible:
			_title.open()
		return
	Log.info("App", "loaded %s" % slot)
	_enter_game()
	Game.set_speed(int(Settings.value("game/load_speed")))


## Saves in a slot from the save screen; then back to the pause menu, or on to quit ("Save and quit").
func save_game(slot: String) -> void:
	if _busy:
		return
	_busy = true
	UiFeel.wait(true)
	await get_tree().process_frame  # the hourglass shows before the work
	var e := Game.save_slot(slot)
	UiFeel.wait(false)
	_busy = false
	Log.info("App", "save %s (%s)" % [slot, error_string(e)])
	if e == OK:
		_audio.play("sfx_ui_seal")  # 02 §3: the seal of a saved game
	_saves.close()
	var then := _after_save
	_after_save = ""
	if e == OK and then != "":
		_quit_to(then)
	elif _pause.visible:
		_pause.open()


## A slot was written: its thumbnail is what was seen (when the pause menu opened, or the screen now).
func _on_saved(slot: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := _pause_shot if slot != SaveSlots.AUTOSAVE and _pause_shot != null else get_viewport().get_texture().get_image()
	SaveSlots.save_thumbnail(slot, img)


## The pause menu (02 §6): what is seen now becomes the thumbnail of a save made from it.
func open_pause() -> void:
	if menu_open() or Game.sim == null or not Game.sim.state.ending.is_empty():
		return
	_pause_shot = null
	if DisplayServer.get_name() != "headless":
		_pause_shot = get_viewport().get_texture().get_image()
	_pause.open()


func _quit_to(where: String) -> void:
	Log.info("App", "quit to %s" % where)
	if where == "quit":
		get_tree().quit()
	else:
		show_title()


## D19: "End the dynasty" confirmed in the pause menu: the order is applied now (the menu locks the queue).
func _close_dynasty() -> void:
	_pause.close()
	var st := Game.sim.state
	var fam := SimQuery.player_family(st)
	var r := Orders.apply(Game.sim, {"type": "close_dynasty", "actor": SimQuery.family_actor(st, fam, _world.selected_id)})
	Log.info("App", "close dynasty (ok=%s, reason=%s)" % [r.get("ok", false), r.get("reason", "")])


func _owns(building: String) -> bool:
	for id: String in Game.sim.state.characters:
		if str(Game.sim.state.characters[id].get("controlled_by", "")) == "human" and SimQuery.is_own(Game.sim.state, id, building):
			return true
	return false


## A notice was clicked: back to the town if needed, the camera on the building (its door) or the person (or the
## building they are in); a person of the player's family is selected.
func focus_on(target: String) -> void:
	var st := Game.sim.state
	var tile := Vector2i(-999, -999)
	var workplace := Staff.employer(st, target) if st.characters.has(target) else ""
	if workplace != "" and _owns(workplace):
		Log.info("App", "focus employee %s: staff panel of %s" % [target, workplace])
		open_interior(workplace, true, "staff")
		return
	if st.buildings.has(target):
		var d: Array = st.buildings[target].get("door", [])
		if d.size() == 2:
			tile = Vector2i(int(d[0]), int(d[1]))
		_world.pick_building_id(target)
	elif st.characters.has(target):
		var ch: Dictionary = st.characters[target]
		var loc := str(ch.get("location", ""))
		var p: Array = st.buildings.get(loc, {}).get("door", []) if loc != "" else ch.get("position", [])
		if p.size() == 2:
			tile = Vector2i(int(p[0]), int(p[1]))
		if _world.view_of(target) != null and _world.view_of(target).selectable:
			_world.select(target)
	if tile.x == -999:
		return
	Log.info("App", "focus %s (tile=%s)" % [target, tile])
	if interior_building != "":
		_close_now()
	_world.camera().center_on(Iso.tile_to_world(tile))


func audio() -> AudioDirector:
	return _audio


func world() -> WorldView:
	return _world


func interior() -> InteriorView:
	return _interior


func hud() -> CanvasLayer:
	return _hud


func _on_world_selection(id: String) -> void:
	_hud.set_selected(id)
	if interior_building != "":
		_interior.select(id)


## Shows the inside of `building` (with the selected person, or in management mode) after a fade. `panel` = "staff"
## opens its staff panel too.
func open_interior(building: String, manage: bool, panel: String = "") -> void:
	if building == "" or not Game.sim.state.buildings.has(building):
		return
	Log.info("App", "open interior (building=%s, manage=%s, selected=%s)" % [building, manage, _world.selected_id])
	_fade_swap(func() -> void:
		interior_building = building
		_interior.setup(Game.sim, building, _world.selected_id, manage)
		_interior.set_active(true)
		_world.set_active(false)
		_hud.set_interior(true)
		if panel == "staff":
			_interior.show_staff(true, "staff"))


## Back to the town, centred on the building's door.
func close_interior() -> void:
	if interior_building == "":
		return
	Log.info("App", "close interior (building=%s)" % interior_building)
	var bld := interior_building
	_fade_swap(func() -> void:
		_close_now()
		var d: Array = Game.sim.state.buildings.get(bld, {}).get("door", [])
		if d.size() == 2:
			_world.camera().center_on(Iso.tile_to_world(Vector2i(int(d[0]), int(d[1])))))


func _close_now() -> void:
	interior_building = ""
	_interior.set_active(false)
	_world.set_active(true)
	_hud.set_interior(false)


## Fade to black, run `swap`, fade back (fade_seconds in total, data/view.json "interior").
func _fade_swap(swap: Callable) -> void:
	var half := float(ViewConfig.value("interior", {}).get("fade_seconds", 0.4)) / 2.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", 1.0, half)
	_fade_tween.tween_callback(swap)
	_fade_tween.tween_property(_fade, "color:a", 0.0, half)


func _on_sim_event(e: Dictionary) -> void:
	var type := str(e.get("type", ""))
	var actor := str(e.get("actor", ""))
	if type == "building_entered" and actor == _world.selected_id and actor != "":
		if interior_building != str(e.get("building", "")):
			open_interior(str(e.get("building", "")), false)
	elif type == "building_left" and interior_building != "" and str(e.get("building", "")) == interior_building:
		if not _interior.manage and actor == _interior.selected_id:
			close_interior()
	if interior_building != "":
		_interior.on_sim_event(e)


## ESC: the top panel closes first (station menu, building panels, the person's panel); with nothing open inside a
## building, leave it (GDD 4.6.4).
## F5 / F9 in the game open the pause menu with save / load over it. With nothing open, ESC asks the HUD for the
## pause menu (hud.pause_menu_requested).
func _unhandled_input(event: InputEvent) -> void:
	if menu_open():
		return  # the screens take the keys themselves (they get them before the HUD)
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and \
			(event as InputEventKey).keycode in [KEY_F5, KEY_F9]:
		open_pause()
		_open_sub("pause", _saves, "save" if (event as InputEventKey).keycode == KEY_F5 else "load")
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _hud.help_visible():
		_hud.toggle_help()
	elif interior_building != "" and _interior.close_top():
		pass
	elif _hud.close_top():
		pass
	elif interior_building != "":
		_interior.request_exit()
	else:
		_hud.request_pause_menu()   # nothing open: the pause menu (hud.pause_menu_requested, docs/ui/01 §2)
	get_viewport().set_input_as_handled()


## F11: full screen on / off, anywhere (also over the menus).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_F11:
		Settings.set_value("display/fullscreen", not bool(Settings.value("display/fullscreen")))
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Settings.set_unfocused(true)
		if bool(Settings.value("game/pause_unfocused")) and not menu_open() and _shots_left <= 0 \
				and not has_node("SmokeScript") and Game.sim != null:
			Game.set_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Settings.set_unfocused(false)


func _process(delta: float) -> void:
	if Game.sim != null and not Game.sim.state.ending.is_empty() and not _ending.visible and not _title.visible \
			and not _new_game.visible:
		Game.set_paused(true)  # D18: the ruin ends the game; the sim does not stop by itself
		Game.lock_orders(true)
		for sc: MenuScreen in [_pause, _saves, _options, _credits]:
			sc.close()
		_hud.visible = false
		_ending.show_ending(Game.sim.state, Game.sim)
		_audio.play("sfx_ui_seal")  # 02 §7: the seal of the ending appears
	_background.color = Color.BLACK if interior_building != "" else _bg_color * _world.tint_color
	_reveal_selection()
	if _shots_left <= 0:
		return
	_shot_timer += delta
	if _shot_timer < _shot_every:
		return
	_shot_timer = 0.0
	_shot_n += 1
	save_shot("smoke_%02d" % _shot_n)
	_shots_left -= 1
	if _shots_left == 0:
		get_tree().quit()


var _reveal_sig: String = ""


## docs/ui/01 §4.6: when the selection or the open panel changes, the camera moves just enough so that the selected
## person (or the picked building) is not under the management panel or the selection bar.
func _reveal_selection() -> void:
	if interior_building != "" or Game.sim == null:
		_reveal_sig = ""
		return
	var open: Control = _hud.open_manage_panel()
	var sig := "%s|%s|%s" % [_world.selected_id, _world.picked_building, open.name if open != null else ""]
	if sig == _reveal_sig:
		return
	_reveal_sig = sig
	var at := Vector2.INF
	if _world.view_of(_world.selected_id) != null:
		at = _world.view_of(_world.selected_id).position
	elif _world.picked_building != "":
		var d: Array = Game.sim.state.buildings.get(_world.picked_building, {}).get("door", [])
		if d.size() == 2:
			at = Iso.tile_to_world(Vector2i(int(d[0]), int(d[1])))
	if at == Vector2.INF:
		return
	var cam := _world.camera()
	var vp := get_viewport().get_visible_rect().size
	var z := HudLayout.zones(vp)
	var free := Rect2(Vector2((z["column"] as Rect2).end.x, (z["status"] as Rect2).end.y + 4.0),
		Vector2.ZERO).expand(Vector2(vp.x - 4.0, (z["selection"] as Rect2).position.y - 4.0))
	var blocked: Array = _hud.covered_rects()
	if open != null:
		free.end.x = minf(free.end.x, open.get_global_rect().position.x - 4.0)
	var delta := HudLayout.reveal_delta(cam.world_to_screen(at), blocked, free)
	if delta != Vector2.ZERO:
		Log.info("App", "camera reveals %s (delta=%s)" % [sig, delta])
		cam.pan(delta)


## Saves what the player sees to reports/shots/<shot_name>.png: the 960×540 render scaled by the window's whole
## factor (D2), pixel for pixel.
func save_shot(shot_name: String) -> String:
	var dir := ProjectSettings.globalize_path("res://reports/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(shot_name + ".png")
	var img := get_viewport().get_texture().get_image()
	var vp := img.get_size()
	var k := maxi(1, mini(get_window().size.x / vp.x, get_window().size.y / vp.y))
	if k > 1:
		img.resize(vp.x * k, vp.y * k, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("[Smoke] shot %s (x%d)" % [path, k])
	return path
