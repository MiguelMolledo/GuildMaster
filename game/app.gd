extends Node
## Main scene: the town view (WorldView), the inside of a building (InteriorView), the HUD, the background and the
## fade between town and interior (GDD 4.6.4: ~0.4 s, the exterior goes black, the game does not pause).
## Opens an interior when the selected person enters a building (event building_entered) or with "Manage"
## (double click on a building or the HUD button); closes it when that person leaves (building_left) or, in
## management mode, with the door / Exit / ESC. ESC closes the top panel first.
## Options after "--" (besides Game's): --smoke --shots=<n> --shot-every=<s> takes screenshots to reports/shots/ and
## quits (needs a window: run it through `grimoire heavy`). In smoke mode the first person of the human family starts
## selected, so the capture shows the selection. --smoke-script=<id> runs a scripted capture instead
## (game/smoke/smoke_<id>.gd; "forja" = the H2 forge screenshots).

const SMOKE_SCRIPTS: Dictionary = {"forja": "res://game/smoke/smoke_forja.gd"}

@onready var _background: ColorRect = %Background
@onready var _world: WorldView = %WorldView
@onready var _interior: InteriorView = %InteriorView
@onready var _hud: CanvasLayer = %Hud
@onready var _fade: ColorRect = %Fade

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
	for a: String in OS.get_cmdline_user_args():
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
	_world.manage_requested.connect(func(id: String) -> void: open_interior(id, true))
	_hud.manage_pressed.connect(func(id: String) -> void: open_interior(id, true))
	_interior.selection_changed.connect(func(id: String) -> void: _world.select(id))
	_interior.close_requested.connect(close_interior)
	Events.sim_event.connect(_on_sim_event)
	Game.started.connect(func() -> void: _close_now())
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


## Shows the inside of `building` (with the selected person, or in management mode) after a fade.
func open_interior(building: String, manage: bool) -> void:
	if building == "" or not Game.sim.state.buildings.has(building):
		return
	Log.info("App", "open interior (building=%s, manage=%s, selected=%s)" % [building, manage, _world.selected_id])
	_fade_swap(func() -> void:
		interior_building = building
		_interior.setup(Game.sim, building, _world.selected_id, manage)
		_interior.set_active(true)
		_world.set_active(false)
		_hud.set_interior(true))


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
	if not event.is_action_pressed("ui_cancel"):
		return
	if interior_building != "" and _interior.close_top():
		pass
	elif _hud.close_top():
		pass
	elif interior_building != "":
		_interior.request_exit()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
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
