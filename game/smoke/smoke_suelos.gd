extends Node
## Scripted capture of the town's ground and facades (--smoke-script=suelos; run it through `grimoire heavy` with the
## engine's --always-on-top): the same camera before and after an art pass. Scenario town_e_start (the slice) and
## region_capital_start (the dense capital), paused, the HUD hidden; for each place a shot at noon and at dusk
## (reports/shots/suelos_<place>_<dia|tarde>.png). The clock is set directly (capture only). Quits when done, or
## after `timeout` seconds.

const NOON: int = 720
const DUSK: int = 1230  # spring dusk starts at 1140; +90 = past the 60-minute blend
# [name, scenario, tile, zoom index]
const PLACES: Array = [
	["general", "town_e_start", Vector2i(19, 19), 0],
	["plaza", "town_e_start", Vector2i(19, 18), 1],
	["calle", "town_e_start", Vector2i(10, 18), 1],
	["rio", "town_e_start", Vector2i(34, 19), 1],
	["campos", "town_e_start", Vector2i(9, 31), 1],
	["capital", "region_capital_start", Vector2i(37, 36), 0],
	["capital_plaza", "region_capital_start", Vector2i(36, 34), 1],
	["capital_puente", "region_capital_start", Vector2i(55, 64), 1],
]

var app: Node = null
var timeout: float = 90.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1
var _dusk: bool = false
var _scenario: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeSuelos] start (%d places x2)" % PLACES.size())


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeSuelos] TIMEOUT at place %d" % _i)
		get_tree().quit(1)
		return
	if _i == -1:
		if _t > 0.5:
			_next()
		return
	if _t > 0.8:
		var p: Array = PLACES[_i]
		app.save_shot("suelos_%s_%s" % [p[0], "tarde" if _dusk else "dia"])
		if not _dusk:
			_dusk = true
			_set_minute(DUSK)
			_t = 0.0
			return
		_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	_dusk = false
	if _i >= PLACES.size():
		print("[SmokeSuelos] done")
		get_tree().quit(0)
		return
	var p: Array = PLACES[_i]
	if str(p[1]) != _scenario:
		_scenario = str(p[1])
		var r := NewGame.from_scenario(_scenario)
		if not bool(r.get("ok", false)):
			print("[SmokeSuelos] scenario %s failed: %s" % [_scenario, r.get("error", "")])
			get_tree().quit(1)
			return
		Game.start(r["state"])
		Game.set_paused(true)
	_set_minute(NOON)
	app.hud().visible = false
	var cam: WorldCamera = app.world().camera()
	cam.zoom_index = clampi(int(p[3]), 0, cam.zoom_levels.size() - 1)
	cam.center_on(Iso.tile_to_world(p[2]))
	print("[SmokeSuelos] camera on %s %s zoom x%d" % [p[0], p[2], cam.current_zoom()])


## Sets the minute of the current day (capture only: the sim does not run).
func _set_minute(m: int) -> void:
	var clock: Dictionary = Game.sim.state.clock
	var day := int(clock["minute"]) / Clock.MINUTES_PER_DAY
	clock["minute"] = day * Clock.MINUTES_PER_DAY + m
