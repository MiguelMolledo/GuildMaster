extends Node
## Scripted capture of H14 (--smoke-script=ia_familiar; through `grimoire heavy` with the engine's --always-on-top).
## kin_trader: the AI panel of Agnès with Trade first (h14_directivas); the game runs until she walks home from the market
## with what she bought (h14_comerciar); kin_tired: her needs low, home first, with the notices (h14_necesidades).
## Quits when done, or after `timeout` seconds with a shot.

const HERO: String = "chr_0001"

var app: Node = null
var timeout: float = 120.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _wife: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeIaFamiliar] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeIaFamiliar] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _load(id: String) -> bool:
	var r := NewGame.from_scenario(id)
	if not bool(r.get("ok", false)):
		print("[SmokeIaFamiliar] scenario %s failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	app.hud().close_panels()
	Game.start(r["state"])
	Game.set_paused(true)
	app.world().select(HERO)
	_wife = str(Game.sim.state.characters[HERO]["spouse"])
	return true


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeIaFamiliar] TIMEOUT in step %s" % _step)
		app.save_shot("h14_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3 and _load("kin_trader"):
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(22, 18)))
				app.hud().open_kin_ai(_wife)
				_go("shot_panel")
		"shot_panel":
			if _t > 0.8:
				app.save_shot("h14_directivas")
				Game.set_speed(4)
				Game.set_paused(false)
				_go("wait_market")
		"wait_market":
			var bag: Dictionary = Game.sim.state.characters[_wife].get("inventory", {})
			var loc := str(Game.sim.state.characters[_wife].get("location", ""))
			if loc == "" and (Inventory.count(bag, "iron") > 0 or Inventory.count(bag, "coal") > 0):
				var pos: Array = Game.sim.state.characters[_wife]["position"]
				app.hud().kin_ai_panel().close()
				app.world().select(_wife)
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(pos[0]), int(pos[1]))))
				Game.set_paused(true)
				_go("shot_trade")
			elif _t > 40.0:
				_go("shot_trade")
		"shot_trade":
			if _t > 0.8:
				print("[SmokeIaFamiliar] comerciando: %s en %s" % [Game.sim.state.characters[_wife].get("ai"),
					Game.sim.state.characters[_wife].get("position")])
				app.save_shot("h14_comerciar")
				if _load("kin_tired"):
					Game.set_speed(4)
					Game.set_paused(false)
				_go("wait_tired")
		"wait_tired":
			if _t > 3.0:
				Game.set_paused(true)
				app.hud().open_kin_ai(_wife)
				_go("shot_needs")
		"shot_needs":
			if _t > 0.8:
				app.save_shot("h14_necesidades")
				_go("done")
				get_tree().quit(0)
