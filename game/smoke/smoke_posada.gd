extends Node
## Scripted capture of the Taberna-Posada (--smoke-script=posada; through `grimoire heavy` with --always-on-top).
## Scenario inn_night (innkeeper_start played by the bot until the fullest minute of a night): the tavern on the map
## (posada_mapa), its interior full at night (posada_noche), the panel's Clientela (posada_clientela), the menu
## (posada_carta), the rooms (posada_habitacion) and the card of the turn summary (posada_resumen). Everything
## through the UI's own calls. Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _tavern: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokePosada] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokePosada] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokePosada] TIMEOUT in step %s" % _step)
		app.save_shot("posada_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_scenario("inn_night")
				if not bool(r.get("ok", false)):
					print("[SmokePosada] scenario failed: %s" % r.get("error", ""))
					get_tree().quit(1)
					return
				Game.start(r["state"])
				Game.set_paused(true)
				for b: String in Game.sim.state.buildings:
					if Inn.is_inn(Game.sim, b):
						_tavern = b
				_go("map")
		"map":
			if _t > 0.3:
				var b: Dictionary = Game.sim.state.buildings[_tavern]
				var o: Array = b["origin"]
				app.world().camera().center_on(Iso.tilef_to_world(Vector2(float(o[0]) + 1.5, float(o[1]) + 1.5)) + Vector2(0, -30))
				app.world().pick_building_id(_tavern)
				_go("shot_map")
		"shot_map":
			if _t > 0.6:
				app.save_shot("posada_mapa")
				var hero := str(Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["head"])
				app.world().select(hero)
				app.open_interior(_tavern, false)
				_go("inside")
		"inside":
			if app.interior_building == _tavern and _t > 1.0:
				var layer: InnLayer = app.interior().inn_layer()
				print("[SmokePosada] guests drawn: %d, inside: %d" % [layer.guest_count() if layer != null else -1,
					Inn.guests(Game.sim, _tavern).size()])
				_go("shot_night")
		"shot_night":
			if _t > 0.5:
				app.save_shot("posada_noche")
				app.interior().show_inn(true)
				app.interior().inn_panel().show_tab("clientele")
				_go("shot_clientele")
		"shot_clientele":
			if _t > 0.6:
				app.save_shot("posada_clientela")
				app.interior().inn_panel().show_tab("menu")
				_go("shot_menu")
		"shot_menu":
			if _t > 0.6:
				app.save_shot("posada_carta")
				app.interior().inn_panel().show_tab("rooms")
				_go("shot_rooms")
		"shot_rooms":
			if _t > 0.6:
				app.save_shot("posada_habitacion")
				app.interior().show_inn(false)
				var card := app.get_node("%InnTurnCard") as InnTurnCard
				card.show_for(Game.sim, _tavern)
				_go("shot_summary")
		"shot_summary":
			if _t > 0.8:
				app.save_shot("posada_resumen")
				_go("done")
				get_tree().quit()
