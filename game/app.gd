extends Control
## Main scene. H0: an empty world with the clock running and the HUD clock. Later milestones put the map view here.
## Options after "--" (besides Game's): --smoke --shots=<n> --shot-every=<s> takes screenshots to reports/shots/ and
## quits (needs a window: run it through `grimoire heavy`).

@onready var _clock_label: Label = %ClockLabel
@onready var _title_label: Label = %TitleLabel

var _shots_left: int = 0
var _shot_every: float = 1.0
var _shot_timer: float = 0.0
var _shot_n: int = 0


func _ready() -> void:
	_title_label.text = tr("app.title")
	for a: String in OS.get_cmdline_user_args():
		if a == "--smoke":
			_shots_left = maxi(_shots_left, 1)
		elif a.begins_with("--shots="):
			_shots_left = a.substr(8).to_int()
		elif a.begins_with("--shot-every="):
			_shot_every = a.substr(13).to_float()
	Events.step_done.connect(func(_e: Array) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	var t := Game.sim.now()
	_clock_label.text = tr("hud.clock") % [t["day"], tr("season." + str(t["season"])), t["year"], t["hour"], t["minute"],
		tr("phase." + str(t["phase"]))]


func _process(delta: float) -> void:
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
	get_viewport().get_texture().get_image().save_png(path)
	print("[Smoke] shot %s" % path)
	_shots_left -= 1
	if _shots_left == 0:
		get_tree().quit()
