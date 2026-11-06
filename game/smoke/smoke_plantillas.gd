extends Node
## Scripted captures of the playable towns (plantillas: «Dónde empiezas»; --smoke-script=plantillas, through
## `grimoire heavy` with the engine's --always-on-top). First the new game screen with Bellcaire chosen; then, for each
## settlement of the region (NewGame.cities), a real new game there (NewGame.from_start with choices.city, the
## generated cast of --seed, 1 by default) played from dawn, with a shot at each moment, to
## reports/shots/plantillas_<city>_<moment>.png:
##   mediodia  12:00, the market square (stalls, the board, the town hall, townsfolk shopping)
##   puerta    12:05, the first gate of the watch with its guard (and the visitors coming in)
##   paso      12:10, the bridge or the quay (where the map has one): the townsfolk crossing
##   ruina, solar, fuera, venta  12:12-12:18, the plots (04 §4.9.1, data/maps plots): the best-located ruin, a free
##             lot inside the town, a free lot outside it, the business with the «Se vende» sign
##   zona_<kind> from 12:20, in a town with zones (H13, Bellcaire: data/maps zones): each zone at the farthest zoom,
##             with its name (ZoneLayer)
##   atardecer the start of dusk + 50 min, the biggest corrillo (a rumour over a head)
##   noche     23:10, a night guard on its round with the lantern
##   corrillo_antes, corrillo_despues (only with --smoke-moments=corrillo) a corrillo of 6 or more at dusk with the
##             player beside it: every bubble and phrase at once (as before), then WorldView's turns (2 at a time)
##   fiesta    the festival FIESTA put in force on its day at 11:00 (as --smoke-script=fiestas does) and played to
##             12:30: its decoration on this town's plaza, ring, main street, town hall and gates (FestivalLayer), and
##             the townsfolk at it
## Prints per shot what is on the map (townsfolk out, walking, stuck, guards on duty, visitors, corrillos) and, at the
## end, the orders refused while playing. --smoke-cities=a,b: only those; --smoke-moments=a,b: only those moments. Quits when done, or after `timeout` seconds
## with a shot of whatever is on screen.

const HERO: String = "chr_0001"
const START: String = "artisan_blacksmith"
const FIESTA: String = "mayday_corpus"

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
	var moments: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
		elif a.begins_with("--seed="):
			world_seed = maxi(1, a.substr(7).to_int())
		elif a.begins_with("--smoke-cities="):
			only = a.substr(15).split(",", false)
		elif a.begins_with("--smoke-moments="):
			moments = a.substr(16).split(",", false)
	_steps = [["plantillas_partida_nueva", _new_game, 1.0]]
	for id: String in NewGame.cities(Data.catalog):
		if not only.is_empty() and not id in only:
			continue
		var all: Array = [["mediodia", _noon.bind(id), 1.2], ["puerta", _gate.bind(id), 1.0]]
		if not _crossing(id).is_empty():
			all.append(["paso", _cross.bind(id), 1.0])
		all += [["ruina", _plot.bind(id, "ruin", "", 12 * 60 + 12), 1.0], ["solar", _plot.bind(id, "lot", "inside", 12 * 60 + 14), 1.0],
			["fuera", _plot.bind(id, "lot", "outside", 12 * 60 + 16), 1.0], ["venta", _plot.bind(id, "for_sale", "", 12 * 60 + 18), 1.0]]
		var m: Dictionary = Data.catalog.maps().get(str(NewGame.city(Data.catalog, id).get("map", "")), {})
		var zi := 0
		for z: Dictionary in m.get("zones", []):  # H13: each zone of the map, its name over it (ZoneLayer)
			all.append(["zona_" + str(z["kind"]), _zone.bind(id, str(z["id"]), _v(z["label"]), 12 * 60 + 20 + zi), 1.0])
			zi += 1
		all += [["atardecer", _dusk.bind(id), 1.2], ["noche", _night.bind(id), 1.2], ["fiesta", _fiesta.bind(id), 1.2]]
		if "corrillo" in moments:  # only when asked: a corrillo of 6 or more with its bubbles and phrases, before/after
			all += [["corrillo_antes", _corrillo.bind(id, false), 1.2], ["corrillo_despues", _corrillo.bind(id, true), 1.2]]
		for s: Array in all:
			if moments.is_empty() and not str(s[0]).begins_with("corrillo") or str(s[0]) in moments \
					or str(s[0]).begins_with("corrillo") and "corrillo" in moments:
				_steps.append(["plantillas_%s_%s" % [id, s[0]], s[1], s[2]])
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


