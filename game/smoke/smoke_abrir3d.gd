extends Node
## The opening of a house in the 3D town, as the player sees it (--smoke-script=abrir3d; through `grimoire heavy`, with
## the engine's --always-on-top and, for a clip, --write-movie <file>.avi --fixed-fps 30): a new game in Normal at
## 11:00, the camera over the plaza (size 30, yaw 225, the same as Prueba3D's clip), then the player's forge opened by
## «Gestionar» (App.open_interior(..., true)), closed four seconds later, and the town for three more. Without
## --write-movie it measures the frames while the house opens and closes (fps, worst frame) ->
## reports/perf/abrir3d.json. --abrir3d-via=enter: the protagonist walks in instead (enter_building). Then the camera
## zooms in over the house next door (it opens to look inside: no panels) and out again (it closes).

const START: String = "artisan_blacksmith"

var app: Node = null
var timeout: float = 120.0
var _t: float = 0.0
var _stage: int = 0
var _forge: String = ""
var _frames: Array = []     # [stage, delta] while measuring
var _perf: Dictionary = {}
var _pc_last: int = 0


## Render pipelines compiled so far (every kind): a frame that compiles many waits for them.
func _pipelines() -> int:
	var n := 0
	for k: int in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += RenderingServer.get_rendering_info(k)
	return n


func _ready() -> void:
	print("[SmokeAbrir3D] start")


func _process(delta: float) -> void:
	_t += delta
	if _t > timeout:
		print("[SmokeAbrir3D] TIMEOUT at stage %d" % _stage)
		get_tree().quit(1)
		return
	var w3 := app.call("world3d") as WorldView3D
	if _stage in [2, 3]:
		var pc := _pipelines()
		_frames.append([_stage, delta, pc - _pc_last])   # + pipelines compiled in that frame
		_pc_last = pc
	match _stage:
		0:
			if _t > 0.5:
				var r := NewGame.from_start(Data.catalog, START, "normal", {}, 1)
				var st: WorldState = r["state"]
				Game.set_time_of_day(st, 11 * 60)
				(app.new_game_screen() as NewGameScreen).started.emit(st)
				_forge = WorldView3D._workshop(Game.sim.state)
				_stage = 1
				_t = 0.0
		1:
			if _t > 0.2 and w3 != null and w3.town != null and _stage == 1 and _t < 0.4:
				w3.town.target = Vector3(40.0, 1.2, 32.0)
				w3.town.cam.size = 30.0
				w3.town.yaw = 225.0
				w3.town._update_camera()
			if _t > 3.0:
				var via := "manage"
				for a: String in OS.get_cmdline_user_args():
					if a.begins_with("--abrir3d-via="):
						via = a.substr(14)
				print("[SmokeAbrir3D] open %s (%s) at %.1f s" % [_forge, via, _t])
				if via == "enter":
					var me := str(Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["head"])
					Game.give({"type": "enter_building", "actor": me, "building": _forge})
				else:
					app.call("open_interior", _forge, true)
				_stage = 2
				_t = 0.0
		2:
			if _t > 4.0:
				print("[SmokeAbrir3D] close at %.1f s (interior=%s)" % [_t, app.get("interior_building")])
				app.call("close_interior")
				_stage = 3
				_t = 0.0
		3:
			if _t > 3.0:
				# looking inside by zooming in over another house (as Prueba3D): no panels, no orders
				var h := _look_house(w3)
				if h != null:
					w3.town.target = Vector3(h.global_position.x, 1.2, h.global_position.z)
					w3.town._zoom_goal = 9.0
					w3.town._update_camera()
					print("[SmokeAbrir3D] zoom in over %s" % h.name)
				_stage = 4
				_t = 0.0
		4:
			if _t > 3.0:
				_perf["mirar"] = {"looking": w3.town.looking, "interior_panels": str(app.get("interior_building")) != ""}
				print("[SmokeAbrir3D] looking=%s panels=%s" % [w3.town.looking, app.get("interior_building")])
				w3.town._zoom_goal = 26.0
				_stage = 5
				_t = 0.0
		5:
			if _t > 2.5:
				_perf["mirar"]["closed_by_zooming_out"] = not w3.town.inside
				_write()
				get_tree().quit(0)


func _write() -> void:
	var seq: Array = []   # the abrir frames in order: where the worst ones fall (the frame of the order, the cut...)
	var comp: Array = []
	for f: Array in _frames:
		if int(f[0]) == 2:
			seq.append(snappedf(float(f[1]) * 1000.0, 0.1))
			comp.append(int(f[2]))
	var idx: Array = range(seq.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return float(seq[a]) > float(seq[b]))
	print("[SmokeAbrir3D] abrir: worst frames [index, ms, pipelines compiled] %s (of %d; %d pipelines in all)" % [
		idx.slice(0, 5).map(func(i: int) -> Array: return [i, seq[i], comp.slice(maxi(0, i - 2), i + 3)]), seq.size(),
		comp.reduce(func(a, b): return a + b, 0)])
	var where: Array = []
	for i: int in comp.size():
		if int(comp[i]) > 0:
			where.append([i, comp[i], seq[i]])
	print("[SmokeAbrir3D] abrir: frames that compiled [index, pipelines, ms] %s" % [where.slice(0, 12)])
	_perf["pipelines_abrir"] = comp.reduce(func(a, b): return a + b, 0)
	for st: int in [2, 3]:
		var n := 0
		var sum := 0.0
		var worst := 0.0
		for f: Array in _frames:
			if int(f[0]) == st:
				n += 1
				sum += float(f[1])
				worst = maxf(worst, float(f[1]))
		_perf["abrir" if st == 2 else "cerrar"] = {"frames": n, "fps": snappedf(float(n) / maxf(sum, 0.001), 0.1),
			"worst_frame_ms": snappedf(worst * 1000.0, 0.1)}
	var dir := ProjectSettings.globalize_path("res://reports/perf")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("abrir3d.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_perf, "  "))
	f.close()
	print("[SmokeAbrir3D] %s" % JSON.stringify(_perf))


## A house with an interior in place near the forge that is not the forge (the house next door to look into).
func _look_house(w3: WorldView3D) -> Node3D:
	var forge: Node3D = w3.town.bld_anchor[_forge].house if w3.town.bld_anchor.has(_forge) else null
	var best: Node3D = null
	var bd := 1e9
	for h: Node3D in w3.town.houses:
		if h == forge or not h.has_meta("interior"):
			continue
		var d := h.global_position.distance_to(forge.global_position) if forge != null else 0.0
		if d < bd:
			bd = d
			best = h
	return best
