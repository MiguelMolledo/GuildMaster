extends Node
## Scripted capture of H8 (--smoke-script=familia; run it through `grimoire heavy` with the engine's --always-on-top).
## founder_old: the family tree (key F) with the son picked: the family by its colours, the children with the hair or
## the skin of a parent, the heir's crown, the group in the HUD (h8_arbol). family_routines: the son selected, his sheet
## with the routine editor and the group of three in the HUD (h8_rutina). founder_no_heir: the clock runs into the new
## year, the old founder dies without heir and the ending screen shows the dynasty score (h8_game_over). Quits when
## done, or after `timeout` seconds with a shot of whatever is on screen.

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeFamilia] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeFamilia] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _load(id: String) -> bool:
	var r := NewGame.from_scenario(id)
	if not bool(r.get("ok", false)):
		print("[SmokeFamilia] scenario %s failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	Game.start(r["state"])
	Game.set_paused(true)
	return true


func _centre_on(chr: String) -> void:
	var st := Game.sim.state
	var ch: Dictionary = st.characters[chr]
	var loc := str(ch.get("location", ""))
	var p: Array = st.buildings[loc]["door"] if loc != "" else ch["position"]
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(p[0]), int(p[1]))))


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeFamilia] TIMEOUT in step %s" % _step)
		app.save_shot("h8_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3 and _load("founder_old"):
				_go("tree")
		"tree":
			if _t > 0.3:
				app.world().select("chr_0001")
				_centre_on("chr_0001")
				app.hud().toggle_tree()
				var son := str(Game.sim.state.characters["chr_0001"]["children"][0])
				app.hud().tree_panel().pick(son)
				_go("shot_tree")
		"shot_tree":
			if _t > 0.6:
				app.save_shot("h8_arbol")
				app.hud().close_panels()
				if _load("family_routines"):
					_go("routine")
		"routine":
			if _t > 0.3:
				var son := str(Kin.group(Game.sim.state, "fam_0001")[1])
				app.world().select(son)
				_centre_on(son)
				app.hud().toggle_character_panel()
				_go("shot_routine")
		"shot_routine":
			if _t > 0.6:
				app.save_shot("h8_rutina")
				app.hud().close_panels()
				if _load("founder_no_heir"):
					Game.set_paused(false)
					Game.set_speed(4)
					_go("wait_end")
		"wait_end":
			if app.ending_screen().visible and _t > 0.5:
				_go("shot_end")
		"shot_end":
			if _t > 0.5:
				app.save_shot("h8_game_over")
				_go("done")
				get_tree().quit(0)
