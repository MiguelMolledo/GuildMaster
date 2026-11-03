extends Node
## Scripted capture of H13 · seasons and global events (--smoke-script=eventos; run it through `grimoire heavy` with
## the engine's --always-on-top). season_events at 23:50 of a winter day with a war and a festival: the game runs past
## midnight; the festival ends and the next day's roll starts another event: the notices zone and the clock with the
## events in force (h13_avisos). The same scenario at 10:00: the protagonist goes to the resources stall, the market
## panel says why each price moves (h13_mercado); the account book on Today with the season's prices and each event
## with its time left (h13_libro). Orders only through the UI paths. Quits when done, or after `timeout` seconds.

const SCENARIO: String = "season_events"
const DAY: int = 1440

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _who: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeEventos] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeEventos] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _load(at: int) -> bool:
	var r := NewGame.from_scenario(SCENARIO)
	if not bool(r.get("ok", false)):
		print("[SmokeEventos] scenario %s failed: %s" % [SCENARIO, r.get("error", "")])
		get_tree().quit(1)
		return false
	var st: WorldState = r["state"]
	if at >= 0:
		Game.set_time_of_day(st, at)
	app.hud().close_panels()
	Game.start(st, Game.sim.catalog)
	Game.set_paused(false)
	_who = SimQuery.family_actor(st, SimQuery.player_family(st))
	app.world().select(_who)
	return true


func _svc(id: String) -> Dictionary:
	for s: Dictionary in SimQuery.map_services(Game.sim.state, Game.sim.catalog):
		if str(s["id"]) == id:
			return s
	return {}


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeEventos] TIMEOUT in step %s" % _step)
		app.save_shot("h13_timeout")
		get_tree().quit(1)
		return
	var hud: Node = app.hud()
	match _step:
		"start":
			if _t > 0.3 and _load(-1):
				_go("midnight")
		"midnight":
			if int(Game.sim.state.clock["minute"]) >= 7 * DAY + 3 and _t > 0.5:
				print("[SmokeEventos] notices on screen: %s" % [hud.shown_notices()])
				print("[SmokeEventos] events: %s" % [SimQuery.events_line(Game.sim)])
				app.save_shot("h13_avisos")
				_go("morning")
		"morning":
			if _t > 0.3 and _load(10 * 60):
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(18, 18)))
				app.world().command_service(_svc("resources"))
				_go("to_stall")
		"to_stall":
			if hud.market_panel().visible and _t > 0.5:
				_go("market")
		"market":
			if _t > 0.6:
				print("[SmokeEventos] wheat: %s" % SimQuery.price_reason(Game.sim, "wheat"))
				app.save_shot("h13_mercado")
				hud.market_panel().close()
				hud.open_ledger("today")
				_go("ledger")
		"ledger":
			if _t > 0.6:
				app.save_shot("h13_libro")
				hud.ledger_panel().close()
				_go("done")
				get_tree().quit()
