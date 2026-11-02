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
## --gallery opens game/tools/gallery.tscn instead (every visual scene of game/visuals/ on the grid; with --smoke it
## saves reports/shots/gallery_01.png and quits). The AudioDirector node plays the sounds and music by id.

const GALLERY: String = "res://game/tools/gallery.tscn"
const SMOKE_SCRIPTS: Dictionary = {"forja": "res://game/smoke/smoke_forja.gd",
	"mercado": "res://game/smoke/smoke_mercado.gd", "empleados": "res://game/smoke/smoke_empleados.gd",
	"mejoras": "res://game/smoke/smoke_mejoras.gd", "rebanada": "res://game/smoke/smoke_rebanada.gd"}

@onready var _background: ColorRect = %Background
@onready var _world: WorldView = %WorldView
@onready var _interior: InteriorView = %InteriorView
@onready var _hud: CanvasLayer = %Hud
@onready var _fade: ColorRect = %Fade
@onready var _new_game: NewGameScreen = %NewGameScreen
@onready var _ending: EndingScreen = %EndingScreen
@onready var _audio: AudioDirector = %AudioDirector

var interior_building: String = ""   # "" = the town is shown
var _shots_left: int = 0
var _shot_every: float = 1.0
var _shot_timer: float = 0.0
var _shot_n: int = 0
var _bg_color: Color = Color.BLACK
var _fade_tween: Tween = null


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
	_world.manage_requested.connect(func(id: String) -> void:
		if _owns(id):
			open_interior(id, true))
	_hud.manage_pressed.connect(func(id: String) -> void: open_interior(id, true))
	_world.service_requested.connect(_hud.request_service)
	_interior.shop_requested.connect(_hud.open_market)
	_hud.focus_requested.connect(focus_on)
	_new_game.started.connect(_on_new_game_started)
	_ending.new_game_pressed.connect(show_new_game)
	_ending.quit_pressed.connect(func() -> void: get_tree().quit())
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
	if bool(Game.parse_args(args)["new_game"]):
		show_new_game()


func new_game_screen() -> NewGameScreen:
	return _new_game


func ending_screen() -> EndingScreen:
	return _ending


## The new game screen over the paused town (GDD 4.16).
func show_new_game() -> void:
	var opts := Game.parse_args(OS.get_cmdline_user_args())
	var seed_value: int = opts["seed"] if int(opts["seed"]) >= 0 else randi() % 1000000 + 1
	_ending.visible = false
	_new_game.setup(Game.sim.catalog, seed_value)
	_new_game.visible = true
	Game.set_paused(true)
	Log.info("App", "new game screen (seed=%d)" % seed_value)


func _on_new_game_started(state: WorldState) -> void:
	Log.info("App", "new game started (family=%s, difficulty=%s)" % [SimQuery.player_family(state), state.difficulty])
	_new_game.visible = false
	_ending.visible = false
	Game.start(state, Game.sim.catalog)
	Game.set_paused(false)
	_world.select(_world.first_selectable())


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
func _unhandled_input(event: InputEvent) -> void:
	if _new_game.visible or _ending.visible:
		return  # the screens take the keys themselves (they get them before the HUD)
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
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if Game.sim != null and not Game.sim.state.ending.is_empty() and not _ending.visible:
		Game.set_paused(true)  # D18: the ruin ends the game; the sim does not stop by itself
		_ending.show_ending(Game.sim.state)
	_background.color = Color.BLACK if interior_building != "" else _bg_color * _world.tint_color
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
