extends Node
## Scripted capture of H5 (--smoke-script=mejoras; run it through `grimoire heavy` with --dev-time and the engine's
## --always-on-top). Scenario forge_upgrade_works: the forge on the map with the scaffold and the works bar
## (h5_obra_mapa); its interior in management mode with the tree panel and the works in progress (h5_obra_panel);
## when the works end, the tree with the stone facade selected (h5_arbol), bought from the panel; the interior with
## the upgrade visuals and the new works under the title (h5_interior); when the facade is done, the forge on the map
## with its facade (h5_fachada). Orders only through the UI paths. Quits when done, or after `timeout` seconds with a
## shot of whatever is on screen.

const BLD := "bld_0001"

var app: Node = null
var timeout: float = 150.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeMejoras] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeMejoras] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _centre_on_forge() -> void:
	var b: Dictionary = Game.sim.state.buildings[BLD]
	var o: Array = b.get("origin", [0, 0])
	var f: Array = b.get("footprint", [1, 1])
	var c := Vector2(float(o[0]) + (float(f[0]) - 1.0) / 2.0, float(o[1]) + (float(f[1]) - 1.0) / 2.0)
	app.world().camera().center_on(Iso.tilef_to_world(c) + Vector2(0, -24))


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeMejoras] TIMEOUT in step %s" % _step)
		app.save_shot("h5_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_scenario("forge_upgrade_works")
				if not bool(r.get("ok", false)):
					print("[SmokeMejoras] scenario failed: %s" % r.get("error", ""))
					get_tree().quit(1)
					return
				Game.start(r["state"])
				Game.set_paused(true)
				_go("map")
		"map":
			if _t > 0.2:
				_centre_on_forge()
				app.world().refresh_upgrades()
				_go("shot_map")
		"shot_map":
			if _t > 0.5:
				app.save_shot("h5_obra_mapa")
				app.open_interior(BLD, true)
				_go("inside")
		"inside":
			if app.interior_building == BLD and _t > 0.8:
				app.interior().show_upgrades(true)
				_go("shot_works_panel")
		"shot_works_panel":
			if _t > 0.5:
				app.save_shot("h5_obra_panel")
				Game.set_paused(false)
				Game.set_speed(4)
				_go("wait_works")
		"wait_works":
			if Upgrades.has(Game.sim.state, BLD, "forge_capacity_2") and _t > 0.3:
				Game.set_paused(true)
				app.interior().upgrade_panel().select("forge_facade_1")
				_go("shot_tree")
		"shot_tree":
			if _t > 0.5:
				app.save_shot("h5_arbol")
				app.interior().upgrade_panel().buy("forge_facade_1")   # the same call the Buy button makes
				Game.set_speed(1)
				Game.set_paused(false)   # the order given in the pause goes in with the next step
				_go("bought")
		"bought":
			if Upgrades.under_works(Game.sim.state, BLD):
				Game.set_paused(true)
				app.interior().show_upgrades(false)
				_go("shot_interior")
		"shot_interior":
			if _t > 0.5:
				app.save_shot("h5_interior")
				Game.set_speed(4)
				Game.set_paused(false)
				_go("wait_facade")
		"wait_facade":
			if Upgrades.has(Game.sim.state, BLD, "forge_facade_1"):
				Game.set_paused(true)
				app.close_interior()
				_go("facade")
		"facade":
			if app.interior_building == "" and _t > 0.6:
				_centre_on_forge()
				app.world().refresh_upgrades()
				_go("shot_facade")
		"shot_facade":
			if _t > 0.5:
				app.save_shot("h5_fachada")
				_go("done")
				get_tree().quit()
