extends Node
## Scripted capture of a whole town (--smoke-script=mapa; run it through `grimoire heavy` with the engine's
## --always-on-top): for each scenario of --smoke-maps=<id,id...> (default town_e_start), paused at 10:00 of its day
## (capture only, in daylight), the
## camera on the plaza, the centre and the four quarters of the map, and a shot of each
## (reports/shots/mapa_<map id>_<place>.png; mapa_<scenario>_<place>.png when the scenario is not <map id>_start). Made to check the town builder's dressing (tools/city/,
## docs/protocolos/generar-ciudad.md): houses facing the street, lanterns, props, fences. Quits when done, or after
## `timeout` seconds.

var app: Node = null
var timeout: float = 120.0
var _t: float = 0.0
var _total: float = 0.0
var _scenarios: PackedStringArray = ["town_e_start"]
var _s: int = -1
var _places: Array = []
var _i: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-maps="):
			_scenarios = a.substr(13).split(",", false)
	print("[SmokeMapa] start (%s)" % [_scenarios])


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeMapa] TIMEOUT at scenario %d place %d" % [_s, _i])
		get_tree().quit(1)
		return
	if _s == -1:
		if _t > 0.5:
			_next_scenario()
		return
	if _t > 0.8:
		app.save_shot("mapa_%s_%s" % [_shot_name(), _places[_i][0]])
		_i += 1
		_t = 0.0
		if _i >= _places.size():
			_next_scenario()
		else:
			_look()


func _next_scenario() -> void:
	_s += 1
	_t = 0.0
	if _s >= _scenarios.size():
		print("[SmokeMapa] done")
		get_tree().quit(0)
		return
	var r := NewGame.from_scenario(_scenarios[_s])
	if not r["ok"]:
		print("[SmokeMapa] scenario %s: %s" % [_scenarios[_s], r["error"]])
		get_tree().quit(1)
		return
	var st: WorldState = r["state"]
	var minute := int(st.clock["minute"])
	st.clock["minute"] = minute - minute % Clock.MINUTES_PER_DAY + 600  # capture only: 10:00 of its day, in daylight
	Game.start(st)
	Game.set_paused(true)
	var rows: Array = Game.sim.catalog.maps().get(Game.sim.state.map_id, {}).get("rows", [])
	var h := rows.size()
	var w := str(rows[0]).length() if h > 0 else 0
	var plaza := Vector2.ZERO
	var n := 0
	for r_: int in h:
		for c_: int in w:
			if str(rows[r_])[c_] == "P":
				plaza += Vector2(c_, r_)
				n += 1
	if n > 0:
		plaza /= float(n)
	else:
		plaza = Vector2(w / 2.0, h / 2.0)
	_places = [["plaza", Vector2i(roundi(plaza.x), roundi(plaza.y))], ["centro", Vector2i(w / 2, h / 2)],
		["no", Vector2i(w / 4, h / 4)], ["ne", Vector2i(3 * w / 4, h / 4)], ["so", Vector2i(w / 4, 3 * h / 4)],
		["se", Vector2i(3 * w / 4, 3 * h / 4)]]
	_i = 0
	_look()


func _look() -> void:
	print("[SmokeMapa] %s: camera on %s %s" % [Game.sim.state.map_id, _places[_i][0], _places[_i][1]])
	app.world().camera().center_on(Iso.tile_to_world(_places[_i][1]))


## The shot's name: the map's id for its <map>_start scenario (mapa_town_e_plaza), else the scenario's id.
func _shot_name() -> String:
	var sc := str(_scenarios[_s])
	return Game.sim.state.map_id if sc == Game.sim.state.map_id + "_start" else sc
