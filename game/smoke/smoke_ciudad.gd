extends Node
## Scripted capture of H7 (--smoke-script=ciudad; run it through `grimoire heavy` with the engine's --always-on-top).
## plaza_dusk: the sim runs to 20:10 and Hugo stands in the plaza: townsfolk on the benches, chatting, at the dice
## and strolling the market, with their bubbles and the phrases of the ones near Hugo (h7_plaza_atardecer); to 23:00:
## the plaza empty, everybody home (h7_noche); again at dusk with the food stall keeper angry at the family: the
## angry bubble over her and her sheet with the emotion and the actions (h7_ficha_npc). microevent_card: the card of a
## sick employee with its three choices and the time left (h7_microevento). town_microevents: the sim runs until a
## customer waits inside the forge, whose interior shows them at the counter (h7_mostrador). Quits when done, or after
## `timeout` seconds with a shot of whatever is on screen.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var app: Node = null
var timeout: float = 120.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeCiudad] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeCiudad] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _load(id: String) -> bool:
	var r := NewGame.from_scenario(id)
	if not bool(r.get("ok", false)):
		print("[SmokeCiudad] scenario %s failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	Game.start(r["state"])
	Game.set_paused(true)
	return true


## Runs the sim to hh:mm of `day` (the scripted capture skips the wait).
func _run_to(day: int, hh: int, mm: int) -> void:
	var target := day * Clock.MINUTES_PER_DAY + hh * 60 + mm
	var n := target - int(Game.sim.state.clock["minute"])
	if n > 0:
		Game.sim.run_minutes(n)


func _centre(tile: Vector2i) -> void:
	app.world().camera().center_on(Iso.tile_to_world(tile))


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeCiudad] TIMEOUT in step %s" % _step)
		app.save_shot("h7_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3 and _load("plaza_dusk"):
				_run_to(1, 20, 10)
				app.world().select(HERO)
				_centre(Vector2i(19, 20))
				_go("shot_plaza")
		"shot_plaza":
			if _t > 0.8:
				var social := 0
				for id: String in Population.townsfolk(Game.sim.state):
					if str(TownLife.view(Game.sim, id).get("state", "")) in ["social", "market"]:
						social += 1
				print("[SmokeCiudad] plaza al atardecer: %d vecinos socializando" % social)
				app.save_shot("h7_plaza_atardecer")
				_run_to(1, 23, 0)
				_go("shot_night")
		"shot_night":
			if _t > 0.8:
				var home := 0
				for id: String in Population.townsfolk(Game.sim.state):
					if str(Game.sim.state.characters[id]["location"]) == str(Game.sim.state.characters[id]["home"]):
						home += 1
				print("[SmokeCiudad] noche: %d de %d vecinos en casa" % [home, Population.townsfolk(Game.sim.state).size()])
				app.save_shot("h7_noche")
				if _load("plaza_dusk"):
					_run_to(1, 19, 50)
					var keeper := TownLife.stall_keeper(Game.sim.state, Game.sim.catalog, "food")
					Emotions.add(Game.sim, keeper, "angry", FAM)
					app.world().select(HERO)
					var p: Array = Game.sim.state.characters[keeper]["position"]
					_centre(Vector2i(int(p[0]), int(p[1])))
					app.hud().open_npc(keeper)
					_go("shot_npc")
		"shot_npc":
			if _t > 0.8:
				app.save_shot("h7_ficha_npc")
				app.hud().close_panels()
				if _load("microevent_card"):
					_centre(Vector2i(26, 20))
					_go("shot_mev")
		"shot_mev":
			if _t > 0.8:
				app.save_shot("h7_microevento")
				if _load("town_microevents"):
					var guard := 0
					while Counter.customers(Game.sim, FORGE).is_empty() and guard < 900:
						Game.sim.run_minutes(5)
						guard += 5
					print("[SmokeCiudad] cliente en el mostrador: %s (minuto %d)" % [Counter.customers(Game.sim, FORGE),
						int(Game.sim.state.clock["minute"])])
					app.open_interior(FORGE, true)
					_go("shot_counter")
		"shot_counter":
			if _t > 0.8:
				app.save_shot("h7_mostrador")
				_go("done")
				get_tree().quit(0)
