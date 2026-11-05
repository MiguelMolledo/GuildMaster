extends Node
## Scripted captures of the playable towns (plantillas: «Dónde empiezas»; --smoke-script=plantillas, through
## `grimoire heavy` with the engine's --always-on-top). First the new game screen with Bellcaire chosen; then, for each
## settlement of the region (NewGame.cities), a real new game there (NewGame.from_start with choices.city, the
## generated cast of --seed, 1 by default) played from dawn, with a shot at each moment, to
## reports/shots/plantillas_<city>_<moment>.png:
##   mediodia  12:00, the market square (stalls, the board, the town hall, townsfolk shopping)
##   puerta    12:05, the first gate of the watch with its guard (and the visitors coming in)
##   paso      12:10, the bridge or the quay (where the map has one): the townsfolk crossing
##   atardecer the start of dusk + 50 min, the biggest corrillo (a rumour over a head)
##   noche     23:10, a night guard on its round with the lantern
## Prints per shot what is on the map (townsfolk out, walking, stuck, guards on duty, visitors, corrillos) and, at the
## end, the orders refused while playing. --smoke-cities=a,b: only those. Quits when done, or after `timeout` seconds
## with a shot of whatever is on screen.

const HERO: String = "chr_0001"
const START: String = "artisan_blacksmith"

var app: Node = null
var timeout: float = 420.0
var world_seed: int = 1
var _steps: Array = []
var _i: int = -1
var _t: float = 0.0
var _total: float = 0.0
var _armed: bool = false
var _refused: Dictionary = {}  # city -> [reason...]
var _city: String = ""


func _ready() -> void:
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
		elif a.begins_with("--seed="):
			world_seed = maxi(1, a.substr(7).to_int())
		elif a.begins_with("--smoke-cities="):
			only = a.substr(15).split(",", false)
	_steps = [["plantillas_partida_nueva", _new_game, 1.0]]
	for id: String in NewGame.cities(Data.catalog):
		if not only.is_empty() and not id in only:
			continue
		_steps.append(["plantillas_%s_mediodia" % id, _noon.bind(id), 1.2])
		_steps.append(["plantillas_%s_puerta" % id, _gate.bind(id), 1.0])
		if not _crossing(id).is_empty():
			_steps.append(["plantillas_%s_paso" % id, _cross.bind(id), 1.0])
		_steps.append(["plantillas_%s_atardecer" % id, _dusk.bind(id), 1.2])
		_steps.append(["plantillas_%s_noche" % id, _night.bind(id), 1.2])
	print("[SmokePlantillas] start (%d shots, seed %d, timeout=%.0f s)" % [_steps.size(), world_seed, timeout])


func _new_game() -> void:
	app.show_new_game()
	(app.new_game_screen() as NewGameScreen).set_city("capital")


