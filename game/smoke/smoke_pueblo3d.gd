extends Node
## Scripted capture of the 3D town in play (--smoke-script=pueblo3d, docs/3d/plan.md M3D-1; run it through
## `grimoire heavy` with the engine's --always-on-top and --resolution 1600x900): a new game in Normal (the
## blacksmith's start, the new game screen's signal, as the player starts one) at 10:00, running at ×1. It measures the
## frame rate and the draw calls with the whole town in view and in the street (vsync off), and takes
## reports/shots/pueblo3d_<view>.png: the whole town, a street with the protagonist, the plaza, the same street at ×4,
## dusk and night (the clock moved on, capture only). Writes reports/perf/pueblo3d.json. Quits when done, or after
## `timeout` seconds. --smoke-seed=<n> the game's seed (1).

const START: String = "artisan_blacksmith"
const PLAZA: Vector2i = Vector2i(20, 15)
## [name, what, seconds] in order; "measure_*" counts frames for that long.
const STEPS: Array = [
	["vista", "town", 3.0], ["measure_vista", "town", 6.0],
	["calle", "street", 2.5], ["measure_calle", "street", 6.0],
	["plaza", "plaza", 2.5],
	["calle_x4", "street_x4", 3.0],
	["atardecer", "dusk", 2.5], ["noche", "night", 2.5], ["noche_calle", "night_street", 2.0]]

var app: Node = null
var timeout: float = 240.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -2
var _frames: int = 0
var _dc_sum: float = 0.0
var _prim_sum: float = 0.0
var _worst: float = 0.0
var _perf: Dictionary = {}


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("[SmokePueblo3D] start (%d steps, view=%s)" % [STEPS.size(), app.get("view_mode")])


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokePueblo3D] TIMEOUT at step %d" % _i)
		get_tree().quit(1)
		return
	if _i == -2:
		if _t > 0.5:
			_begin()
		return
	if _i == -1:
		if _t > 1.0:
			_next()
		return
	var step: Array = STEPS[_i]
	if str(step[0]).begins_with("measure_"):
		_frames += 1
		_worst = maxf(_worst, delta)
		_dc_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		_prim_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	if _t >= float(step[2]):
		_finish(step)
		_next()


## A new game in Normal as the new game screen gives it (NewGameScreen.started), at 10:00.
func _begin() -> void:
	var seed_value := 1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-seed="):
			seed_value = a.substr(13).to_int()
	var r := NewGame.from_start(Data.catalog, START, "normal", {}, seed_value)
	if not bool(r.get("ok", false)):
		print("[SmokePueblo3D] from_start failed: %s" % r.get("error", ""))
		get_tree().quit(1)
		return
	var st: WorldState = r["state"]
	Game.set_time_of_day(st, 10 * 60)
	(app.new_game_screen() as NewGameScreen).started.emit(st)
	Game.set_speed(1)
	_i = -1
	_t = 0.0
	var w := _w3()
	var root := get_tree().root
	print("[SmokePueblo3D] window %s, root size %s, visible %s, scale mode %d, stretch %d, factor %.2f, texture %s" % [
		DisplayServer.window_get_size(), root.size, root.get_visible_rect().size, root.content_scale_mode,
		root.content_scale_stretch, root.content_scale_factor, root.get_texture().get_size()])
	print("[SmokePueblo3D] new game %s (seed %d): town built in %d ms, %d houses, %d people" % [START, seed_value,
		w.build_ms, w.town.houses.size(), w.town.people.size()])
	_perf["build_ms"] = w.build_ms
	_perf["houses"] = w.town.houses.size()
	_perf["people"] = w.town.people.size()


func _w3() -> WorldView3D:
	return app.call("world3d") as WorldView3D


func _next() -> void:
	_i += 1
	_t = 0.0
	_frames = 0
	_dc_sum = 0.0
	_prim_sum = 0.0
	_worst = 0.0
	if _i >= STEPS.size():
		_write_perf()
		print("[SmokePueblo3D] done")
		get_tree().quit(0)
		return
	_view(str(STEPS[_i][1]))


func _finish(step: Array) -> void:
	var name_ := str(step[0])
	if name_.begins_with("measure_"):
		var fps := float(_frames) / maxf(0.001, _t)
		var m := {"fps": snappedf(fps, 0.1), "worst_frame_ms": snappedf(_worst * 1000.0, 0.1),
			"draw_calls": int(_dc_sum / maxf(1.0, float(_frames))), "primitives": int(_prim_sum / maxf(1.0, float(_frames))),
			"frames": _frames, "size": str(get_viewport().get_visible_rect().size),
			"window": str(DisplayServer.window_get_size()), "cam_size": snappedf(_w3().town.cam.size, 0.1),
			"people_shown": _shown()}
		_perf[name_.trim_prefix("measure_")] = m
		print("[SmokePueblo3D] %s: %s" % [name_, JSON.stringify(m)])
		return
	app.call("save_shot", "pueblo3d_" + name_)


func _shown() -> int:
	var n := 0
	for id: Variant in _w3().town.people:
		if (_w3().town.people[id].node as Node3D).visible:
			n += 1
	return n


## The camera and the clock for a view.
func _view(what: String) -> void:
	var town := _w3().town
	var me := str(Game.sim.state.families.get(SimQuery.player_family(Game.sim.state), {}).get("head", ""))
	var p: Array = Game.sim.state.characters.get(me, {}).get("position", [PLAZA.x, PLAZA.y])
	match what:
		"town":
			town.look_at_tile(Vector2(town.W / 2.0, town.H / 2.0))
			town.cam.size = 74.0
		"street", "street_x4":
			town.follow_id = me
			town.look_at_tile(Vector2(float(p[0]), float(p[1])))
			town.cam.size = 18.0
			Game.set_speed(4 if what == "street_x4" else 1)
		"plaza":
			town.follow_id = ""
			town.look_at_tile(Vector2(PLAZA))
			town.cam.size = 30.0
			Game.set_speed(1)
		"dusk", "night":
			var starts: Dictionary = Game.sim.catalog.time["phase_starts"][Clock.season(int(Game.sim.state.clock["minute"]),
				Game.sim.catalog.time)]
			var at := int(starts["dusk"]) + 20 if what == "dusk" else int(starts["night"]) + 60
			Game.set_time_of_day(Game.sim.state, at)  # capture only
			town.follow_id = ""
			town.look_at_tile(Vector2(PLAZA))
			town.cam.size = 40.0
		"night_street":
			town.look_at_tile(Vector2(float(p[0]), float(p[1])))
			town.cam.size = 16.0
	town._update_camera()
	print("[SmokePueblo3D] view %s (cam size %.1f, minute %d)" % [what, town.cam.size, int(Game.sim.state.clock["minute"])])


func _write_perf() -> void:
	var dir := ProjectSettings.globalize_path("res://reports/perf")
	DirAccess.make_dir_recursive_absolute(dir)
	_perf["renderer"] = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	_perf["adapter"] = RenderingServer.get_video_adapter_name()
	_perf["made"] = Time.get_datetime_string_from_system()
	var f := FileAccess.open(dir.path_join("pueblo3d.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_perf, "  "))
	f.close()
	print("[SmokePueblo3D] perf -> reports/perf/pueblo3d.json")
