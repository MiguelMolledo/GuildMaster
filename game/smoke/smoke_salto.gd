extends Node
## Measure of the jump when somebody starts walking (--smoke-script=salto; 3D by default, --view=2d for the 2D town;
## run it with the engine's --fixed-fps 60 so every frame is 1/60 s of real time; no window needed). A new game in
## Normal at 10:00: the protagonist gets move_to orders at several fractions of the game minute (0.1, 0.5, 0.9) at ×1,
## ×2 and ×4, and a new order half way along a walk; then the whole town is watched for a while at ×1 and ×4 (seats,
## work, the rain with --tiempo=lluvia). Per frame, the displacement of each drawn body in metres (2D: its position
## turned back into tiles, 1 tile = 2 m). A jump is a frame that moves more than JUMP_K times the walking step of that
## frame and more than JUMP_MIN metres, and less than TELEPORT (going in or out of a building is not one).
## Writes reports/perf/salto_<view>[_<tag>].json (--smoke-tag=<tag>) and prints the summary. --salto-clip=<dir>
## (with a window): instead, the camera close on the protagonist, an order half way through a minute at ×1, and every
## frame for 1.5 s saved to <dir>/NNN.png (half size) for a clip. Capture only: the
## protagonist is put out in the street if the game starts with him inside.

const JUMP_K: float = 2.5
const JUMP_MIN: float = 0.25
const TELEPORT: float = 3.5
const FRACS: Array = [0.1, 0.5, 0.9]
const SPEEDS: Array = [1, 2, 4]

var app: Node = null
var timeout: float = 400.0
var _total: float = 0.0
var _out: Dictionary = {"cases": [], "town": {}}
var _me: String = ""
var _last: Dictionary = {}     # chr -> last drawn position (metres, Vector3)
var _mpt: float = 2.0


func _ready() -> void:
	print("[SmokeSalto] start (view=%s)" % app.get("view_mode"))
	_run.call_deferred()


func _process(delta: float) -> void:
	_total += delta
	if _total > timeout:
		print("[SmokeSalto] TIMEOUT")
		get_tree().quit(1)


func _frame() -> void:
	await get_tree().process_frame


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var r := NewGame.from_start(Data.catalog, "artisan_blacksmith", "normal", {}, 1)
	var st: WorldState = r["state"]
	Game.set_time_of_day(st, 10 * 60)
	(app.new_game_screen() as NewGameScreen).started.emit(st)
	_mpt = float(Movement.minutes_per_tile(Game.sim.catalog))
	_me = str(Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["head"])
	for i: int in 40:
		await _frame()
	await _out_in_street()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--salto-clip="):
			await _clip(a.substr(13))
			get_tree().quit(0)
			return
	for sp: int in SPEEDS:
		for f: float in FRACS:
			await _case("quieto", sp, f, false)
		await _case("cambio_de_camino", sp, 0.5, true)
	await _watch_town(1, 20.0)
	await _watch_town(4, 12.0)
	_write()
	get_tree().quit(0)


## Where a body is drawn now, in metres on the ground (Vector3.INF if not drawn).
func _drawn(id: String) -> Vector3:
	var w3: Variant = app.call("world3d")
	if w3 != null:
		var town: Town3D = (w3 as WorldView3D).town
		if town == null or not town.people.has(id) or not (town.people[id].node as Node3D).visible:
			return Vector3.INF
		return (town.people[id].node as Node3D).position
	var v: CharacterView = (app.call("world") as WorldView).view_of(id)
	if v == null or not v.visible:
		return Vector3.INF
	var p := v.position   # Iso: world = ((c - r) * 32, (c + r) * 16)
	var c := (p.x / 32.0 + p.y / 16.0) / 2.0
	var rr := (p.y / 16.0 - p.x / 32.0) / 2.0
	return Vector3(c * 2.0, 0.0, rr * 2.0)


## Metres a walker covers in one frame at the speed now.
func _step_m() -> float:
	return 2.0 / _mpt * Game.steps_per_second() * get_process_delta_time()


func _out_in_street() -> void:
	var ch: Dictionary = Game.sim.state.characters[_me]
	if str(ch.get("location", "")) != "":
		Game.give({"type": "exit_building", "actor": _me})
		for i: int in 200:
			await _frame()
			if str(Game.sim.state.characters[_me].get("location", "")) == "":
				break
	for i: int in 30:
		await _frame()


## A walkable tile 3 to 5 tiles from `from`, the first in a fixed order that the sim can route to.
func _target(from: Vector2i, avoid_dir: Vector2i = Vector2i.ZERO) -> Vector2i:
	var grid := Grid.for_state(Game.sim.catalog, Game.sim.state)
	for d: Vector2i in [Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 0), Vector2i(0, -4), Vector2i(3, 3), Vector2i(-3, 3),
			Vector2i(3, -3), Vector2i(-3, -3), Vector2i(5, 1), Vector2i(1, 5), Vector2i(-5, -1)]:
		if avoid_dir != Vector2i.ZERO and d.sign() == avoid_dir.sign():
			continue
		var t := from + d
		if grid.in_bounds(t.x, t.y) and grid.walkable(t.x, t.y) and not Pathfinder.find(grid, from, t).is_empty():
			return t
	return from


func _pos() -> Vector2i:
	var p: Array = Game.sim.state.characters[_me]["position"]
	return Vector2i(int(p[0]), int(p[1]))