## A new game in `id` (the first shot of each city); the later ones go on with it.
func _begin(id: String) -> bool:
	(app.new_game_screen() as NewGameScreen).close()
	var r := NewGame.from_start(Data.catalog, START, "normal", {} if id == NewGame.start_city(Data.catalog, START)
		else {"city": id}, world_seed)
	if not bool(r.get("ok", false)):
		print("[SmokePlantillas] %s: from_start failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	app.hud().close_panels()
	Game.start(r["state"])
	app.call("_enter_game")
	Game.set_paused(true)
	_city = id
	_refused[id] = []
	print("[SmokePlantillas] %s: partida nueva en %s (%d personajes, %d vecinos)" % [id, Game.sim.state.map_id,
		Game.sim.state.characters.size(), Population.townsfolk(Game.sim.state).size()])
	return true


## Plays up to `minute_of_day` of today, counting the refused orders.
func _run_to(minute_of_day: int) -> void:
	var st := Game.sim.state
	var target := Clock.day(int(st.clock["minute"])) * Clock.MINUTES_PER_DAY + minute_of_day
	while int(st.clock["minute"]) < target:
		for e: Dictionary in Game.sim.step():
			if str(e.get("type", "")) == "order_refused":
				(_refused[_city] as Array).append("%s %s: %s" % [e.get("order", ""), e.get("actor", ""), e.get("reason", "")])


func _phase_start(phase: String) -> int:
	var time: Dictionary = Data.catalog.time
	return int(time["phase_starts"][Clock.season(int(Game.sim.state.clock["minute"]), time)][phase])


func _centre(tile: Vector2i, zoom: int = 0) -> void:
	var cam: WorldCamera = app.world().camera()
	cam.zoom_index = clampi(zoom, 0, cam.zoom_levels.size() - 1)
	cam.center_on(Iso.tile_to_world(tile))


func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## What is on the map now: townsfolk out of doors, walking, stuck (a route not found, waiting to try again), guards on
## duty and where, visitors, corrillos.
func _report(label: String) -> void:
	var st := Game.sim.state
	var now := int(st.clock["minute"])
	var out := 0
	var walking := 0
	var stuck: Array = []
	for id: String in Population.townsfolk(st):
		var ch: Dictionary = st.characters[id]
		if str(ch.get("location", "")) != "":
			continue
		out += 1
		if not (ch.get("path", []) as Array).is_empty():
			walking += 1
		var t: Variant = ch.get("town")
		if t is Dictionary and int((t as Dictionary).get("retry_at", -1)) > now:
			stuck.append("%s@%s" % [id, ch.get("position", [])])
	var guards: Array = []
	for g: String in Watch.guards(st):
		if not Life.offstage(st, g):
			guards.append("%s@%s" % [st.characters[g]["guard"]["role"], Life.tile_of(st, g)])
	var groups := Rumors.corrillos(Game.sim)
	var sizes: Array = []
	for p: String in groups:
		sizes.append("%s=%d" % [p, (groups[p] as Array).size()])
	print("[SmokePlantillas] %s %s: vecinos fuera %d (andando %d, atascados %d %s), guardias %s, forasteros %d, corrillos %s" % [
		label, "%02d:%02d" % [Clock.minute_of_day(now) / 60, Clock.minute_of_day(now) % 60], out, walking,
		stuck.size(), stuck.slice(0, 4), guards, Visitors.alive(st).size(), sizes])


func _noon(id: String) -> void:
	if not _begin(id):
		return
	_run_to(12 * 60)
	app.world().select(HERO)
	_centre(_v(Life.plaza(Game.sim)), 0)
	_report("%s mediodía" % id)


func _gate(id: String) -> void:
	_run_to(12 * 60 + 5)
	app.world().select("")
	var gates := Life.gates(Game.sim)
	var first := ""
	for g: Variant in Life.cfg(Data.catalog).get("watch", {}).get("gates", []):
		if gates.has(str(g)):
			first = str(g)
			break
	var at := _v(Agenda._inside(Game.sim, gates.get(first, Life.plaza(Game.sim))))
	for g: String in Watch.guards(Game.sim.state):
		if str(Game.sim.state.characters[g]["guard"]["role"]) == "gate_" + first and not Life.offstage(Game.sim.state, g):
			at = _v(Life.tile_of(Game.sim.state, g))
			app.world().select(g)
	_centre(at, 1)
	_report("%s puerta %s" % [id, first])


## The bridge (a meeting point of kind bridge) or else a pier tile of the map ("m"), [] if neither.
func _crossing(id: String) -> Array:
	var m: Dictionary = Data.catalog.maps().get(str(NewGame.city(Data.catalog, id).get("map", "")), {})
	for p: Dictionary in m.get("social_points", []):
		if str(p.get("kind", "")) == "bridge" and not (p.get("slots", []) as Array).is_empty():
			return (p["slots"][0] as Array).duplicate()
	var rows: Array = m.get("rows", [])
	for r: int in rows.size():
		var c := str(rows[r]).find("m")
		if c >= 0:
			return [c, r]
	return []


func _cross(id: String) -> void:
	_run_to(12 * 60 + 10)
	app.world().select("")
	_centre(_v(_crossing(id)), 1)
	_report("%s paso %s" % [id, _crossing(id)])


func _dusk(id: String) -> void:
	_run_to(_phase_start("dusk") + 50)
	app.world().select("")
	var groups := Rumors.corrillos(Game.sim)
	var best := ""
	for p: String in groups:
		if best == "" or (groups[p] as Array).size() > (groups[best] as Array).size():
			best = p
	var at := _v(Life.plaza(Game.sim))
	if best != "":
		var who: Array = groups[best]
		at = _v(Life.tile_of(Game.sim.state, str(who[0])))
		app.world().select(str(who[0]))
	_centre(at, 1)
	_report("%s atardecer (corrillo %s)" % [id, best])


func _night(id: String) -> void:
	_run_to(23 * 60 + 10)
	var at := _v(Life.plaza(Game.sim))
	var found := ""
	for i: int in 120:
		for g: String in Watch.guards(Game.sim.state):
			if str(Game.sim.state.characters[g]["guard"]["role"]).begins_with("night") and not Life.offstage(Game.sim.state, g):
				found = g
				break
		if found != "":
			break
		Game.sim.step()
	if found != "":
		at = _v(Life.tile_of(Game.sim.state, found))
		app.world().select(found)
	_centre(at, 1)
	_report("%s noche (ronda %s)" % [id, found])
	print("[SmokePlantillas] %s: órdenes rechazadas %d %s" % [id, (_refused[id] as Array).size(),
		(_refused[id] as Array).slice(0, 5)])


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokePlantillas] TIMEOUT in step %d" % _i)
		app.save_shot("plantillas_timeout")
		get_tree().quit(1)
		return
	if _i >= _steps.size():
		return
	if _i < 0 or (_armed and _t > float(_steps[_i][2])):
		if _i >= 0:
			app.save_shot(str(_steps[_i][0]))
			print("[SmokePlantillas] shot %s" % _steps[_i][0])
		_i += 1
		_t = 0.0
		_armed = false
		if _i >= _steps.size():
			var total := 0
			for c: String in _refused:
				total += (_refused[c] as Array).size()
			print("[SmokePlantillas] done (órdenes rechazadas en total: %d)" % total)
			get_tree().quit(0)
			return
		(_steps[_i][1] as Callable).call()
		_armed = true
