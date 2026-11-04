extends Node
## Scripted captures of the living town II (docs/gdd/04f_vida_y_fiestas.md §4.24; --smoke-script=vida; through
## `grimoire heavy` with the engine's --always-on-top). Each step loads its scenario (tools/scenarios/
## make_life_scenarios.gd), runs the sim to its moment, puts the camera there and saves reports/shots/<shot>.png:
##   vida_plaza_atardecer  life_plaza at 19:52: corrillos at the well, the atrium and the gates; a rumour over a head
##   vida_libro_rumores    the family book on its «Rumores» tab
##   vida_guardia_puerta   life_gate at 09:52: the guard at the west gate greeting a merchant from Portvell
##   vida_patrulla_noche   life_night at 23:10: the night round with its lantern
##   vida_altercado        life_altercation: two townsfolk fighting in the plaza, the ring of onlookers, the watch
##   vida_altercado_carta  and its card
##   vida_secuestro_carta  life_kidnap at 18:51: the kidnapping's card (pay, negotiate, rescue, nothing)
## Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

const HERO: String = "chr_0001"

var app: Node = null
var timeout: float = 150.0
var _steps: Array = []
var _i: int = -1
var _t: float = 0.0
var _total: float = 0.0
var _armed: bool = false


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	_steps = [
		["vida_plaza_atardecer", _plaza, 1.2],
		["vida_libro_rumores", _book, 0.8],
		["vida_guardia_puerta", _gate, 1.0],
		["vida_patrulla_noche", _night, 1.0],
		["vida_altercado", _brawl, 1.0],
		["vida_altercado_carta", _brawl_card, 0.8],
		["vida_secuestro_carta", _kidnap, 1.0],
	]
	print("[SmokeVida] start (%d shots, timeout=%.0f s)" % [_steps.size(), timeout])


func _load(id: String) -> bool:
	var r := NewGame.from_scenario(id)
	if not bool(r.get("ok", false)):
		print("[SmokeVida] scenario %s failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	app.hud().close_panels()
	_card().close()
	Game.start(r["state"])
	Game.set_paused(true)
	return true


func _card() -> IncidentCard:
	return app.get_node("%IncidentCard") as IncidentCard


func _run_to(minute_of_day: int) -> void:
	var st := Game.sim.state
	var day := Clock.day(int(st.clock["minute"]))
	var target := day * Clock.MINUTES_PER_DAY + minute_of_day
	if target > int(st.clock["minute"]):
		Game.sim.run_minutes(target - int(st.clock["minute"]))


func _centre(tile: Vector2i, zoom: int = 0) -> void:
	var cam: WorldCamera = app.world().camera()
	cam.zoom_index = clampi(zoom, 0, cam.zoom_levels.size() - 1)
	cam.center_on(Iso.tile_to_world(tile))


func _plaza() -> void:
	if not _load("life_plaza"):
		return
	_run_to(19 * 60 + 52)
	app.world().select(HERO)
	_centre(Vector2i(20, 18))
	var groups := Rumors.corrillos(Game.sim)
	var told: Dictionary = Game.sim.state.town["rumors"]["told"]
	print("[SmokeVida] corrillos %s; rumores en el aire %s; oídos %d" % [groups, told.keys(), Rumors.heard(Game.sim.state).size()])


func _book() -> void:
	app.hud().open_ledger("rumors")
	for r: Dictionary in LifeQuery.book(Game.sim).slice(0, 4):
		print("[SmokeVida] libro: %s — %s" % [r["where"], r["text"]])


func _gate() -> void:
	if not _load("life_gate"):
		return
	_run_to(9 * 60 + 52)
	var at := Vector2i(3, 19)
	for g: String in Watch.guards(Game.sim.state):
		if str(Game.sim.state.characters[g]["guard"]["role"]) == "gate_west_gate":
			var t := Life.tile_of(Game.sim.state, g)
			at = Vector2i(int(t[0]) + 1, int(t[1]))
			app.world().select(g)  # its name over it, and what covers it goes see-through
	_centre(at, 1)
	for g: String in Watch.guards(Game.sim.state):
		print("[SmokeVida] guardia %s %s en %s (fuera=%s)" % [g, Game.sim.state.characters[g]["guard"]["role"],
			Life.tile_of(Game.sim.state, g), Life.offstage(Game.sim.state, g)])
	print("[SmokeVida] forasteros %s" % [Visitors.alive(Game.sim.state)])


func _night() -> void:
	if not _load("life_night"):
		return
	_run_to(23 * 60 + 10)
	var at := Vector2i(20, 18)
	for i: int in 240:  # until the main street's round crosses the plaza
		var g := _guard("night_1")
		var t := Life.tile_of(Game.sim.state, g) if g != "" else [0, 0]
		if g != "" and not Life.offstage(Game.sim.state, g) and int(t[1]) >= 15 and int(t[1]) <= 22 and int(t[0]) >= 15 and int(t[0]) <= 24:
			at = Vector2i(int(t[0]), int(t[1]))
			app.world().select(g)
			break
		Game.sim.step()
	_centre(at, 1)
	print("[SmokeVida] ronda en %s" % at)


func _guard(role: String) -> String:
	for g: String in Watch.guards(Game.sim.state):
		if str(Game.sim.state.characters[g]["guard"]["role"]) == role:
			return g
	return ""


func _brawl() -> void:
	if not _load("life_altercation"):
		return
	for i: int in 90:
		Game.sim.step()
		var a := Incidents.active(Game.sim.state)
		if not a.is_empty() and str(a[0].get("phase", "")) == "fighting" and int(Game.sim.state.clock["minute"]) >= int(a[0].get("fight_until", 0)) - 18:
			break
	var act := Incidents.active(Game.sim.state)
	if not act.is_empty():
		var tile: Array = act[0]["tile"]
		_centre(Vector2i(int(tile[0]), int(tile[1])), 1)
		print("[SmokeVida] pelea %s: %s, mirones %s" % [act[0]["id"], act[0]["people"], act[0].get("watchers", [])])
	app.world().select(HERO)


func _brawl_card() -> void:
	_card().follow(Game.sim, [])
	print("[SmokeVida] carta del altercado visible=%s" % _card().visible)


func _kidnap() -> void:
	if not _load("life_kidnap"):
		return
	_run_to(18 * 60 + 51)
	_card().follow(Game.sim, [])
	print("[SmokeVida] carta del secuestro visible=%s (%s)" % [_card().visible, _card().incident_id])


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeVida] TIMEOUT in step %d" % _i)
		app.save_shot("vida_timeout")
		get_tree().quit(1)
		return
	if _i >= _steps.size():
		return
	if _i < 0 or (_armed and _t > float(_steps[_i][2])):
		if _i >= 0:
			app.save_shot(str(_steps[_i][0]))
			print("[SmokeVida] shot %s" % _steps[_i][0])
		_i += 1
		_t = 0.0
		_armed = false
		if _i >= _steps.size():
			print("[SmokeVida] done")
			get_tree().quit(0)
			return
		(_steps[_i][1] as Callable).call()
		_armed = true
