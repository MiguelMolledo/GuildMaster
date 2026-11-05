extends Node
## Scripted capture of the Forja viva (docs/gdd/03b_diversion_y_ritmo.md §3b.2; --smoke-script=forja_viva
## --scenario=forge_live_ready --dev-time, through `grimoire heavy` and --always-on-top): Hugo goes into his forge, picks
## Forja viva at the anvil (fv_menu) and forges a sword by hand: the heat with the iron at cherry red (fv_calentar),
## two strikes of the template (fv_batir), the quench (fv_templar) and the result (fv_resultado). Then he forges
## hammers well, at ×4, until one comes out a masterwork with its name (fv_obra_maestra). The game pauses for each
## shot (the decision waits: a paused game applies no orders). It plays through the real UI paths (the screen's own
## buttons) and gives orders only through them. Quits when done, or after `timeout` seconds with a shot.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var app: Node = null
var timeout: float = 170.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _pieces: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeForjaViva] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeForjaViva] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _screen() -> LiveForgeScreen:
	return app.interior().live_screen()


func _view() -> Dictionary:
	return LiveForge.view(Game.sim, BLD, "anvil")


func _rdef() -> Dictionary:
	return LiveForge.recipe_def(Game.sim, _screen().recipe)


## Pauses, waits a moment for the frame, takes the shot, resumes.
func _shot(name: String) -> void:
	app.save_shot(name)
	Game.set_paused(false)


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeForjaViva] TIMEOUT in step %s (pieces=%d)" % [_step, _pieces])
		app.save_shot("fv_timeout")
		get_tree().quit(1)
		return
	var hugo: Dictionary = Game.sim.state.characters[HUGO]
	match _step:
		"start":
			if _t > 0.4:
				app.world().select(HUGO)
				app.world().command_enter(BLD)
				_go("entering")
		"entering":
			if str(hugo["location"]) == BLD and app.interior_building == BLD and _t > 0.6:
				app.interior().open_station_menu("anvil", app.interior().station_screen("anvil"))
				app.interior().station_menu().choose_mode(app.interior().station_menu().third_mode())
				_go("menu")
		"menu":
			if _t > 0.5:
				app.save_shot("fv_menu")
				app.interior().station_menu().choose_recipe("forge_sword")
				_go("heat")
		"heat":
			var cherry := (Game.sim.catalog.live_forge["heat_colors"] as Array).find(str(_rdef().get("heat", "cherry")))
			if _screen().visible and _screen().heat_index >= cherry and _t > 0.3:
				Game.set_paused(true)
				_go("heat_shot")
		"heat_shot":
			if _t > 0.35:
				_shot("fv_calentar")
				_screen().pull()
				_go("strikes")
		"strikes":
			var v := _view()
			if str(v.get("stage", "")) == "strike" and _t > 0.15:
				var done := (v["strikes"] as Array).size()
				if done == 2:
					Game.set_paused(true)
					_go("strike_shot")
					return
				_screen().strike(str(LiveForge.template_of(Game.sim, _rdef(), _part())[done]))
				_t = 0.0
		"strike_shot":
			if _t > 0.35:
				_shot("fv_batir")
				_go("strikes_rest")
		"strikes_rest":
			var v := _view()
			if str(v.get("stage", "")) == "strike" and _t > 0.15:
				_screen().strike(str(LiveForge.template_of(Game.sim, _rdef(), _part())[(v["strikes"] as Array).size()]))
				_t = 0.0
			elif str(v.get("stage", "")) == "quench":
				Game.set_paused(true)
				_go("quench_shot")
		"quench_shot":
			if _t > 0.35:
				_shot("fv_templar")
				_screen().quench(LiveForge.wanted_quench(_rdef(), _part()))
				_go("result")
		"result":
			if not _screen().result.is_empty() and _t > 0.2:
				Game.set_paused(true)
				_go("result_shot")
		"result_shot":
			if _t > 0.35:
				_shot("fv_resultado")
				_pieces += 1
				if (_screen().get_node("%Masterwork") as PageCard).visible:
					_go("masterwork")
				else:
					_screen().close()
					Game.set_speed(4)
					_go("hunt")
		"hunt":   # well-forged pieces until a masterwork comes out (the screen opens again on each live cycle)
			if (_screen().get_node("%Masterwork") as PageCard).visible:
				Game.set_paused(true)
				_go("masterwork")
				return
			if _screen().visible and not _screen().result.is_empty():
				_screen().close()   # «Seguir»: on to the next piece, again by hand
				return
			var v := _view()
			if v.is_empty() or not _screen().visible:
				return
			_play_well(v)
			Game.set_speed(4)
		"masterwork":
			if _t > 0.6:
				app.save_shot("fv_obra_maestra")
				Game.set_paused(false)
				print("[SmokeForjaViva] done: %d pieces, masterworks=%d" % [_pieces,
					LiveForge.masterworks_of(Game.sim.state, "").size()])
				_go("done")
				get_tree().quit()


func _part() -> Dictionary:
	var job: Variant = Game.sim.state.buildings[BLD]["zones"]["anvil"].get("job")
	return (job as Dictionary).get("live", {}) if job is Dictionary else {}


func _play_well(v: Dictionary) -> void:
	var s := _screen()
	if not s.result.is_empty():
		return
	match str(v.get("stage", "")):
		"heat":
			s.heat_index = (Game.sim.catalog.live_forge["heat_colors"] as Array).find(str(_rdef()["heat"]))
			s.pull()
			_pieces += 1
		"strike":
			s.strike(str(LiveForge.template_of(Game.sim, _rdef(), _part())[(v["strikes"] as Array).size()]))
		"quench":
			s.quench(LiveForge.wanted_quench(_rdef(), _part()))
