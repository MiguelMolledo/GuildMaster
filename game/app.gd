extends Node
## Main scene (H1): the town view (WorldView), the HUD and the background. Options after "--" (besides Game's):
## --smoke --shots=<n> --shot-every=<s> takes screenshots to reports/shots/ and quits (needs a window: run it
## through `grimoire heavy`). In smoke mode the first person of the human family starts selected, so the capture
## shows the selection.

@onready var _background: ColorRect = %Background
@onready var _world: WorldView = %WorldView

var _shots_left: int = 0
var _shot_every: float = 1.0
var _shot_timer: float = 0.0
var _shot_n: int = 0
var _bg_color: Color = Color.BLACK


func _ready() -> void:
	_bg_color = ViewConfig.color(str(ViewConfig.value("background", "#2b221b")))
	for a: String in OS.get_cmdline_user_args():
		if a == "--smoke":
			_shots_left = maxi(_shots_left, 1)
		elif a.begins_with("--shots="):
			_shots_left = a.substr(8).to_int()
		elif a.begins_with("--shot-every="):
			_shot_every = a.substr(13).to_float()
	if _shots_left > 0:
		_world.select(_world.first_selectable())


func _process(delta: float) -> void:
	_background.color = _bg_color * _world.tint_color
	if _shots_left <= 0:
		return
	_shot_timer += delta
	if _shot_timer < _shot_every:
		return
	_shot_timer = 0.0
	_shot_n += 1
	var dir := ProjectSettings.globalize_path("res://reports/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("smoke_%02d.png" % _shot_n)
	var img := get_viewport().get_texture().get_image()
	# What the player sees: the 960×540 render scaled by the window's whole factor (D2), pixel for pixel.
	var vp := img.get_size()
	var k := maxi(1, mini(get_window().size.x / vp.x, get_window().size.y / vp.y))
	if k > 1:
		img.resize(vp.x * k, vp.y * k, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("[Smoke] shot %s (x%d)" % [path, k])
	_shots_left -= 1
	if _shots_left == 0:
		get_tree().quit()