## Waits until the step fraction is at `f` (within the next 0.1), then gives the order.
func _order_at(f: float, tile: Vector2i) -> void:
	for i: int in 600:
		var fr := Game.step_fraction()
		if fr >= f and fr < f + 0.1:
			break
		await _frame()
	Game.give({"type": "move_to", "actor": _me, "tile": [tile.x, tile.y]})


func _case(kind: String, speed: int, f: float, repath: bool) -> void:
	Game.set_paused(false)
	Game.set_speed(speed)
	# standing still first
	for i: int in 400:
		await _frame()
		if (Game.sim.state.characters[_me].get("path", []) as Array).is_empty():
			break
	for i: int in 10:
		await _frame()
	var first := _target(_pos())
	if repath:
		await _order_at(0.2, first)
		for i: int in 200:   # walking, half way along the first tile of that path
			await _frame()
			var ch: Dictionary = Game.sim.state.characters[_me]
			if not (ch.get("path", []) as Array).is_empty() and int(ch.get("move_progress", 0)) >= 1:
				break
		var dir := first - _pos()
		await _order_at(f, _target(_pos(), dir))
	else:
		await _order_at(f, first)
	var worst := 0.0
	var worst_ratio := 0.0
	var jumps := 0
	var last := _drawn(_me)
	for i: int in 90:   # 1.5 s at 60 frames per second
		await _frame()
		var now := _drawn(_me)
		if now == Vector3.INF or last == Vector3.INF:
			last = now
			continue
		var d := Vector2(now.x - last.x, now.z - last.z).length()
		var step := maxf(_step_m(), 0.001)
		last = now
		if d >= TELEPORT:
			continue
		worst = maxf(worst, d)
		worst_ratio = maxf(worst_ratio, d / step)
		if d > maxf(JUMP_K * step, JUMP_MIN):
			jumps += 1
	var row := {"caso": kind, "velocidad": speed, "fraccion": f, "max_m": snappedf(worst, 0.001),
		"paso_m": snappedf(_step_m(), 0.001), "max_veces_paso": snappedf(worst_ratio, 0.01), "saltos": jumps}
	(_out["cases"] as Array).append(row)
	print("[SmokeSalto] %s" % JSON.stringify(row))


## Every drawn body for `secs` of real time at `speed`: the jumps by what they were doing.
func _watch_town(speed: int, secs: float) -> void:
	Game.set_speed(speed)
	_last.clear()
	var frames := int(secs * 60.0)
	var jumps: Dictionary = {}
	var worst := 0.0
	var n := 0
	for i: int in frames:
		await _frame()
		var step := maxf(_step_m(), 0.001)
		for id: String in Game.sim.state.characters:
			var now := _drawn(id)
			var was: Vector3 = _last.get(id, Vector3.INF)
			_last[id] = now
			if now == Vector3.INF or was == Vector3.INF:
				continue
			var d := Vector2(now.x - was.x, now.z - was.z).length()
			if d >= TELEPORT:
				continue
			n += 1
			worst = maxf(worst, d / step)
			if d > maxf(JUMP_K * step, JUMP_MIN):
				var doing := SimQuery.doing(Game.sim, id, int(Game.sim.state.clock["minute"]))
				jumps[doing] = int(jumps.get(doing, 0)) + 1
	var total := 0
	for k: Variant in jumps:
		total += int(jumps[k])
	var row := {"velocidad": speed, "segundos": secs, "muestras": n, "saltos": total, "por_lo_que_hace": jumps,
		"max_veces_paso": snappedf(worst, 0.01)}
	_out["town"]["x%d" % speed] = row
	print("[SmokeSalto] pueblo x%d: %s" % [speed, JSON.stringify(row)])


func _write() -> void:
	var tag := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-tag="):
			tag = "_" + a.substr(12)
	var view := str(app.get("view_mode"))
	var total := 0
	for c: Dictionary in _out["cases"]:
		total += int(c["saltos"])
	_out["view"] = view
	_out["saltos_protagonista"] = total
	var dir := ProjectSettings.globalize_path("res://reports/perf")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("salto_%s%s.json" % [view, tag])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(_out, "  "))
	f.close()
	print("[SmokeSalto] %s: %d saltos del protagonista en %d casos -> %s" % [view, total, (_out["cases"] as Array).size(), path])


func _clip(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Game.set_speed(1)
	var w3: Variant = app.call("world3d")
	var p0: Array = Game.sim.state.characters[_me]["position"]
	if w3 != null:
		var town: Town3D = (w3 as WorldView3D).town
		town.look_at_tile(Vector2(float(p0[0]) + 1.0, float(p0[1])))
		town.cam.size = 9.0
		town._update_camera()
	else:
		var cam: WorldCamera = (app.call("world") as WorldView).camera()
		cam.center_on(Iso.tile_to_world(Vector2i(int(p0[0]) + 1, int(p0[1]))))
	for i: int in 30:
		await _frame()
	var target := _target(_pos())
	var given := false
	for i: int in 90:
		if not given and i >= 15 and Game.step_fraction() >= 0.5:
			Game.give({"type": "move_to", "actor": _me, "tile": [target.x, target.y]})
			given = true
		await _frame()
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		img.save_png(dir.path_join("%03d.png" % i))
	print("[SmokeSalto] clip: 90 frames -> %s (order given: %s)" % [dir, given])
