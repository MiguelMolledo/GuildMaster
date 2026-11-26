extends Node
## The sim's festivals dressed in the 3D town (M3D-5; --smoke-script=fiesta3d; with a window through `grimoire heavy`,
## a shot per festival reports/shots/fiesta3d_<id>.png). For each festival of data/festivals.json with a town layout
## (data/view3d/fiestas.json pueblo): a new game on its day, two hours after it starts, the festival put on the
## calendar with the sim's own Festivals._schedule (a fixed one falls on its day of the year anyway), and the town
## checked: FiestasPueblo has it in force and its pieces up (mounted). --fiesta3d=<id>[,<id>] only those.
## --fiesta3d-perf: then the biggest one with rain (--tiempo=lluvia is the weather's own argument) at 1600×900, the
## camera over the plaza: frames for 8 s -> reports/perf/fiesta3d.json (fps, worst frame). Prints
## "[SmokeFiesta3D] ok|FAIL ..."; quits 1 on a FAIL or a timeout.

const START: String = "artisan_blacksmith"
const PERF_ID: String = "harvest_fair"

var app: Node = null
var timeout: float = 400.0
var _total: float = 0.0
var _fails: int = 0
var _res: Dictionary = {}


func _ready() -> void:
	print("[SmokeFiesta3D] start")
	_run.call_deferred()


func _process(delta: float) -> void:
	_total += delta
	if _total > timeout:
		print("[SmokeFiesta3D] TIMEOUT")
		get_tree().quit(1)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(cond: bool, what: String) -> void:
	print("[SmokeFiesta3D] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _run() -> void:
	await _wait(0.5)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1600, 900)
	var defs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/festivals.json")).get("festivals", {})
	var lay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/view3d/fiestas.json")).get("pueblo", {})
	var ids: Array = []
	var only := _arg("--fiesta3d=")
	for id: String in defs:
		if lay.has(id) and (only == "" or id in only.split(",")):
			ids.append(id)
	for id: String in ids:
		await _one(id, defs[id])
	if "--fiesta3d-perf" in OS.get_cmdline_user_args():
		await _perf(defs)
	print("[SmokeFiesta3D] %s" % JSON.stringify(_res))
	print("[SmokeFiesta3D] %s (%d fails)" % ["ok" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## A new game on the festival's day, two hours in, the festival on the calendar.
func _start(id: String, d: Dictionary) -> String:
	var r := NewGame.from_start(Data.catalog, START, "normal", {"cast": "fixed"}, 1)
	var st: WorldState = r["state"]
	var dpy := 8
	var day := 2
	if str(d.get("kind", "")) == "fixed":
		day = int(d.get("day_of_year", 0))
		while day < 1:
			day += dpy
	var hour := mini(int(d.get("start_hour", 0)) + 2, 22)
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY + hour * 60
	(app.new_game_screen() as NewGameScreen).started.emit(st)
	await _wait(0.3)
	var inst := ""
	var f: Dictionary = Game.sim.state.festivals if Game.sim.state.festivals is Dictionary else {}
	for key: String in ["active", "upcoming"]:
		for i: Dictionary in f.get(key, []):
			if str(i.get("def", "")) == id:
				inst = str(i.get("id", ""))
	if inst == "":
		var extra := {}
		match str(d.get("trigger", {}).get("on", "")):
			"organized":
				extra = {"by": FestivalCourt.mayor(Game.sim)}
		inst = Festivals._schedule(Game.sim, id, day, "guion", extra)
	return inst


func _one(id: String, d: Dictionary) -> void:
	var inst := await _start(id, d)
	_check(inst != "", "%s on the sim's calendar (%s)" % [id, inst])
	var w3 := app.call("world3d") as WorldView3D
	# a game minute or two: the sim puts it in force, the town lays it out again (Town3D._check_festivals)
	await _until(func() -> bool: return _fp(w3) != null and _mounted(_fp(w3), id) > 0, 8.0)
	var fp := _fp(w3)
	var n := _mounted(fp, id) if fp != null else 0
	_check(n > 0, "%s dressed in the 3D town (%d pieces up)" % [id, n])
	_res[id] = {"instance": inst, "pieces_up": n}
	w3.town.target = Vector3(40.0, 1.2, 32.0)   # the plaza (smoke_abrir3d's view)
	w3.town.cam.size = 34.0
	w3.town.yaw = 225.0
	w3.town._update_camera()
	await _wait(1.5)
	await _shot("fiesta3d_%s" % id)


func _fp(w3: WorldView3D) -> Node3D:
	if w3 == null or w3.town == null or w3.town.vivo == null:
		return null
	var fp: Variant = w3.town.vivo.get("fiestas")
	return fp as Node3D if fp is Node3D and is_instance_valid(fp) else null


## The pieces up of festival `id` (its instances mounted, their placed pieces).
func _mounted(fp: Node3D, id: String) -> int:
	var n := 0
	for inst: Dictionary in fp.get("insts"):
		if str(inst.get("def", "")) == id and bool(inst.get("mounted", false)):
			n += (inst.get("placed", []) as Array).size()
	return n


func _until(cond: Callable, secs: float) -> void:
	var t := 0.0
	while t < secs and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()


func _perf(defs: Dictionary) -> void:
	await _start(PERF_ID, defs[PERF_ID])
	var w3 := app.call("world3d") as WorldView3D
	await _until(func() -> bool: return _fp(w3) != null and _mounted(_fp(w3), PERF_ID) > 0, 8.0)
	w3.town.target = Vector3(40.0, 1.2, 32.0)
	w3.town.cam.size = 30.0
	w3.town.yaw = 225.0
	w3.town._update_camera()
	await _wait(2.0)
	var frames: Array = []
	var t := 0.0
	while t < 8.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		frames.append(dt)
		t += dt
	var worst := 0.0
	for x: float in frames:
		worst = maxf(worst, x)
	frames.sort()
	var p99: float = frames[int(frames.size() * 0.99)] if not frames.is_empty() else 0.0
	var out := {"festival": PERF_ID, "rain": "--tiempo=lluvia" in OS.get_cmdline_user_args(),
		"window": [get_window().size.x, get_window().size.y], "frames": frames.size(),
		"fps": snappedf(float(frames.size()) / maxf(t, 0.001), 0.1), "worst_frame_ms": snappedf(worst * 1000.0, 0.1),
		"p99_ms": snappedf(p99 * 1000.0, 0.1), "pieces_up": _mounted(_fp(w3), PERF_ID),
		"people": w3.town.people.size()}
	_res["perf"] = out
	var dir := ProjectSettings.globalize_path("res://reports/perf")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("fiesta3d.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	await _shot("fiesta3d_perf_lluvia")
	print("[SmokeFiesta3D] perf %s" % JSON.stringify(out))


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://reports/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("[SmokeFiesta3D] shot %s.png" % name)
