extends Node
## Scripted capture of H3 (--smoke-script=mercado; run it through `grimoire heavy` with the engine's
## --always-on-top): a new game from the start (NewGame.from_start, normal, moved to 09:00 so the market is open), the
## square with the stalls, the board and the HUD with the family gold, the debt and the objective (h3_plaza); the
## protagonist sent to the resources stall by the same call a right click makes, the market panel on arrival
## (h3_mercado) and an errand bought from it; then to the board, one contract accepted (h3_tablon); into the armory,
## its counter opens the same panel (h3_armeria); the account book on Today and on Debts (h3_libro, h3_libro_deudas);
## the new game screen (h3_partida_nueva) and the ruin screen (h3_ruina). Orders only through the UI paths and
## Game.give. Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

var app: Node = null
var timeout: float = 120.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _who: String = ""
var _fam: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeMercado] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeMercado] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
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
		print("[SmokeMercado] TIMEOUT in step %s" % _step)
		app.save_shot("h3_timeout")
		get_tree().quit(1)
		return
	var hud: Node = app.hud()
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed", "name": "Hugo",
					"female": false, "family_name": "Herrero", "colors": {"primary": "#8b2e2e", "secondary": "#c8a84e"},
					"stats_add": {"craft": 2, "negotiation": 2, "constitution": 1}}, 7)
				if not bool(r.get("ok", false)):
					print("[SmokeMercado] from_start failed: %s" % r.get("error", ""))
					get_tree().quit(1)
					return
				var st: WorldState = r["state"]
				Game.set_time_of_day(st, 9 * 60)
				Game.start(st, Game.sim.catalog)
				_fam = SimQuery.player_family(st)
				_who = SimQuery.family_actor(st, _fam)
				_go("select")
		"select":
			if _t > 0.3:
				app.world().select(_who)
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(18, 18)))
				_go("plaza")
		"plaza":
			if _t > 0.8:
				app.save_shot("h3_plaza")
				app.world().command_service(_svc("resources"))
				_go("to_stall")
		"to_stall":
			if hud.market_panel().visible and _t > 0.3:
				hud.market_panel().set_qty("iron", 0, 2)
				_go("market")
		"market":
			if _t > 0.6:
				app.save_shot("h3_mercado")
				hud.market_panel().buy("iron", 0, 2, str(Market.own_storages(Game.sim, _who)[0]))
				_go("errand")
		"errand":
			if _t > 0.6:
				app.world().command_service(_svc("board"))
				_go("to_board")
		"to_board":
			if hud.board_panel().visible and _t > 0.3:
				var open: Array = Game.sim.state.contracts.get("board", [])
				if not open.is_empty():
					hud.board_panel().accept_contract(str(open[0]["id"]))
				_go("board")
		"board":
			if _t > 0.8:
				app.save_shot("h3_tablon")
				hud.board_panel().close()
				var armory := ""
				for b: String in Game.sim.state.buildings:
					if str(Game.sim.state.buildings[b]["type"]) == "armory":
						armory = b
				app.world().command_enter(armory)
				_go("to_armory")
		"to_armory":
			if app.interior_building != "" and _t > 0.8:
				app.interior().open_shop()
				_go("armory")
		"armory":
			if _t > 0.6:
				app.save_shot("h3_armeria")
				hud.market_panel().close()
				hud.open_ledger("today")
				_go("ledger")
		"ledger":
			if _t > 0.6:
				app.save_shot("h3_libro")
				hud.ledger_panel().show_tab("debts")
				_go("debts")
		"debts":
			if _t > 0.6:
				app.save_shot("h3_libro_deudas")
				hud.ledger_panel().close()
				app.show_new_game()
				_go("new_game")
		"new_game":
			if _t > 0.6:
				app.new_game_screen().add_point("craft", 2)
				app.new_game_screen().add_point("charisma", 1)
				_go("new_game_shot")
		"new_game_shot":
			if _t > 0.4:
				app.save_shot("h3_partida_nueva")
				app.new_game_screen().visible = false
				Game.sim.state.ending = {"kind": "ruin", "family": _fam, "minute": int(Game.sim.state.clock["minute"])}
				_go("ruin")
		"ruin":
			if _t > 0.8:
				app.save_shot("h3_ruina")
				_go("done")
				get_tree().quit()
