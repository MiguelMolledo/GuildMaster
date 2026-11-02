extends Node
## Scripted capture of H9 (--smoke-script=titulos; run it through `grimoire heavy` with the engine's --always-on-top).
## title_ready: Hugo in front of the town hall; a right click on it opens its panel with Citizen's requirements met
## (h9_ayuntamiento); «Ask for the title» is pressed and the game runs: the ceremony card (h9_ceremonia); the panel
## again, now with Patrician's requirements pending (h9_ayuntamiento_patricio); the book's Reputation tab
## (h9_reputacion). Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

const HERO: String = "chr_0001"

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeTitulos] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeTitulos] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _svc(id: String) -> Dictionary:
	for s: Dictionary in SimQuery.map_services(Game.sim.state, Game.sim.catalog):
		if str(s["id"]) == id:
			return s
	return {}


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeTitulos] TIMEOUT in step %s" % _step)
		app.save_shot("h9_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_scenario("title_ready")
				if not bool(r.get("ok", false)):
					print("[SmokeTitulos] scenario failed: %s" % r.get("error", ""))
					get_tree().quit(1)
					return
				Game.start(r["state"])
				Game.set_paused(true)
				app.world().select(HERO)
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(20, 25)) + Vector2(-60, -110))
				app.world().command_service(_svc("town_hall"))  # what a right click on the town hall does
				_go("shot_hall")
		"shot_hall":
			if _t > 0.8:
				print("[SmokeTitulos] panel abierto=%s, estado=%s" % [app.hud().town_hall_panel().visible,
					Titles.status(Game.sim, HERO)])
				app.save_shot("h9_ayuntamiento")
				(app.hud().town_hall_panel().get_node("%AskButton") as Button).pressed.emit()
				Game.set_paused(false)
				_go("wait_title")
		"wait_title":
			if app.hud().title_card().visible:
				Game.set_paused(true)
				_go("shot_card")
			elif _t > 10.0:
				print("[SmokeTitulos] no ceremony: título=%s" % Titles.current(Game.sim, "fam_0001"))
				_go("shot_card")
		"shot_card":
			if _t > 0.8:
				app.save_shot("h9_ceremonia")
				app.hud().title_card().close()
				app.hud().open_town_hall(HERO)
				_go("shot_hall2")
		"shot_hall2":
			if _t > 0.8:
				app.save_shot("h9_ayuntamiento_patricio")
				app.hud().town_hall_panel().close()
				app.hud().open_ledger("reputation")
				_go("shot_rep")
		"shot_rep":
			if _t > 0.8:
				app.save_shot("h9_reputacion")
				_go("done")
				get_tree().quit(0)
