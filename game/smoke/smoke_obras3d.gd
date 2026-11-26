extends Node
## Upgrades that change a house's level in the 3D town while the game runs (--smoke-script=obras3d; with a window,
## through `grimoire heavy`, it also saves reports/shots/obras3d_<stage>.png). A new game as the blacksmith at 10:00;
## the forge's state is edited by hand (capture and check only, as the oficios scripts do): two finished upgrades and a
## third one under works (its house goes up a level in frame), then the third finished (the new level built). Each
## stage waits for the town to rebuild that house (Town3D.rebuilds, the house's look_key and level). Then works of a
## building on a free plot (construction) and its end: the town drawn again (App's H6 rebuild). Prints
## "[SmokeObras3D] ok|FAIL ..."; quits 1 on a FAIL or a timeout.

const START: String = "artisan_blacksmith"

var app: Node = null
var timeout: float = 90.0
var _total: float = 0.0
var _fails: int = 0
var _forge: String = ""


func _ready() -> void:
	print("[SmokeObras3D] start")
	_run.call_deferred()


func _process(delta: float) -> void:
	_total += delta
	if _total > timeout:
		print("[SmokeObras3D] TIMEOUT")
		get_tree().quit(1)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(cond: bool, what: String) -> void:
	print("[SmokeObras3D] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _w3() -> WorldView3D:
	return app.call("world3d") as WorldView3D


func _house() -> Node3D:
	var w3 := _w3()
	return w3.town.bld_anchor[_forge].house if w3 != null and w3.town != null and w3.town.bld_anchor.has(_forge) else null


func _run() -> void:
	await _wait(0.5)
	var r := NewGame.from_start(Data.catalog, START, "normal", {"cast": "fixed"}, 1)
	var st: WorldState = r["state"]
	Game.set_time_of_day(st, 10 * 60)
	(app.new_game_screen() as NewGameScreen).started.emit(st)
	await _wait(2.0)
	_forge = WorldView3D._workshop(Game.sim.state)
	var h := _house()
	_check(h != null, "the forge has its house in the 3D town (%s)" % _forge)
	if h == null:
		_end()
		return
	var w3 := _w3()
	w3.town.target = Vector3(h.global_position.x, 1.2, h.global_position.z)
	w3.town.cam.size = 16.0
	w3.town._update_camera()
	await _wait(1.0)
	await _shot("antes")
	var lv0 := int(h.get_meta("level", 0))
	var key0 := str(h.get_meta("look_key", ""))
	print("[SmokeObras3D] forge house %s level %d look %s" % [h.name, lv0, key0])
	var tree := _tree_ids()
	var b: Dictionary = Game.sim.state.buildings[_forge]
	# two finished, the third under works: the level of the next look in frame
	b["upgrades"] = tree.slice(0, 2)
	var now := int(Game.sim.state.clock["minute"])
	b["upgrade_work"] = {"upgrade": str(tree[2]), "start": now, "end": now + 600}
	var n0: int = w3.town.rebuilds.size()
	await _until(func() -> bool: return w3.town.rebuilds.size() > n0, 6.0)
	h = _house()
	_check(w3.town.rebuilds.size() > n0 and str(h.get_meta("stage", "")) == "frame",
		"works to a new level: the house built again in frame (%s, stage %s, level %d)" % [h.name, h.get_meta("stage", ""), int(h.get_meta("level", 0))])
	await _wait(1.0)
	await _shot("obra")
	# the works end: three upgrades, the new level
	b["upgrades"] = tree.slice(0, 3)
	b.erase("upgrade_work")
	var n1: int = w3.town.rebuilds.size()
	await _until(func() -> bool: return w3.town.rebuilds.size() > n1, 6.0)
	h = _house()
	_check(int(h.get_meta("level", 0)) == mini(lv0 + 1, 3) and str(h.get_meta("stage", "")) in ["", "done"],
		"works done: the house at its new level (%d -> %d)" % [lv0, int(h.get_meta("level", 0))])
	print("[SmokeObras3D] rebuilds %s" % JSON.stringify(w3.town.rebuilds))
	await _wait(1.0)
	await _shot("nivel")
	_end()


func _tree_ids() -> Array:
	var ids: Array = []
	for id: String in Game.sim.catalog.upgrades().keys():
		if id.begins_with("forge_production_") or id.begins_with("forge_quality_") or id.begins_with("forge_capacity_"):
			ids.append(id)
	ids.sort()
	return ids


func _until(cond: Callable, secs: float) -> void:
	var t := 0.0
	while t < secs and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://reports/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join("obras3d_%s.png" % stage))
	print("[SmokeObras3D] shot obras3d_%s.png" % stage)


func _end() -> void:
	print("[SmokeObras3D] %s (%d fails)" % ["ok" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
