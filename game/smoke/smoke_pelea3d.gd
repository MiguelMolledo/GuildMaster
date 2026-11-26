extends Node
## The fight of the plaza in the 3D town (M3D-5; --smoke-script=pelea3d; with a window through `grimoire heavy` it
## saves reports/shots/pelea3d.png). The scenario life_altercation (day 9, 19:55: two neighbours come to blows in the
## plaza at 20:00) at ×2 until the sim has two people brawling; then their bodies are checked: each one plays a blow
## (Punch_*, Hit_*) and faces the other (within 35°). Prints "[SmokePelea3D] ok|FAIL ..."; quits 1 on a FAIL or a
## timeout.

var app: Node = null
var timeout: float = 90.0
var _total: float = 0.0
var _fails: int = 0


func _ready() -> void:
	print("[SmokePelea3D] start")
	_run.call_deferred()


func _process(delta: float) -> void:
	_total += delta
	if _total > timeout:
		print("[SmokePelea3D] TIMEOUT")
		get_tree().quit(1)


func _check(cond: bool, what: String) -> void:
	print("[SmokePelea3D] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var r := NewGame.from_scenario("life_altercation", 1)
	Game.start(r["state"], Game.sim.catalog if Game.sim != null else Data.catalog)
	app.call("_enter_game")
	app.hud().close_panels()
	var w3 := app.call("world3d") as WorldView3D
	await get_tree().create_timer(1.5).timeout
	w3.town.target = Vector3(40.0, 1.2, 38.0)   # the plaza
	w3.town.cam.size = 14.0
	w3.town.yaw = 225.0
	w3.town._update_camera()
	Game.set_speed(1)
	# every frame while the sim has two of them brawling and standing: do their bodies show it?
	var seen := 0
	var good := 0
	var shot := false
	var last := ""
	var t := 0.0
	while t < 60.0 and good < 20:
		await get_tree().process_frame
		t += get_process_delta_time()
		var fighters: Array = []
		for id: String in w3.town.people:
			if str(w3.town.people[id].doing) == "brawl" and (w3.town.people[id].node as Node3D).visible \
					and w3.town.motion_at(w3.town.people[id], w3.town.t_min) == Vector2.ZERO:
				fighters.append(id)
		if fighters.size() < 2:
			continue
		seen += 1
		var ok := true
		var line := ""
		for k: int in 2:
			var me: Node3D = w3.town.people[fighters[k]].node
			var other: Node3D = w3.town.people[fighters[1 - k]].node
			var anim := str(w3.town._chr[fighters[k]].anim)
			var want := atan2(other.position.x - me.position.x, other.position.z - me.position.z)
			var off := absf(rad_to_deg(angle_difference(me.rotation.y, want)))
			ok = ok and (anim.begins_with("Punch") or anim.begins_with("Hit")) and off < 35.0
			line += "%s %s %.0f° " % [fighters[k], anim, off]
		last = line
		if ok:
			good += 1
			if not shot and DisplayServer.get_name() != "headless":
				shot = true
				Game.set_paused(true)
				var a: Node3D = w3.town.people[fighters[0]].node
				w3.town.target = Vector3(a.position.x, 1.2, a.position.z)
				w3.town.cam.size = 9.0
				w3.town._update_camera()
				await get_tree().create_timer(0.4).timeout
				await RenderingServer.frame_post_draw
				var dir := ProjectSettings.globalize_path("res://reports/shots")
				DirAccess.make_dir_recursive_absolute(dir)
				get_viewport().get_texture().get_image().save_png(dir.path_join("pelea3d.png"))
				Game.set_paused(false)
	print("[SmokePelea3D] frames with two brawling: %d, showing it (blows, facing): %d; last: %s" % [seen, good, last])
	_check(seen > 0, "the sim has two people brawling in the plaza")
	_check(good >= 1, "their bodies trade blows facing each other")
	print("[SmokePelea3D] %s (%d fails)" % ["ok" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