## The first plot of the map (by its order: best located first) of `state` (and `side`), or a business for sale whose
## sign is drawn; the camera on its middle.
func _plot(id: String, state: String, side: String, at: int) -> void:
	if _city != id and not _begin(id):
		return
	_run_to(at)
	app.world().select("")
	var m: Dictionary = Data.catalog.maps().get(Game.sim.state.map_id, {})
	var pick: Dictionary = {}
	for p: Dictionary in m.get("plots", []):
		var shown := str(app.world().plot_layer.shown.get(str(p["id"]), ""))
		if state == "for_sale" and shown == "for_sale" or str(p["state"]) == state and (side == "" or str(p["side"]) == side):
			pick = p
			break
	if pick.is_empty():
		print("[SmokePlantillas] %s: sin parcela %s %s" % [id, state, side])
		return
	var tiles := PlotLayer.tiles_of(pick)
	var c := Vector2.ZERO
	for tt: Vector2i in tiles:
		c += Vector2(tt)
	c /= float(tiles.size())
	_centre(Vector2i(roundi(c.x), roundi(c.y)), 1)
	print("[SmokePlantillas] %s parcela %s: %s %s %s, situación %.2f, %s" % [id, pick["id"], pick["state"], pick["side"],
		pick["zone"], float(pick["location"]), pick.get("site", "")])


## The biggest corrillo of the dusk (the first of 6 or more people, else the biggest by 21:00), the player's
## person beside it (so the rumour is told aloud) and the camera on it; `turns` off = every bubble and phrase at once
## (as before), on = WorldView._take_turns.
## A zone of the map (H13: data/maps "zones"): its label tile at the farthest zoom, where ZoneLayer shows its name.
func _zone(id: String, zone: String, at: Vector2i, minute: int) -> void:
	if _city != id and not _begin(id):
		return
	_run_to(minute)
	app.world().select("")
	_centre(at, 0)
	app.world().zone_layer.update(1)
	_report("%s zona %s" % [id, zone])


func _corrillo(id: String, turns: bool) -> void:
	if not turns:
		if not _begin(id):  # a fresh game: the corrillos form at dusk
			return
		_run_to(_phase_start("dusk"))
		var best := ""
		for i: int in 120:
			var g := Rumors.corrillos(Game.sim)
			for p: String in g:
				if best == "" or (g[p] as Array).size() > (g.get(best, []) as Array).size():
					best = p
			if best != "" and (g.get(best, []) as Array).size() >= 6:
				break
			Game.sim.step()
		_corr_point = best
		var who: Array = Rumors.corrillos(Game.sim).get(best, [])
		if not who.is_empty():
			var at: Array = Life.tile_of(Game.sim.state, str(who[0]))
			var hero: Dictionary = Game.sim.state.characters[HERO]
			hero["location"] = ""
			hero["path"] = []
			for d: Vector2i in [Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2), Vector2i(3, 0), Vector2i(0, 3)]:
				if TownLife._walkable(Game.sim, int(at[0]) + d.x, int(at[1]) + d.y):
					hero["position"] = [int(at[0]) + d.x, int(at[1]) + d.y]
					break
			_centre(_v(at), 1)
		print("[SmokePlantillas] %s corrillo %s: %d personas" % [id, best, who.size()])
	app.world().turns_enabled = turns
	app.world().select("")
	app.world().sync(0.0)
	print("[SmokePlantillas] %s corrillo %s: turnos %s %s" % [id, "sí" if turns else "no", app.world().turns, _corr_point])


var _corr_point: String = ""


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


## The festival FIESTA in force on its day (year 1) at 11:00, its decoration on this town (smoke_fiestas._force).
func _fiesta(id: String) -> void:
	if _city != id and not _begin(id):
		return
	var sim: Sim = Game.sim
	var d := Festivals.def_of(sim, FIESTA)
	var day := 8 + int(d.get("day_of_year", 1))
	sim.state.festivals = Festivals.new_block()
	sim.state.festivals["planned_day"] = day
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + 11 * 60
	var board: Array = sim.state.contracts["board"]
	sim.state.contracts["board"] = board.filter(func(c: Dictionary) -> bool: return not bool(c.get("race", false)))
	var inst_id := Festivals._schedule(sim, FIESTA, day, "smoke", {"hosts": [], "couple": []})
	var inst := Festivals.find(sim, inst_id)
	inst["organized"]["bulls"] = "smoke"
	sim.events = []
	Festivals.step(sim)
	_run_to(12 * 60 + 30)
	app.world().call("_refresh_festivals")
	app.world().select("")
	_centre(_v(Life.plaza(Game.sim)), 0)
	print("[SmokePlantillas] %s fiesta %s en vigor (%s): %s" % [id, FIESTA, inst_id, app.world().festival_layer.shown])


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
